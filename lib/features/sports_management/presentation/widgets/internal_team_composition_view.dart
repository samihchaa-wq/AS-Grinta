import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show PlayerAvatar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int _minimumPositionAppearances = 5;

enum _InternalPlayerCategory { defender, midfielder, attacker, other }

extension on _InternalPlayerCategory {
  String get label => switch (this) {
        _InternalPlayerCategory.defender => 'Défenseurs',
        _InternalPlayerCategory.midfielder => 'Milieux',
        _InternalPlayerCategory.attacker => 'Attaquants',
        _InternalPlayerCategory.other => 'Autre',
      };
}

/// Composition d'un « match entre nous » : pas de terrain ni de formation,
/// juste une réserve de joueurs convoqués répartie en deux équipes identifiées
/// visuellement par les maillots choisis pour le match.
class InternalTeamCompositionView extends ConsumerStatefulWidget {
  const InternalTeamCompositionView({
    super.key,
    required this.matchId,
    required this.editable,
    this.canonicalPlayerIds = const {},
    this.positionProfiles = kPlayerPositionProfiles,
  });

  final String matchId;
  final bool editable;

  /// `season_players.id` -> identité canonique (`players.id`).
  final Map<String, String> canonicalPlayerIds;

  /// Même historique pondéré que celui utilisé par « Simuler la compo ».
  final Map<String, PlayerPositionProfile> positionProfiles;

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
  String? _selectedParticipantId;
  bool _dirty = false;
  bool _saving = false;
  bool _syncingNames = false;

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
    _team1Jersey =
        JerseyOption.fromId(composition.team1JerseyId) ?? JerseyOption.orange;
    _team2Jersey =
        JerseyOption.fromId(composition.team2JerseyId) ?? JerseyOption.blue;
    if (_team1Jersey == _team2Jersey) {
      _team2Jersey = JerseyOption.values.firstWhere(
        (option) => option != _team1Jersey,
      );
    }
    _entries = List.of(composition.entries);
    _selectedParticipantId = null;
  }

  void _moveTo(InternalCompositionEntry entry, int? teamNo) {
    setState(() {
      final entries = _entries;
      if (entries == null) return;
      final index = entries.indexWhere(
        (e) => e.participantId == entry.participantId,
      );
      if (index == -1) return;
      entries[index] = entries[index].copyWith(
        teamNo: teamNo,
        clearTeam: teamNo == null,
      );
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _togglePlayerSelection(InternalCompositionEntry entry) {
    if (!widget.editable) return;
    setState(() {
      _selectedParticipantId = _selectedParticipantId == entry.participantId
          ? null
          : entry.participantId;
    });
  }

  void _moveSelectedToTeam(int teamNo) {
    if (!widget.editable) return;
    final participantId = _selectedParticipantId;
    final entries = _entries;
    if (participantId == null || entries == null) return;
    final index = entries.indexWhere((e) => e.participantId == participantId);
    if (index == -1) return;
    final entry = entries[index];
    if (entry.teamNo == teamNo) {
      setState(() => _selectedParticipantId = null);
      return;
    }
    _moveTo(entry, teamNo);
  }

  void _selectJersey(int teamNo, JerseyOption jersey) {
    if (!widget.editable) return;
    if ((teamNo == 1 && jersey == _team1Jersey) ||
        (teamNo == 2 && jersey == _team2Jersey)) {
      return;
    }
    setState(() {
      if (teamNo == 1) {
        final previous = _team1Jersey;
        if (_team2Jersey == jersey) _team2Jersey = previous;
        _team1Jersey = jersey;
      } else {
        final previous = _team2Jersey;
        if (_team1Jersey == jersey) _team1Jersey = previous;
        _team2Jersey = jersey;
      }
      _dirty = true;
    });
  }

  _InternalPlayerCategory _categoryFor(InternalCompositionEntry entry) {
    if (entry.isGoalkeeper) return _InternalPlayerCategory.other;
    final seasonPlayerId = entry.seasonPlayerId;
    if (seasonPlayerId == null) return _InternalPlayerCategory.other;
    final canonicalId = widget.canonicalPlayerIds[seasonPlayerId];
    if (canonicalId == null) return _InternalPlayerCategory.other;
    final profile = widget.positionProfiles[canonicalId];
    if (profile == null ||
        profile.appearances < _minimumPositionAppearances) {
      return _InternalPlayerCategory.other;
    }

    var weightedY = 0.0;
    var totalWeight = 0.0;
    for (final sample in profile.samples) {
      // Comme la simulation, on ne transforme jamais un dépannage au but en
      // poste de champ. Un gardien déclaré est déjà classé « Autre » plus haut.
      if (sample.slotLabel == 'GB') continue;
      final position = matchSheetSlotPositions[sample.slotLabel];
      if (position == null || sample.weight <= 0) continue;
      weightedY += position.dy * sample.weight;
      totalWeight += sample.weight;
    }
    if (totalWeight <= 0) return _InternalPlayerCategory.other;

    final averageY = weightedY / totalWeight;
    // Frontières placées entre les lignes de la feuille de match :
    // défense (y=.65+) / milieux (jusqu'à .53), puis ailiers (.22) / MOC (.27).
    if (averageY >= .59) return _InternalPlayerCategory.defender;
    if (averageY <= .235) return _InternalPlayerCategory.attacker;
    return _InternalPlayerCategory.midfielder;
  }

  Map<_InternalPlayerCategory, List<InternalCompositionEntry>>
      _groupUnassigned(List<InternalCompositionEntry> entries) {
    final grouped = {
      for (final category in _InternalPlayerCategory.values)
        category: <InternalCompositionEntry>[],
    };
    for (final entry in entries) {
      grouped[_categoryFor(entry)]!.add(entry);
    }
    for (final values in grouped.values) {
      values.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    }
    return grouped;
  }

  Future<void> _save() async {
    final entries = _entries;
    if (entries == null || _saving) return;
    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(internalMatchCompositionRepositoryProvider).save(
        matchId: widget.matchId,
        team1Name: _team1Controller.text,
        team2Name: _team2Controller.text,
        team1JerseyId: _team1Jersey.id,
        team2JerseyId: _team2Jersey.id,
        entries: [
          for (final entry in entries.where((e) => e.teamNo == null)) entry,
          for (final entry in entries.where((e) => e.teamNo == 1)) entry,
          for (final entry in entries.where((e) => e.teamNo == 2)) entry,
        ],
      );
      if (!mounted) return;
      setState(() {
        _initFrom(saved);
        _dirty = false;
      });
      ref.invalidate(internalMatchCompositionProvider(widget.matchId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Composition enregistrée.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(internalMatchCompositionProvider(widget.matchId));

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
        if (!_dirty && _team1Controller.text.isEmpty) {
          _initFrom(composition);
        }
        final entries = _entries!;
        final unassigned = entries.where((e) => e.teamNo == null).toList();
        final team1 = entries.where((e) => e.teamNo == 1).toList();
        final team2 = entries.where((e) => e.teamNo == 2).toList();
        final grouped = _groupUnassigned(unassigned);
        final selectedEntry = _selectedParticipantId == null
            ? null
            : entries.cast<InternalCompositionEntry?>().firstWhere(
                  (entry) =>
                      entry?.participantId == _selectedParticipantId,
                  orElse: () => null,
                );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (unassigned.isNotEmpty || widget.editable) ...[
              Text(
                'Non affectés (${unassigned.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.outline.withValues(alpha: .3),
                  ),
                ),
                child: unassigned.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text(
                          'Aucun joueur à répartir.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final category in _InternalPlayerCategory.values)
                            if (grouped[category]!.isNotEmpty)
                              _PlayerCategorySection(
                                title: category.label,
                                entries: grouped[category]!,
                                editable: widget.editable,
                                selectedParticipantId:
                                    _selectedParticipantId,
                                onPlayerTap: _togglePlayerSelection,
                              ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TeamColumn(
                    controller: widget.editable ? _team1Controller : null,
                    name: _team1Controller.text.isEmpty
                        ? composition.team1Name
                        : _team1Controller.text,
                    teamNo: 1,
                    jersey: _team1Jersey,
                    entries: team1,
                    editable: widget.editable,
                    selectedParticipantId: _selectedParticipantId,
                    canReceiveSelected: selectedEntry != null &&
                        selectedEntry.teamNo != 1,
                    onJerseyTap: () => _moveSelectedToTeam(1),
                    onJerseyChanged: (jersey) => _selectJersey(1, jersey),
                    onPlayerTap: _togglePlayerSelection,
                    onUnassign: (entry) => _moveTo(entry, null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeamColumn(
                    controller: widget.editable ? _team2Controller : null,
                    name: _team2Controller.text.isEmpty
                        ? composition.team2Name
                        : _team2Controller.text,
                    teamNo: 2,
                    jersey: _team2Jersey,
                    entries: team2,
                    editable: widget.editable,
                    selectedParticipantId: _selectedParticipantId,
                    canReceiveSelected: selectedEntry != null &&
                        selectedEntry.teamNo != 2,
                    onJerseyTap: () => _moveSelectedToTeam(2),
                    onJerseyChanged: (jersey) => _selectJersey(2, jersey),
                    onPlayerTap: _togglePlayerSelection,
                    onUnassign: (entry) => _moveTo(entry, null),
                  ),
                ),
              ],
            ),
            if (widget.editable) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
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

class _PlayerCategorySection extends StatelessWidget {
  const _PlayerCategorySection({
    required this.title,
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.onPlayerTap,
  });

  final String title;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              '$title (${entries.length})',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.muted,
                  ),
            ),
          ),
          Wrap(
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
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.name,
    required this.teamNo,
    required this.jersey,
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.canReceiveSelected,
    required this.onJerseyTap,
    required this.onJerseyChanged,
    required this.onPlayerTap,
    required this.onUnassign,
    this.controller,
  });

  final String name;
  final int teamNo;
  final JerseyOption jersey;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final bool canReceiveSelected;
  final VoidCallback onJerseyTap;
  final ValueChanged<JerseyOption> onJerseyChanged;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;
  final ValueChanged<InternalCompositionEntry> onUnassign;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final controllerName = controller?.text.trim();
    final semanticName = controllerName != null && controllerName.isNotEmpty
        ? controllerName
        : name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: editable,
          label: canReceiveSelected
              ? 'Mettre le joueur sélectionné dans $semanticName'
              : '$semanticName, ${entries.length} joueurs',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: editable ? onJerseyTap : null,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 88,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: canReceiveSelected
                      ? AppTheme.accent.withValues(alpha: .10)
                      : AppTheme.surface.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: canReceiveSelected
                        ? AppTheme.accent
                        : AppTheme.outline.withValues(alpha: .3),
                    width: canReceiveSelected ? 2 : 1,
                  ),
                ),
                child: Image.asset(
                  jersey.assetPath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${entries.length} joueur${entries.length == 1 ? '' : 's'}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        if (editable) ...[
          const SizedBox(height: 6),
          _JerseyPicker(
            selected: jersey,
            onChanged: onJerseyChanged,
          ),
        ],
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
                labelText: 'Nom de l’équipe $teamNo',
                hintText: 'Équipe $teamNo',
                counterText: '',
                isDense: true,
              ),
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
              ? Text(
                  'Aucun joueur.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : Column(
                  children: [
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _PlayerChip(
                          entry: entry,
                          editable: editable,
                          expand: true,
                          selected:
                              selectedParticipantId == entry.participantId,
                          onTap: () => onPlayerTap(entry),
                          onRemove: () => onUnassign(entry),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _JerseyPicker extends StatelessWidget {
  const _JerseyPicker({required this.selected, required this.onChanged});

  final JerseyOption selected;
  final ValueChanged<JerseyOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < JerseyOption.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              button: true,
              selected: JerseyOption.values[i] == selected,
              label: 'Maillot ${JerseyOption.values[i].label}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onChanged(JerseyOption.values[i]),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: JerseyOption.values[i] == selected
                            ? AppTheme.accent
                            : AppTheme.outline.withValues(alpha: .3),
                        width: JerseyOption.values[i] == selected ? 2 : 1,
                      ),
                    ),
                    child: Image.asset(
                      JerseyOption.values[i].assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.entry,
    required this.editable,
    required this.selected,
    required this.onTap,
    this.onRemove,
    this.expand = false,
  });

  final InternalCompositionEntry entry;
  final bool editable;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: editable ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: .12)
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
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              PlayerAvatar(
                photoUrl: entry.photoUrl,
                name: entry.displayName,
                isGoalkeeper: entry.isGoalkeeper,
                size: 28,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (editable && onRemove != null) ...[
                const SizedBox(width: 3),
                IconButton(
                  tooltip: 'Retirer de l’équipe',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
