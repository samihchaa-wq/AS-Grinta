import 'dart:math';

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/player_identity_repository.dart';
import 'package:as_grinta/features/sports_management/domain/composition_publication_rules.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_formation.dart';
import 'package:as_grinta/features/sports_management/domain/composition_simulation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show CompositionPlayerTile, PlayerAvatar, SubstituteHistoryBadge;
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    _entries = List.of(composition.entries);
    _team1FormationCode = composition.team1FormationCode;
    _team2FormationCode = composition.team2FormationCode;
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

  void _moveSelectedToBench(int teamNo) {
    final entries = _entries;
    final selected = _selectedEntry;
    if (!widget.editable ||
        entries == null ||
        selected == null ||
        selected.teamNo != teamNo ||
        selected.slotLabel == null) {
      return;
    }
    final teamSize = entries.where((entry) => entry.teamNo == teamNo).length;
    if (teamSize <= 11) {
      _showMessage('Le banc apparaît seulement au-delà de 11 joueurs.');
      return;
    }
    final index = entries.indexWhere(
      (entry) => entry.participantId == selected.participantId,
    );
    if (index == -1) return;
    setState(() {
      entries[index] = selected.copyWith(
        zone: 'bench',
        clearSlot: true,
      );
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _invalidateTeamLayout(int teamNo) {
    final entries = _entries;
    if (entries == null) return;
    for (var index = 0; index < entries.length; index += 1) {
      if (entries[index].teamNo == teamNo && entries[index].slotLabel != null) {
        entries[index] = entries[index].copyWith(clearPlacement: true);
      }
    }
    if (teamNo == 1) {
      _team1FormationCode = null;
    } else {
      _team2FormationCode = null;
    }
  }

  void _changeFormation(int teamNo, String code) {
    final entries = _entries;
    if (!widget.editable || entries == null) return;
    final team = entries.where((entry) => entry.teamNo == teamNo).toList();
    final formation = internalFormationByCode(
      playerCount: team.length,
      code: code,
    );
    if (formation == null) return;

    final field = team.where((entry) => entry.zone == 'field').toList();
    final ordered = [
      ...field.where((entry) => entry.isGoalkeeper),
      ...field.where((entry) => !entry.isGoalkeeper),
    ];
    final placement = <String, FootballFormationSlot>{};
    final overflow = <String>{};
    for (var index = 0; index < ordered.length; index += 1) {
      if (index < formation.slots.length) {
        placement[ordered[index].participantId] = formation.slots[index];
      } else {
        overflow.add(ordered[index].participantId);
      }
    }
    final benchBase =
        team.where((entry) => entry.zone == 'bench').length;
    var extraBench = 0;

    setState(() {
      for (var index = 0; index < entries.length; index += 1) {
        final entry = entries[index];
        if (entry.teamNo != teamNo) continue;
        if (placement[entry.participantId] case final slot?) {
          entries[index] = entry.copyWith(
            zone: 'field',
            x: slot.position.dx,
            y: slot.position.dy,
            slotLabel: slot.label,
          );
        } else if (overflow.contains(entry.participantId)) {
          entries[index] = entry.copyWith(
            zone: 'bench',
            sortOrder: benchBase + extraBench++,
            clearSlot: true,
          );
        }
      }
      if (teamNo == 1) {
        _team1FormationCode = code;
      } else {
        _team2FormationCode = code;
      }
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _onPitchSlotTap({
    required int teamNo,
    required String slotLabel,
    required InternalCompositionEntry? occupant,
  }) {
    if (!widget.editable) return;
    final entries = _entries;
    if (entries == null) return;
    final selected = _selectedEntry;

    if (selected == null) {
      if (occupant != null) _selectPlayer(occupant);
      return;
    }
    if (selected.teamNo != teamNo) {
      _showMessage('Affecte d’abord ce joueur à cette équipe.');
      return;
    }
    if (occupant?.participantId == selected.participantId) {
      setState(() => _selectedParticipantId = null);
      return;
    }

    final selectedIndex = entries.indexWhere(
      (entry) => entry.participantId == selected.participantId,
    );
    if (selectedIndex == -1) return;
    final previousSlot = selected.slotLabel;
    final occupantIndex = occupant == null
        ? -1
        : entries.indexWhere(
            (entry) => entry.participantId == occupant.participantId,
          );

    setState(() {
      entries[selectedIndex] = selected.copyWith(slotLabel: slotLabel);
      if (occupantIndex >= 0 && occupant != null) {
        entries[occupantIndex] = previousSlot == null
            ? occupant.copyWith(clearSlot: true)
            : occupant.copyWith(slotLabel: previousSlot);
      }
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  MatchCompositionEntry _asClassicEntry(InternalCompositionEntry entry) {
    return MatchCompositionEntry(
      participantId: entry.participantId,
      seasonPlayerId: entry.seasonPlayerId ?? '',
      guestPlayerId: entry.guestPlayerId,
      displayName: entry.displayName,
      lastInitial: entry.lastInitial,
      isGuest: entry.isGuest,
      isGoalkeeper: entry.isGoalkeeper,
      zone: MatchCompositionZone.fromWire(entry.zone),
      x: entry.x,
      y: entry.y,
      slotLabel: entry.slotLabel,
      photoUrl: entry.photoUrl,
      sortOrder: entry.sortOrder,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: switch (entry.zone) {
        'field' => 'starter',
        'bench' => 'substitute',
        _ => 'undecided',
      },
    );
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
    final benchCount =
        entries.where((entry) => entry.teamNo == teamNo && entry.zone == 'bench').length;

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
    final benchCount =
        entries.where((entry) => entry.teamNo == teamNo && entry.zone == 'bench').length;
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

  Future<void> _simulate(
    Map<String, PlayerPositionProfile> profiles,
    Map<String, int> benchCounts,
  ) async {
    final entries = _entries;
    if (!widget.editable || entries == null || _saving) return;
    final validation = _validation(entries);
    if (validation.unassignedCount > 0) {
      _showMessage('Répartis d’abord tous les joueurs dans les deux équipes.');
      return;
    }

    SimulatedComposition runForTeam(
      List<InternalCompositionEntry> team,
      InternalTeamFormation formation,
    ) {
      final declaredGoalkeepers =
          team.where((entry) => entry.isGoalkeeper && !entry.isGuest).toList();
      String? randomGoalkeeperId;
      if (declaredGoalkeepers.isEmpty && team.isNotEmpty) {
        randomGoalkeeperId =
            team[Random.secure().nextInt(team.length)].participantId;
      }
      return simulateComposition(
        slots: formation.slots,
        candidates: [
          for (final entry in team)
            SimulationCandidate(
              participantId: entry.participantId,
              displayName: entry.displayName,
              benchCount: benchCounts[entry.participantId] ?? 0,
              profile: profiles[entry.participantId],
              isGuest: entry.isGuest,
              isGoalkeeper:
                  entry.isGoalkeeper || entry.participantId == randomGoalkeeperId,
            ),
        ],
      );
    }

    final team1 = entries.where((entry) => entry.teamNo == 1).toList();
    final team2 = entries.where((entry) => entry.teamNo == 2).toList();
    final formation1 = internalFormationByCode(
      playerCount: team1.length,
      code: _team1FormationCode,
    );
    final formation2 = internalFormationByCode(
      playerCount: team2.length,
      code: _team2FormationCode,
    );
    if (formation1 == null || formation2 == null) {
      _showMessage('Choisis la formation de chaque équipe avant de simuler.');
      return;
    }

    final simulation1 = runForTeam(team1, formation1);
    final simulation2 = runForTeam(team2, formation2);
    final placed = <String, FootballFormationSlot>{
      for (final placement in simulation1.placements)
        placement.candidate.participantId: placement.slot,
      for (final placement in simulation2.placements)
        placement.candidate.participantId: placement.slot,
    };
    final bench = <String, int>{
      for (var i = 0; i < simulation1.bench.length; i += 1)
        simulation1.bench[i].participantId: i,
      for (var i = 0; i < simulation2.bench.length; i += 1)
        simulation2.bench[i].participantId: i,
    };

    setState(() {
      for (var index = 0; index < entries.length; index += 1) {
        final entry = entries[index];
        if (placed[entry.participantId] case final slot?) {
          entries[index] = entry.copyWith(
            zone: 'field',
            x: slot.position.dx,
            y: slot.position.dy,
            slotLabel: slot.label,
          );
        } else if (bench[entry.participantId] case final order?) {
          entries[index] = entry.copyWith(
            zone: 'bench',
            sortOrder: order,
            clearSlot: true,
          );
        }
      }
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  Future<void> _savePaper() async {
    final entries = _entries;
    if (entries == null || _saving) return;

    if (compositionPublicationWillNotify(
      alreadyPublished: _notificationSent,
      sheetNamesPlayers: entries.any((entry) => entry.teamNo != null),
      postMatch: false,
    )) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Publier la composition ?'),
          content: const Text(
            'Publier la composition enverra une notification à tous les '
            'joueurs convoqués.',
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
    } catch (error) {
      if (mounted) _showMessage('Erreur : $error');
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
          title: const Text('Publier la composition ?'),
          content: const Text(
            'Publier la composition enverra une notification à tous les '
            'joueurs convoqués.',
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
      ref.invalidate(_internalPlayerProfilesProvider(widget.matchId));
      _showMessage('Composition enregistrée.');
    } catch (error) {
      if (mounted) _showMessage('Erreur : $error');
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
    } catch (error) {
      if (mounted) _showMessage('Erreur : $error');
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
    final profilesAsync = ref.watch(
      _internalPlayerProfilesProvider(widget.matchId),
    );
    final benchCountsAsync = ref.watch(
      _internalBenchCountsProvider(widget.matchId),
    );

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

        final entries = _entries!;
        final unassigned =
            entries.where((entry) => entry.teamNo == null).toList();
        final team1 = entries.where((entry) => entry.teamNo == 1).toList();
        final team2 = entries.where((entry) => entry.teamNo == 2).toList();
        final profiles = profilesAsync.valueOrNull ??
            const <String, PlayerPositionProfile>{};
        final benchCounts =
            benchCountsAsync.valueOrNull ?? const <String, int>{};
        final validation = _validation(entries);
        final legacyReadOnly =
            !widget.editable && !composition.isVisualComplete;

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
          formationCode:
              _terrainTeam == 1 ? _team1FormationCode : _team2FormationCode,
          editable: widget.editable,
          canReceiveSelected: _selectedEntry != null &&
              _selectedEntry!.teamNo != _terrainTeam,
          onAssignSelected: () => _assignSelectedToTeam(_terrainTeam),
          onJerseySelected: (jersey) => _changeJersey(_terrainTeam, jersey),
          onFormationSelected: (code) =>
              _changeFormation(_terrainTeam, code),
          onDroppedOnSlot: (moving, slot) =>
              _dropOnClassicSlot(_terrainTeam, moving, slot),
          onRemoveFromField: (moving) =>
              _moveClassicToBench(_terrainTeam, moving),
          finishedBenchCounts: benchCounts,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            if (_viewMode == 0) ...[
              if (unassigned.isNotEmpty || widget.editable) ...[
                Text(
                  'Non affectés (${unassigned.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _WaitingPool(
                  key: const ValueKey('internal-unassigned-pool'),
                  entries: unassigned,
                  editable: widget.editable,
                  selectedParticipantId: _selectedParticipantId,
                  canReceiveSelected: _selectedEntry?.teamNo != null,
                  onPoolTap: _moveSelectedToUnassigned,
                  onPlayerTap: _selectPlayer,
                  emptyLabel: 'Tous les joueurs sont répartis.',
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
                _LegacyInternalTeams(
                  team1Name: composition.team1Name,
                  team2Name: composition.team2Name,
                  team1: team1,
                  team2: team2,
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
              if (_viewMode == 1) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('simulate-internal-composition'),
                  onPressed: _saving ||
                          profilesAsync.isLoading ||
                          benchCountsAsync.isLoading
                      ? null
                      : () => _simulate(profiles, benchCounts),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Simuler la composition'),
                ),
              ],
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

class _PaperTeams extends StatelessWidget {
  const _PaperTeams({
    required this.team1Name,
    required this.team2Name,
    required this.team1Controller,
    required this.team2Controller,
    required this.team1Jersey,
    required this.team2Jersey,
    required this.team1,
    required this.team2,
    required this.editable,
    required this.selectedParticipantId,
    required this.onAssignTeam1,
    required this.onAssignTeam2,
    required this.onJersey1,
    required this.onJersey2,
    required this.onPlayerTap,
  });

  final String team1Name;
  final String team2Name;
  final TextEditingController? team1Controller;
  final TextEditingController? team2Controller;
  final JerseyOption team1Jersey;
  final JerseyOption team2Jersey;
  final List<InternalCompositionEntry> team1;
  final List<InternalCompositionEntry> team2;
  final bool editable;
  final String? selectedParticipantId;
  final VoidCallback onAssignTeam1;
  final VoidCallback onAssignTeam2;
  final ValueChanged<JerseyOption> onJersey1;
  final ValueChanged<JerseyOption> onJersey2;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final hasSelected = selectedParticipantId != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PaperTeamColumn(
            name: team1Name,
            teamNo: 1,
            controller: team1Controller,
            jersey: team1Jersey,
            unavailableJersey: team2Jersey,
            entries: team1,
            editable: editable,
            hasSelectedPlayer: hasSelected,
            selectedParticipantId: selectedParticipantId,
            onJerseyTap: onAssignTeam1,
            onJerseySelected: onJersey1,
            onPlayerTap: onPlayerTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PaperTeamColumn(
            name: team2Name,
            teamNo: 2,
            controller: team2Controller,
            jersey: team2Jersey,
            unavailableJersey: team1Jersey,
            entries: team2,
            editable: editable,
            hasSelectedPlayer: hasSelected,
            selectedParticipantId: selectedParticipantId,
            onJerseyTap: onAssignTeam2,
            onJerseySelected: onJersey2,
            onPlayerTap: onPlayerTap,
          ),
        ),
      ],
    );
  }
}

class _PaperTeamColumn extends StatelessWidget {
  const _PaperTeamColumn({
    required this.name,
    required this.teamNo,
    required this.controller,
    required this.jersey,
    required this.unavailableJersey,
    required this.entries,
    required this.editable,
    required this.hasSelectedPlayer,
    required this.selectedParticipantId,
    required this.onJerseyTap,
    required this.onJerseySelected,
    required this.onPlayerTap,
  });

  final String name;
  final int teamNo;
  final TextEditingController? controller;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final bool hasSelectedPlayer;
  final String? selectedParticipantId;
  final VoidCallback onJerseyTap;
  final ValueChanged<JerseyOption> onJerseySelected;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final controllerName = controller?.text.trim();
    final semanticName = controllerName != null && controllerName.isNotEmpty
        ? controllerName
        : name;
    final countLabel = entries.isEmpty
        ? ''
        : '${entries.length} joueur${entries.length > 1 ? 's' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaperJerseyAssignmentTile(
          semanticName: semanticName,
          jersey: jersey,
          unavailableJersey: unavailableJersey,
          playerCountLabel: countLabel,
          editable: editable,
          assignmentEnabled: editable && hasSelectedPlayer,
          onTap: onJerseyTap,
          onJerseySelected: onJerseySelected,
        ),
        const SizedBox(height: 8),
        if (editable && controller != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: controller,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Équipe $teamNo',
                counterText: '',
                isDense: true,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              semanticName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.outline.withValues(alpha: .3)),
          ),
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    'Aucun joueur.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (var index = 0; index < entries.length; index += 1)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == entries.length - 1 ? 0 : 6,
                        ),
                        child: _PlayerChip(
                          entry: entries[index],
                          editable: editable,
                          selected: selectedParticipantId ==
                              entries[index].participantId,
                          onTap: () => onPlayerTap(entries[index]),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PaperJerseyAssignmentTile extends StatelessWidget {
  const _PaperJerseyAssignmentTile({
    required this.semanticName,
    required this.jersey,
    required this.unavailableJersey,
    required this.playerCountLabel,
    required this.editable,
    required this.assignmentEnabled,
    required this.onTap,
    required this.onJerseySelected,
  });

  final String semanticName;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final String playerCountLabel;
  final bool editable;
  final bool assignmentEnabled;
  final VoidCallback onTap;
  final ValueChanged<JerseyOption> onJerseySelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: assignmentEnabled,
      label: [
        semanticName,
        if (playerCountLabel.isNotEmpty) playerCountLabel,
        'maillot ${jersey.label}',
      ].join(', '),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: assignmentEnabled
                ? AppTheme.accent
                : AppTheme.outline.withValues(alpha: .3),
            width: assignmentEnabled ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: assignmentEnabled ? onTap : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.asset(jersey.assetPath, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            if (playerCountLabel.isNotEmpty)
              Positioned(
                left: 7,
                bottom: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.outline.withValues(alpha: .35),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text(
                      playerCountLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            if (editable)
              Positioned(
                top: 2,
                right: 2,
                child: PopupMenuButton<JerseyOption>(
                  tooltip: 'Choisir le maillot',
                  initialValue: jersey,
                  onSelected: onJerseySelected,
                  itemBuilder: (context) => [
                    for (final option in JerseyOption.values)
                      PopupMenuItem<JerseyOption>(
                        value: option,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: Image.asset(
                                option.assetPath,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              option == unavailableJersey
                                  ? '${option.label} · échanger'
                                  : option.label,
                            ),
                          ],
                        ),
                      ),
                  ],
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InternalTeamCard extends StatelessWidget {
  const _InternalTeamCard({
    required this.name,
    required this.teamNo,
    required this.jersey,
    required this.unavailableJersey,
    required this.entries,
    required this.formationCode,
    required this.editable,
    required this.canReceiveSelected,
    required this.onAssignSelected,
    required this.onJerseySelected,
    required this.onFormationSelected,
    required this.onDroppedOnSlot,
    required this.onRemoveFromField,
    required this.finishedBenchCounts,
    this.controller,
  });

  final String name;
  final int teamNo;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final List<InternalCompositionEntry> entries;
  final String? formationCode;
  final bool editable;
  final bool canReceiveSelected;
  final VoidCallback onAssignSelected;
  final ValueChanged<JerseyOption> onJerseySelected;
  final ValueChanged<String> onFormationSelected;
  final void Function(MatchCompositionEntry, FootballFormationSlot)
      onDroppedOnSlot;
  final ValueChanged<MatchCompositionEntry> onRemoveFromField;
  final Map<String, int> finishedBenchCounts;
  final TextEditingController? controller;

  MatchCompositionEntry _classic(InternalCompositionEntry entry) {
    return MatchCompositionEntry(
      participantId: entry.participantId,
      seasonPlayerId: entry.seasonPlayerId ?? '',
      guestPlayerId: entry.guestPlayerId,
      displayName: entry.displayName,
      lastInitial: entry.lastInitial,
      isGuest: entry.isGuest,
      isGoalkeeper: entry.isGoalkeeper,
      zone: MatchCompositionZone.fromWire(entry.zone),
      x: entry.x,
      y: entry.y,
      slotLabel: entry.slotLabel,
      photoUrl: entry.photoUrl,
      sortOrder: entry.sortOrder,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: switch (entry.zone) {
        'field' => 'starter',
        'bench' => 'substitute',
        _ => 'undecided',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formations = internalFormationsForPlayerCount(entries.length);
    final formation = internalFormationByCode(
      playerCount: entries.length,
      code: formationCode,
    );
    final field = entries
        .where((entry) => entry.zone == 'field')
        .map(_classic)
        .toList(growable: false);
    final bench = entries
        .where((entry) => entry.zone == 'bench')
        .map(_classic)
        .toList(growable: false);
    final waiting =
        entries.where((entry) => entry.zone == 'available').toList();
    final semanticName = controller?.text.trim().isNotEmpty == true
        ? controller!.text.trim()
        : name;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _JerseyTarget(
                  semanticName: semanticName,
                  jersey: jersey,
                  unavailableJersey: unavailableJersey,
                  editable: editable,
                  assignmentEnabled: canReceiveSelected,
                  onAssignSelected: onAssignSelected,
                  onJerseySelected: onJerseySelected,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: editable && controller != null
                      ? TextField(
                          controller: controller,
                          maxLength: 40,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Équipe $teamNo',
                            counterText: '',
                            isDense: true,
                          ),
                        )
                      : Text(
                          semanticName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (editable)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Dispositif',
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: formation?.code,
                    hint: entries.isEmpty
                        ? const Text('Aucun joueur')
                        : const Text('Choisir le dispositif'),
                    items: [
                      for (final option in formations)
                        DropdownMenuItem(
                          value: option.code,
                          child: Text(option.code),
                        ),
                    ],
                    onChanged: entries.isEmpty
                        ? null
                        : (value) {
                            if (value != null) onFormationSelected(value);
                          },
                  ),
                ),
              )
            else if (formation != null)
              Text(
                'Dispositif ${formation.code}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            const SizedBox(height: 10),
            if (formation != null)
              FormationPitchEditor(
                slots: formation.slots,
                entries: field,
                editable: editable,
                finishedBenchCounts: finishedBenchCounts,
                onDroppedOnSlot: onDroppedOnSlot,
                onRemoveFromField: onRemoveFromField,
              )
            else
              Container(
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.outline.withValues(alpha: .3),
                  ),
                ),
                child: Text(
                  entries.isEmpty
                      ? 'Aucun joueur dans cette équipe.'
                      : 'Choisis un dispositif pour afficher le terrain.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Remplaçants (${bench.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in bench)
                    _ClassicBenchBox(
                      entry: entry,
                      draggable: editable,
                      finishedBenchCount:
                          finishedBenchCounts[entry.participantId] ?? 0,
                    ),
                ],
              ),
            ],
            if (waiting.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'À placer (${waiting.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in waiting)
                    _ClassicBenchBox(
                      entry: _classic(entry),
                      draggable: editable,
                      finishedBenchCount:
                          finishedBenchCounts[entry.participantId] ?? 0,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassicBenchBox extends StatelessWidget {
  const _ClassicBenchBox({
    required this.entry,
    required this.draggable,
    required this.finishedBenchCount,
  });

  final MatchCompositionEntry entry;
  final bool draggable;
  final int finishedBenchCount;

  @override
  Widget build(BuildContext context) {
    final tile = SizedBox(
      width: 70,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CompositionPlayerTile(
            entry: entry,
            onTap: draggable
                ? () => FormationPitchTapSelection.placePlayer(entry)
                : null,
          ),
          if (finishedBenchCount > 0)
            Positioned(
              top: 0,
              right: -2,
              child: SubstituteHistoryBadge(count: finishedBenchCount),
            ),
        ],
      ),
    );
    final highlighted = FormationPitchTapSelectionHighlight(
      entry: entry,
      child: tile,
    );
    if (!draggable) return highlighted;
    return LongPressDraggable<MatchCompositionEntry>(
      data: entry,
      feedback: Material(type: MaterialType.transparency, child: tile),
      childWhenDragging: Opacity(opacity: .35, child: tile),
      child: highlighted,
    );
  }
}

class _JerseyTarget extends StatelessWidget {
  const _JerseyTarget({
    required this.semanticName,
    required this.jersey,
    required this.unavailableJersey,
    required this.editable,
    required this.assignmentEnabled,
    required this.onAssignSelected,
    required this.onJerseySelected,
  });

  final String semanticName;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final bool editable;
  final bool assignmentEnabled;
  final VoidCallback onAssignSelected;
  final ValueChanged<JerseyOption> onJerseySelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: assignmentEnabled,
              label: '$semanticName, maillot ${jersey.label}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: assignmentEnabled ? onAssignSelected : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: assignmentEnabled
                            ? AppTheme.accent
                            : AppTheme.outline.withValues(alpha: .3),
                        width: assignmentEnabled ? 2 : 1,
                      ),
                    ),
                    child: Image.asset(jersey.assetPath, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          if (editable)
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<JerseyOption>(
                tooltip: 'Choisir le maillot',
                initialValue: jersey,
                onSelected: onJerseySelected,
                itemBuilder: (context) => [
                  for (final option in JerseyOption.values)
                    PopupMenuItem(
                      value: option,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: Image.asset(option.assetPath),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            option == unavailableJersey
                                ? '${option.label} · échanger'
                                : option.label,
                          ),
                        ],
                      ),
                    ),
                ],
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaitingPool extends StatelessWidget {
  const _WaitingPool({
    super.key,
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.canReceiveSelected,
    required this.onPoolTap,
    required this.onPlayerTap,
    required this.emptyLabel,
  });

  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final bool canReceiveSelected;
  final VoidCallback onPoolTap;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canReceiveSelected ? onPoolTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canReceiveSelected
                ? AppTheme.accent
                : AppTheme.outline.withValues(alpha: .3),
            width: canReceiveSelected ? 2 : 1,
          ),
        ),
        child: entries.isEmpty
            ? Text(emptyLabel, style: Theme.of(context).textTheme.bodySmall)
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in entries)
                    _PlayerChip(
                      entry: entry,
                      editable: editable,
                      selected: selectedParticipantId == entry.participantId,
                      onTap: () => onPlayerTap(entry),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.entry,
    required this.editable,
    required this.selected,
    required this.onTap,
  });

  final InternalCompositionEntry entry;
  final bool editable;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.accent.withValues(alpha: .16)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? AppTheme.accent
              : AppTheme.outline.withValues(alpha: .5),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(
            photoUrl: entry.photoUrl,
            name: entry.displayName,
            lastName: entry.lastInitial,
            isGoalkeeper: entry.isGoalkeeper,
            size: 28,
          ),
          const SizedBox(width: 8),
          Text(entry.displayName),
        ],
      ),
    );
    if (!editable) return chip;
    return Semantics(
      button: true,
      selected: selected,
      label: entry.displayName,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

class _LegacyInternalTeams extends StatelessWidget {
  const _LegacyInternalTeams({
    required this.team1Name,
    required this.team2Name,
    required this.team1,
    required this.team2,
  });

  final String team1Name;
  final String team2Name;
  final List<InternalCompositionEntry> team1;
  final List<InternalCompositionEntry> team2;

  @override
  Widget build(BuildContext context) {
    Widget team(String name, List<InternalCompositionEntry> entries) => Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _PlayerChip(
                      entry: entry,
                      editable: false,
                      selected: false,
                      onTap: () {},
                    ),
                  ),
              ],
            ),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: team(team1Name, team1)),
        const SizedBox(width: 10),
        Expanded(child: team(team2Name, team2)),
      ],
    );
  }
}

/// Profils indexés par participant du match. On réutilise exactement la même
/// identité canonique et le même historique que la simulation du onze.
final _internalBenchCountsProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String>((ref, matchId) async {
  try {
    return await ref
        .watch(matchCompositionRepositoryProvider)
        .fetchFinishedBenchCounts(matchId);
  } catch (_) {
    return const {};
  }
});

final _internalPlayerProfilesProvider = FutureProvider.autoDispose
    .family<Map<String, PlayerPositionProfile>, String>((ref, matchId) async {
  final composition = await ref.watch(
    internalMatchCompositionProvider(matchId).future,
  );
  if (composition == null) return const {};

  final seasonPlayerIds = composition.entries
      .where((entry) => !entry.isGuest)
      .map((entry) => entry.seasonPlayerId?.trim())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (seasonPlayerIds.isEmpty) return const {};

  try {
    final repository = ref.watch(matchCompositionRepositoryProvider);
    final canonicalIds = await repository.fetchCanonicalPlayerIds(
      seasonPlayerIds,
    );

    final archive = await ref.watch(playerPositionArchiveProvider.future);
    var positionProfiles = archive;
    try {
      positionProfiles = mergePlayerPositionProfiles(
        history: await repository.fetchPlayerPositionHistory(
          kLivePositionHistoryStart,
        ),
        archive: archive,
      );
    } catch (_) {
      positionProfiles = archive;
    }

    return {
      for (final entry in composition.entries)
        if (!entry.isGuest)
          if (entry.seasonPlayerId case final seasonPlayerId?)
            if (canonicalIds[seasonPlayerId] case final canonicalId?)
              if (positionProfiles[canonicalId] case final profile?)
                entry.participantId: profile,
    };
  } catch (_) {
    return const {};
  }
});
