import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_kit_photo_overrides.dart';
import 'package:as_grinta/features/sports_management/data/player_identity_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/composition_publication_rules.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_player_grouping.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_identity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show CompositionPlayerTile, PlayerAvatar, SubstituteHistoryBadge;
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'internal_team_composition_widgets.dart';

/// Composition visuelle d'un « match entre nous ».
///
/// Les équipes restent libres et peuvent être inégales. Jusqu'à 11 joueurs
/// sont placés sur le terrain ; si une équipe dépasse 11 joueurs, le surplus
/// reste explicitement sur le banc.
class InternalTeamCompositionView extends ConsumerStatefulWidget {
  const InternalTeamCompositionView({
    super.key,
    required this.matchId,
    required this.editable,
  });

  final String matchId;
  final bool editable;

  @override
  ConsumerState<InternalTeamCompositionView> createState() =>
      _InternalTeamCompositionViewState();
}

class _InternalTeamCompositionViewState
    extends ConsumerState<InternalTeamCompositionView> {
  final _team1Controller = TextEditingController();
  final _team2Controller = TextEditingController();

  List<InternalCompositionEntry>? _entries;
  JerseyOption _team1Jersey = JerseyOption.orange;
  JerseyOption _team2Jersey = JerseyOption.blue;
  String? _team1FormationCode;
  String? _team2FormationCode;
  String? _selectedParticipantId;
  bool _dirty = false;
  bool _saving = false;
  bool _syncingNames = false;
  bool _notificationSent = false;
  int _viewMode = 0;
  int _terrainTeam = 1;

  @override
  void initState() {
    super.initState();
    if (!widget.editable) _viewMode = 1;
    _team1Controller.addListener(_handleTeamNameChanged);
    _team2Controller.addListener(_handleTeamNameChanged);
  }

  @override
  void dispose() {
    _team1Controller
      ..removeListener(_handleTeamNameChanged)
      ..dispose();
    _team2Controller
      ..removeListener(_handleTeamNameChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTeamNameChanged() {
    if (!mounted || _syncingNames) return;
    setState(() => _dirty = true);
  }

  void _initFrom(InternalMatchComposition composition) {
    _syncingNames = true;
    _team1Controller.text = composition.team1Name;
    _team2Controller.text = composition.team2Name;
    _syncingNames = false;
    final team1Count =
        composition.entries.where((entry) => entry.teamNo == 1).length;
    final team2Count =
        composition.entries.where((entry) => entry.teamNo == 2).length;
    final automaticTeam1 =
        internalDefaultFormationForPlayerCount(team1Count)?.code;
    final automaticTeam2 =
        internalDefaultFormationForPlayerCount(team2Count)?.code;
    final resetTeam1 = composition.team1FormationCode != null &&
        composition.team1FormationCode != automaticTeam1;
    final resetTeam2 = composition.team2FormationCode != null &&
        composition.team2FormationCode != automaticTeam2;
    _entries = [
      for (final entry in composition.entries)
        if ((entry.teamNo == 1 && resetTeam1) ||
            (entry.teamNo == 2 && resetTeam2))
          entry.copyWith(clearPlacement: true)
        else
          entry,
    ];
    _team1FormationCode = automaticTeam1;
    _team2FormationCode = automaticTeam2;
    _notificationSent = composition.notificationSent;

    final team1 =
        JerseyOption.fromId(composition.team1JerseyId) ?? JerseyOption.orange;
    final requestedTeam2 =
        JerseyOption.fromId(composition.team2JerseyId) ?? JerseyOption.blue;
    _team1Jersey = team1;
    _team2Jersey = requestedTeam2 == team1
        ? JerseyOption.values.firstWhere((option) => option != team1)
        : requestedTeam2;
  }

  void _selectPlayer(InternalCompositionEntry entry) {
    if (!widget.editable) return;
    setState(() {
      _selectedParticipantId = _selectedParticipantId == entry.participantId
          ? null
          : entry.participantId;
    });
  }

  InternalCompositionEntry? get _selectedEntry {
    final entries = _entries;
    final selectedId = _selectedParticipantId;
    if (entries == null || selectedId == null) return null;
    for (final entry in entries) {
      if (entry.participantId == selectedId) return entry;
    }
    return null;
  }

  void _assignSelectedToTeam(int teamNo) {
    final entries = _entries;
    final selected = _selectedEntry;
    if (!widget.editable || entries == null || selected == null) return;

    final index = entries.indexWhere(
      (entry) => entry.participantId == selected.participantId,
    );
    if (index == -1) return;

    setState(() {
      final oldTeam = selected.teamNo;
      final nextTeam = oldTeam == teamNo ? null : teamNo;
      entries[index] = selected.copyWith(
        teamNo: nextTeam,
        clearTeam: nextTeam == null,
        clearPlacement: true,
      );
      if (oldTeam != null) _invalidateTeamLayout(oldTeam);
      if (nextTeam != null) _invalidateTeamLayout(nextTeam);
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _moveSelectedToUnassigned() {
    final entries = _entries;
    final selected = _selectedEntry;
    if (!widget.editable || entries == null || selected?.teamNo == null) return;
    final index = entries.indexWhere(
      (entry) => entry.participantId == selected!.participantId,
    );
    if (index == -1) return;

    setState(() {
      final oldTeam = selected!.teamNo!;
      entries[index] = selected.copyWith(clearTeam: true, clearPlacement: true);
      _invalidateTeamLayout(oldTeam);
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _invalidateTeamLayout(int teamNo) {
    final entries = _entries;
    if (entries == null) return;
    for (var index = 0; index < entries.length; index += 1) {
      if (entries[index].teamNo == teamNo &&
          entries[index].zone != 'available') {
        entries[index] = entries[index].copyWith(clearPlacement: true);
      }
    }
    final teamCount = entries.where((entry) => entry.teamNo == teamNo).length;
    final automaticCode =
        internalDefaultFormationForPlayerCount(teamCount)?.code;
    if (teamNo == 1) {
      _team1FormationCode = automaticCode;
    } else {
      _team2FormationCode = automaticCode;
    }
  }

  void _dropOnClassicSlot(
    int teamNo,
    MatchCompositionEntry moving,
    FootballFormationSlot slot,
  ) {
    final entries = _entries;
    if (!widget.editable || entries == null) return;
    final movingIndex = entries.indexWhere(
      (entry) =>
          entry.participantId == moving.participantId && entry.teamNo == teamNo,
    );
    if (movingIndex == -1) return;
    final current = entries[movingIndex];
    final occupantIndex = entries.indexWhere(
      (entry) =>
          entry.teamNo == teamNo &&
          entry.zone == 'field' &&
          entry.slotLabel == slot.label &&
          entry.participantId != moving.participantId,
    );
    final previousX = current.zone == 'field' ? current.x : null;
    final previousY = current.zone == 'field' ? current.y : null;
    final previousSlot = current.zone == 'field' ? current.slotLabel : null;
    final benchCount = entries
        .where((entry) => entry.teamNo == teamNo && entry.zone == 'bench')
        .length;

    setState(() {
      entries[movingIndex] = current.copyWith(
        zone: 'field',
        x: slot.position.dx,
        y: slot.position.dy,
        slotLabel: slot.label,
      );
      if (occupantIndex >= 0) {
        final occupant = entries[occupantIndex];
        entries[occupantIndex] = previousSlot == null
            ? occupant.copyWith(
                zone: 'bench',
                sortOrder: benchCount,
                clearSlot: true,
              )
            : occupant.copyWith(
                zone: 'field',
                x: previousX,
                y: previousY,
                slotLabel: previousSlot,
              );
      }
      _dirty = true;
    });
  }

  void _moveClassicToBench(int teamNo, MatchCompositionEntry moving) {
    final entries = _entries;
    if (!widget.editable || entries == null) return;
    final index = entries.indexWhere(
      (entry) =>
          entry.participantId == moving.participantId && entry.teamNo == teamNo,
    );
    if (index == -1) return;
    final teamSize = entries.where((entry) => entry.teamNo == teamNo).length;
    if (teamSize <= 11) {
      _showMessage('Le banc apparaît seulement au-delà de 11 joueurs.');
      return;
    }
    final benchCount = entries
        .where((entry) => entry.teamNo == teamNo && entry.zone == 'bench')
        .length;
    setState(() {
      entries[index] = entries[index].copyWith(
        zone: 'bench',
        sortOrder: benchCount,
        clearSlot: true,
      );
      _dirty = true;
    });
  }

  void _changeJersey(int teamNo, JerseyOption jersey) {
    if (!widget.editable) return;
    setState(() {
      if (teamNo == 1) {
        if (jersey == _team1Jersey) return;
        if (jersey == _team2Jersey) _team2Jersey = _team1Jersey;
        _team1Jersey = jersey;
      } else {
        if (jersey == _team2Jersey) return;
        if (jersey == _team1Jersey) _team1Jersey = _team2Jersey;
        _team2Jersey = jersey;
      }
      _dirty = true;
    });
  }

  Future<void> _savePaper() async {
    final entries = _entries;
    if (entries == null || _saving) return;

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(internalMatchCompositionRepositoryProvider)
          .savePaperState(
            matchId: widget.matchId,
            team1Name: _team1Controller.text,
            team2Name: _team2Controller.text,
            team1JerseyId: _team1Jersey.id,
            team2JerseyId: _team2Jersey.id,
            team1FormationCode: _team1FormationCode,
            team2FormationCode: _team2FormationCode,
            entries: entries,
          );
      if (!mounted) return;
      setState(() {
        _initFrom(saved);
        _selectedParticipantId = null;
        _dirty = false;
      });
      ref.invalidate(internalMatchCompositionProvider(widget.matchId));
      _showMessage('Composition enregistrée.');
    } catch (error, stackTrace) {
      AppLogger.error(
          'sports.internal_composition.save_paper', error, stackTrace);
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final entries = _entries;
    if (entries == null || _saving) return;
    final validation = _validation(entries);
    if (!validation.canSave) {
      _showMessage(validation.message);
      return;
    }

    if (compositionPublicationWillNotify(
      alreadyPublished: _notificationSent,
      sheetNamesPlayers: entries.isNotEmpty,
      postMatch: false,
    )) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mettre les compositions en ligne ?'),
          content: const Text(
            'Enregistrer les deux terrains enverra « Les compositions sont '
            'en ligne » aux joueurs convoqués.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Valider'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(internalMatchCompositionRepositoryProvider).saveVisual(
                matchId: widget.matchId,
                team1Name: _team1Controller.text,
                team2Name: _team2Controller.text,
                team1JerseyId: _team1Jersey.id,
                team2JerseyId: _team2Jersey.id,
                team1FormationCode: _team1FormationCode!,
                team2FormationCode: _team2FormationCode!,
                entries: entries,
              );
      if (!mounted) return;
      setState(() {
        _initFrom(saved);
        _selectedParticipantId = null;
        _dirty = false;
      });
      ref.invalidate(internalMatchCompositionProvider(widget.matchId));
      _showMessage('Composition enregistrée.');
    } catch (error, stackTrace) {
      AppLogger.error('sports.internal_composition.save', error, stackTrace);
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetComposition() async {
    final entries = _entries;
    if (entries == null || _saving) return;
    final hasWork = entries.any(
          (entry) => entry.teamNo != null || entry.slotLabel != null,
        ) ||
        _team1FormationCode != null ||
        _team2FormationCode != null;
    if (!hasWork) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Réinitialiser les compositions ?'),
        content: const Text(
          'Tous les joueurs des deux équipes seront remis dans '
          '« Non affectés ». Les noms d’équipe et les maillots seront conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(internalMatchCompositionRepositoryProvider)
          .resetVisual(widget.matchId);
      if (!mounted) return;
      setState(() {
        _initFrom(saved);
        _selectedParticipantId = null;
        _dirty = false;
      });
      ref.invalidate(internalMatchCompositionProvider(widget.matchId));
      _showMessage('Compositions remises à zéro.');
    } catch (error, stackTrace) {
      AppLogger.error('sports.internal_composition.reset', error, stackTrace);
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  _InternalValidation _validation(List<InternalCompositionEntry> entries) {
    final unassigned = entries.where((entry) => entry.teamNo == null).length;
    final team1 = entries.where((entry) => entry.teamNo == 1).toList();
    final team2 = entries.where((entry) => entry.teamNo == 2).toList();
    if (entries.isEmpty) {
      return const _InternalValidation(false, 'Aucun joueur convoqué.', 0);
    }
    if (unassigned > 0) {
      return _InternalValidation(
        false,
        'Il reste $unassigned joueur${unassigned > 1 ? 's' : ''} non affecté${unassigned > 1 ? 's' : ''}.',
        unassigned,
      );
    }
    if (team1.isEmpty || team2.isEmpty) {
      return const _InternalValidation(
        false,
        'Les deux équipes doivent contenir au moins un joueur.',
        0,
      );
    }
    final formation1 = internalFormationByCode(
      playerCount: team1.length,
      code: _team1FormationCode,
    );
    final formation2 = internalFormationByCode(
      playerCount: team2.length,
      code: _team2FormationCode,
    );
    if (formation1 == null || formation2 == null) {
      return const _InternalValidation(
        false,
        'Choisis la formation de chaque équipe.',
        0,
      );
    }
    final requiredStarters1 = team1.length > 11 ? 11 : team1.length;
    final requiredStarters2 = team2.length > 11 ? 11 : team2.length;
    final starters1 =
        team1.where((entry) => entry.zone == 'field').toList(growable: false);
    final starters2 =
        team2.where((entry) => entry.zone == 'field').toList(growable: false);
    final bench1 = team1.where((entry) => entry.zone == 'bench').length;
    final bench2 = team2.where((entry) => entry.zone == 'bench').length;
    if (starters1.length != requiredStarters1 ||
        starters2.length != requiredStarters2 ||
        bench1 != (team1.length - requiredStarters1) ||
        bench2 != (team2.length - requiredStarters2)) {
      return const _InternalValidation(
        false,
        'Place tous les titulaires sur le terrain. Au-delà de 11 joueurs, le surplus reste sur le banc.',
        0,
      );
    }
    final invalid1 = starters1.any(
      (entry) => !formation1.containsSlot(entry.slotLabel),
    );
    final invalid2 = starters2.any(
      (entry) => !formation2.containsSlot(entry.slotLabel),
    );
    if (invalid1 || invalid2) {
      return const _InternalValidation(
        false,
        'Un joueur occupe un poste qui n’appartient pas à la formation choisie.',
        0,
      );
    }
    if (_hasDuplicateSlots(starters1) || _hasDuplicateSlots(starters2)) {
      return const _InternalValidation(
        false,
        'Deux joueurs ne peuvent pas occuper le même poste.',
        0,
      );
    }
    return const _InternalValidation(true, '', 0);
  }

  bool _hasDuplicateSlots(List<InternalCompositionEntry> entries) {
    final slots =
        entries.map((entry) => entry.slotLabel).whereType<String>().toList();
    return slots.toSet().length != slots.length;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(internalMatchCompositionProvider(widget.matchId));
    final kitPhotosAsync = ref.watch(internalTeamKitPhotosProvider);
    if (kitPhotosAsync.isLoading) {
      return const Center(child: GrintaProgressIndicator());
    }
    final kitPhotos =
        kitPhotosAsync.valueOrNull ?? const <String, Map<String, String>>{};
    final benchCountsAsync = ref.watch(
      _internalBenchCountsProvider(widget.matchId),
    );
    final positionArchive = widget.editable
        ? ref.watch(playerPositionArchiveProvider).valueOrNull
        : const <String, PlayerPositionProfile>{};

    return async.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (_, __) => const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Composition indisponible.'),
        ),
      ),
      data: (composition) {
        if (composition == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Match entre nous introuvable.'),
            ),
          );
        }
        _entries ??= List.of(composition.entries);
        if (!_dirty && _team1Controller.text.isEmpty) _initFrom(composition);

        // Display-only photos: team changes and jersey changes update instantly.
        // The persisted composition always retains the original France photo.
        final entries = [
          for (final entry in _entries!)
            if (!entry.isGuest &&
                entry.teamNo != null &&
                entry.seasonPlayerId != null)
              entry.copyWith(
                photoUrl: kitPhotos[entry.seasonPlayerId]?[kitPhotoColumn(
                      entry.teamNo == 1 ? _team1Jersey.id : _team2Jersey.id,
                    )] ??
                    entry.photoUrl,
              )
            else
              entry,
        ];
        final unassigned =
            entries.where((entry) => entry.teamNo == null).toList();
        final profilesByName = <String, PlayerPositionProfile>{
          for (final profile
              in (positionArchive ?? const <String, PlayerPositionProfile>{})
                  .values)
            normalizePlayerName(profile.displayName): profile,
        };
        List<InternalCompositionEntry> unassignedGroup(
          InternalPlayerGroup group,
        ) =>
            unassigned
                .where(
                  (entry) =>
                      internalPlayerGroupFor(
                        isGuest: entry.isGuest,
                        isGoalkeeper: entry.isGoalkeeper,
                        profile: profilesByName[
                            normalizePlayerName(entry.displayName)],
                      ) ==
                      group,
                )
                .toList(growable: false);
        final unassignedDefenders =
            unassignedGroup(InternalPlayerGroup.defenders);
        final unassignedMidfielders =
            unassignedGroup(InternalPlayerGroup.midfielders);
        final unassignedAttackers =
            unassignedGroup(InternalPlayerGroup.attackers);
        final unassignedOther = unassignedGroup(InternalPlayerGroup.other);
        final team1 = entries.where((entry) => entry.teamNo == 1).toList();
        final team2 = entries.where((entry) => entry.teamNo == 2).toList();
        final benchCounts =
            benchCountsAsync.valueOrNull ?? const <String, int>{};
        final validation = _validation(entries);
        final expectedTeam1Code =
            internalDefaultFormationForPlayerCount(team1.length)?.code;
        final expectedTeam2Code =
            internalDefaultFormationForPlayerCount(team2.length)?.code;
        final legacyReadOnly = !widget.editable &&
            (!composition.isVisualComplete ||
                composition.team1FormationCode != expectedTeam1Code ||
                composition.team2FormationCode != expectedTeam2Code);

        final terrainEntries = _terrainTeam == 1 ? team1 : team2;
        final terrainCard = _InternalTeamCard(
          name: _terrainTeam == 1
              ? (_team1Controller.text.isEmpty
                  ? composition.team1Name
                  : _team1Controller.text)
              : (_team2Controller.text.isEmpty
                  ? composition.team2Name
                  : _team2Controller.text),
          controller: widget.editable
              ? (_terrainTeam == 1 ? _team1Controller : _team2Controller)
              : null,
          teamNo: _terrainTeam,
          jersey: _terrainTeam == 1 ? _team1Jersey : _team2Jersey,
          unavailableJersey: _terrainTeam == 1 ? _team2Jersey : _team1Jersey,
          entries: terrainEntries,
          editable: widget.editable,
          canReceiveSelected:
              _selectedEntry != null && _selectedEntry!.teamNo != _terrainTeam,
          onAssignSelected: () => _assignSelectedToTeam(_terrainTeam),
          onJerseySelected: (jersey) => _changeJersey(_terrainTeam, jersey),
          onDroppedOnSlot: (moving, slot) =>
              _dropOnClassicSlot(_terrainTeam, moving, slot),
          onRemoveFromField: (moving) =>
              _moveClassicToBench(_terrainTeam, moving),
          finishedBenchCounts: benchCounts,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.editable) ...[
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('Sur papier'),
                    icon: Icon(Icons.list_alt_rounded),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Sur terrain'),
                    icon: Icon(Icons.sports_soccer_rounded),
                  ),
                ],
                selected: {_viewMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() {
                    _viewMode = selection.first;
                    _selectedParticipantId = null;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_viewMode == 0) ...[
              if (unassigned.isNotEmpty || widget.editable) ...[
                Text(
                  'Non affectés (${unassigned.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _GroupedUnassignedPools(
                  defenders: unassignedDefenders,
                  midfielders: unassignedMidfielders,
                  attackers: unassignedAttackers,
                  other: unassignedOther,
                  editable: widget.editable,
                  selectedParticipantId: _selectedParticipantId,
                  canReceiveSelected: _selectedEntry?.teamNo != null,
                  onPoolTap: _moveSelectedToUnassigned,
                  onPlayerTap: _selectPlayer,
                ),
                const SizedBox(height: 16),
              ],
              _PaperTeams(
                team1Name: composition.team1Name,
                team2Name: composition.team2Name,
                team1Controller: widget.editable ? _team1Controller : null,
                team2Controller: widget.editable ? _team2Controller : null,
                team1Jersey: _team1Jersey,
                team2Jersey: _team2Jersey,
                team1: team1,
                team2: team2,
                editable: widget.editable,
                selectedParticipantId: _selectedParticipantId,
                onAssignTeam1: () => _assignSelectedToTeam(1),
                onAssignTeam2: () => _assignSelectedToTeam(2),
                onJersey1: (jersey) => _changeJersey(1, jersey),
                onJersey2: (jersey) => _changeJersey(2, jersey),
                onPlayerTap: _selectPlayer,
              ),
            ] else ...[
              SegmentedButton<int>(
                segments: [
                  ButtonSegment<int>(
                    value: 1,
                    label: Text(
                      _team1Controller.text.trim().isEmpty
                          ? composition.team1Name
                          : _team1Controller.text.trim(),
                    ),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    label: Text(
                      _team2Controller.text.trim().isEmpty
                          ? composition.team2Name
                          : _team2Controller.text.trim(),
                    ),
                  ),
                ],
                selected: {_terrainTeam},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() {
                    _terrainTeam = selection.first;
                    _selectedParticipantId = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              if (legacyReadOnly)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Les compositions ne sont pas encore en ligne.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                terrainCard,
            ],
            if (widget.editable) ...[
              const SizedBox(height: 16),
              if (_viewMode == 1 && !validation.canSave)
                Text(
                  validation.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _resetComposition,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Réinitialiser'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : _viewMode == 0
                        ? _savePaper
                        : validation.canSave
                            ? _save
                            : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: GrintaProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer la composition'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _InternalValidation {
  const _InternalValidation(this.canSave, this.message, this.unassignedCount);

  final bool canSave;
  final String message;
  final int unassignedCount;
}

/// Profils indexés par participant du match. On réutilise exactement la même
/// identité canonique et le même historique que la simulation du onze.
final _internalBenchCountsProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String>((ref, matchId) async {
  try {
    final history = await ref
        .watch(matchCompositionRepositoryProvider)
        .fetchFinishedBenchHistory(matchId);
    return history.counts;
  } catch (_) {
    return const {};
  }
});
