import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show PlayerAvatar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composition d'un « match entre nous » : pas de terrain ni de formation,
/// juste une réserve de joueurs convoqués répartie en deux équipes.
///
/// L'affectation est volontairement pensée pour le mobile : on sélectionne un
/// joueur, puis on touche le maillot de l'équipe voulue. Aucun drag-and-drop.
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
  Map<String, String> _canonicalPlayerIds = const {};
  Map<String, PlayerPositionProfile> _positionProfiles =
      kPlayerPositionProfiles;
  String? _positionLoadKey;
  String? _selectedParticipantId;
  JerseyOption _team1Jersey = JerseyOption.orange;
  JerseyOption _team2Jersey = JerseyOption.blue;
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
  void didUpdateWidget(covariant InternalTeamCompositionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId == widget.matchId) return;
    _syncingNames = true;
    _team1Controller.clear();
    _team2Controller.clear();
    _syncingNames = false;
    _entries = null;
    _canonicalPlayerIds = const {};
    _positionProfiles = kPlayerPositionProfiles;
    _positionLoadKey = null;
    _selectedParticipantId = null;
    _team1Jersey = JerseyOption.orange;
    _team2Jersey = JerseyOption.blue;
    _dirty = false;
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

  void _ensurePositionProfiles(List<InternalCompositionEntry> entries) {
    final seasonPlayerIds = entries
        .map((entry) => entry.seasonPlayerId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final key = seasonPlayerIds.join(',');
    if (_positionLoadKey == key) return;
    _positionLoadKey = key;
    Future.microtask(() => _refreshPositionProfiles(seasonPlayerIds, key));
  }

  Future<void> _refreshPositionProfiles(
    List<String> seasonPlayerIds,
    String loadKey,
  ) async {
    try {
      final repository = ref.read(matchCompositionRepositoryProvider);
      final canonicalPlayerIds =
          await repository.fetchCanonicalPlayerIds(seasonPlayerIds);
      final history = await repository.fetchPlayerPositionHistory(
        kLivePositionHistoryStart,
      );
      final merged = mergePlayerPositionProfiles(history: history);
      if (!mounted || _positionLoadKey != loadKey) return;
      setState(() {
        _canonicalPlayerIds = canonicalPlayerIds;
        _positionProfiles = merged;
      });
    } catch (_) {
      // Même repli que « Simuler la compo » : l'archive embarquée reste
      // exploitable si l'historique récent est momentanément indisponible.
    }
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

    final first = JerseyOption.fromId(composition.team1JerseyId) ??
        JerseyOption.orange;
    var second =
        JerseyOption.fromId(composition.team2JerseyId) ?? JerseyOption.blue;
    if (second == first) {
      second = JerseyOption.values.firstWhere((option) => option != first);
    }
    _team1Jersey = first;
    _team2Jersey = second;
  }

  void _selectPlayer(InternalCompositionEntry entry) {
    if (!widget.editable) return;
    setState(() {
      _selectedParticipantId = _selectedParticipantId == entry.participantId
          ? null
          : entry.participantId;
    });
  }

  void _moveSelectedTo(int? teamNo) {
    final selectedId = _selectedParticipantId;
    final entries = _entries;
    if (!widget.editable || selectedId == null || entries == null) return;
    final index = entries.indexWhere((e) => e.participantId == selectedId);
    if (index == -1) return;
    final current = entries[index];
    setState(() {
      entries[index] = current.copyWith(
        teamNo: teamNo,
        clearTeam: teamNo == null,
      );
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _selectJersey(int teamNo, JerseyOption option) {
    if (!widget.editable) return;
    setState(() {
      if (teamNo == 1) {
        if (option == _team1Jersey) return;
        if (option == _team2Jersey) {
          _team2Jersey = _team1Jersey;
        }
        _team1Jersey = option;
      } else {
        if (option == _team2Jersey) return;
        if (option == _team1Jersey) {
          _team1Jersey = _team2Jersey;
        }
        _team2Jersey = option;
      }
      _dirty = true;
    });
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
        _selectedParticipantId = null;
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

  _PositionGroup _positionGroup(InternalCompositionEntry entry) {
    if (entry.isGoalkeeper || entry.isGuest) return _PositionGroup.other;
    final seasonPlayerId = entry.seasonPlayerId?.trim();
    final canonicalPlayerId = seasonPlayerId == null
        ? null
        : _canonicalPlayerIds[seasonPlayerId];
    final profile = canonicalPlayerId == null
        ? null
        : _positionProfiles[canonicalPlayerId];

    // En-dessous de quatre titularisations, le poste moyen bouge trop vite
    // pour constituer une catégorie utile. Ces joueurs restent volontairement
    // dans « Autre » jusqu'à ce que l'historique soit assez représentatif.
    if (profile == null || profile.appearances < 4) {
      return _PositionGroup.other;
    }

    var defender = 0.0;
    var midfielder = 0.0;
    var attacker = 0.0;
    for (final sample in profile.samples) {
      switch (_slotGroup(sample.slotLabel)) {
        case _PositionGroup.defenders:
          defender += sample.weight;
        case _PositionGroup.midfielders:
          midfielder += sample.weight;
        case _PositionGroup.attackers:
          attacker += sample.weight;
        case _PositionGroup.other:
          break;
      }
    }
    final best = [defender, midfielder, attacker]
        .reduce((a, b) => a > b ? a : b);
    if (best <= 0) return _PositionGroup.other;

    final mainGroup = _slotGroup(profile.mainSlotLabel);
    if ((mainGroup == _PositionGroup.defenders && defender == best) ||
        (mainGroup == _PositionGroup.midfielders && midfielder == best) ||
        (mainGroup == _PositionGroup.attackers && attacker == best)) {
      return mainGroup;
    }
    if (defender == best) return _PositionGroup.defenders;
    if (midfielder == best) return _PositionGroup.midfielders;
    return _PositionGroup.attackers;
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
        _ensurePositionProfiles(entries);
        final unassigned = entries.where((e) => e.teamNo == null).toList();
        final team1 = entries.where((e) => e.teamNo == 1).toList();
        final team2 = entries.where((e) => e.teamNo == 2).toList();
        InternalCompositionEntry? selected;
        if (_selectedParticipantId != null) {
          for (final entry in entries) {
            if (entry.participantId == _selectedParticipantId) {
              selected = entry;
              break;
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.editable) ...[
              _SelectionHint(selected: selected),
              const SizedBox(height: 12),
            ],
            if (unassigned.isNotEmpty || widget.editable) ...[
              _UnassignedPanel(
                entries: unassigned,
                editable: widget.editable,
                selectedParticipantId: _selectedParticipantId,
                selectedIsAssigned: selected?.teamNo != null,
                groupFor: _positionGroup,
                onSelect: _selectPlayer,
                onMoveSelectedHere: () => _moveSelectedTo(null),
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
                    entries: team1,
                    editable: widget.editable,
                    jersey: _team1Jersey,
                    selectedParticipantId: _selectedParticipantId,
                    onSelectPlayer: _selectPlayer,
                    onAssignSelected: () => _moveSelectedTo(1),
                    onSelectJersey: (option) => _selectJersey(1, option),
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
                    entries: team2,
                    editable: widget.editable,
                    jersey: _team2Jersey,
                    selectedParticipantId: _selectedParticipantId,
                    onSelectPlayer: _selectPlayer,
                    onAssignSelected: () => _moveSelectedTo(2),
                    onSelectJersey: (option) => _selectJersey(2, option),
                  ),
                ),
              ],
            ),
            if (widget.editable) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving || !_dirty ? null : _save,
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

enum _PositionGroup { defenders, midfielders, attackers, other }

_PositionGroup _slotGroup(String slotLabel) {
  if (const {'DG', 'DCG', 'DC', 'DCD', 'DD'}.contains(slotLabel)) {
    return _PositionGroup.defenders;
  }
  if (const {
    'MDG',
    'MDC',
    'MDD',
    'MG',
    'MCG',
    'MC',
    'MCD',
    'MD',
    'MOG',
    'MOC',
    'MOD',
  }.contains(slotLabel)) {
    return _PositionGroup.midfielders;
  }
  if (const {'AG', 'AD', 'BUG', 'BU', 'BUD'}.contains(slotLabel)) {
    return _PositionGroup.attackers;
  }
  return _PositionGroup.other;
}

class _SelectionHint extends StatelessWidget {
  const _SelectionHint({required this.selected});

  final InternalCompositionEntry? selected;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected == null
            ? AppTheme.surface.withValues(alpha: .45)
            : AppTheme.accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected == null
              ? AppTheme.outline.withValues(alpha: .25)
              : AppTheme.accent.withValues(alpha: .55),
        ),
      ),
      child: Text(
        selected == null
            ? 'Sélectionne un joueur, puis touche le maillot de son équipe.'
            : '${selected.displayName} sélectionné · touche un maillot pour le déplacer.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: selected == null ? FontWeight.w600 : FontWeight.w800,
            ),
      ),
    );
  }
}

class _UnassignedPanel extends StatelessWidget {
  const _UnassignedPanel({
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.selectedIsAssigned,
    required this.groupFor,
    required this.onSelect,
    required this.onMoveSelectedHere,
  });

  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final bool selectedIsAssigned;
  final _PositionGroup Function(InternalCompositionEntry) groupFor;
  final ValueChanged<InternalCompositionEntry> onSelect;
  final VoidCallback onMoveSelectedHere;

  @override
  Widget build(BuildContext context) {
    final groups = <_PositionGroup, List<InternalCompositionEntry>>{
      for (final group in _PositionGroup.values) group: [],
    };
    for (final entry in entries) {
      groups[groupFor(entry)]!.add(entry);
    }
    for (final values in groups.values) {
      values.sort((a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ));
    }
    final visibleGroups = _PositionGroup.values
        .where((group) => groups[group]!.isNotEmpty)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outline.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: editable && selectedIsAssigned ? onMoveSelectedHere : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Non affectés (${entries.length})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  if (editable && selectedIsAssigned)
                    const Icon(Icons.undo_rounded, size: 18),
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Aucun joueur à répartir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (var index = 0; index < visibleGroups.length; index++) ...[
              _PositionGroupSection(
                group: visibleGroups[index],
                entries: groups[visibleGroups[index]]!,
                editable: editable,
                selectedParticipantId: selectedParticipantId,
                onSelect: onSelect,
              ),
              if (index != visibleGroups.length - 1)
                const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _PositionGroupSection extends StatelessWidget {
  const _PositionGroupSection({
    required this.group,
    required this.entries,
    required this.editable,
    required this.selectedParticipantId,
    required this.onSelect,
  });

  final _PositionGroup group;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final String? selectedParticipantId;
  final ValueChanged<InternalCompositionEntry> onSelect;

  String get label => switch (group) {
        _PositionGroup.defenders => 'Défenseurs',
        _PositionGroup.midfielders => 'Milieux',
        _PositionGroup.attackers => 'Attaquants',
        _PositionGroup.other => 'Autre',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            '$label (${entries.length})',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .72),
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
                onTap: () => onSelect(entry),
              ),
          ],
        ),
      ],
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.name,
    required this.teamNo,
    required this.entries,
    required this.editable,
    required this.jersey,
    required this.selectedParticipantId,
    required this.onSelectPlayer,
    required this.onAssignSelected,
    required this.onSelectJersey,
    this.controller,
  });

  final String name;
  final int teamNo;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final JerseyOption jersey;
  final String? selectedParticipantId;
  final ValueChanged<InternalCompositionEntry> onSelectPlayer;
  final VoidCallback onAssignSelected;
  final ValueChanged<JerseyOption> onSelectJersey;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final controllerName = controller?.text.trim();
    final semanticName = controllerName != null && controllerName.isNotEmpty
        ? controllerName
        : name;
    final canAssign = editable && selectedParticipantId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canAssign ? onAssignSelected : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 92,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: canAssign
                    ? AppTheme.accent.withValues(alpha: .08)
                    : AppTheme.surface.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: canAssign
                      ? AppTheme.accent.withValues(alpha: .7)
                      : AppTheme.outline.withValues(alpha: .3),
                  width: canAssign ? 1.5 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Image.asset(
                      jersey.assetPath,
                      fit: BoxFit.contain,
                      semanticLabel:
                          '$semanticName, ${_playerCount(entries.length)}',
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.outline.withValues(alpha: .35),
                        ),
                      ),
                      child: Text(
                        '${entries.length}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (editable)
          _JerseyPicker(
            selected: jersey,
            onSelected: onSelectJersey,
          ),
        if (editable) const SizedBox(height: 8),
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
                helperText: _playerCount(entries.length),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$semanticName · ${_playerCount(entries.length)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.outline.withValues(alpha: .3)),
          ),
          padding: const EdgeInsets.all(10),
          child: entries.isEmpty
              ? Text(
                  'Aucun joueur.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : Column(
                  children: [
                    for (var index = 0; index < entries.length; index++) ...[
                      _PlayerChip(
                        entry: entries[index],
                        editable: editable,
                        expand: true,
                        selected: selectedParticipantId ==
                            entries[index].participantId,
                        onTap: () => onSelectPlayer(entries[index]),
                      ),
                      if (index != entries.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _JerseyPicker extends StatelessWidget {
  const _JerseyPicker({
    required this.selected,
    required this.onSelected,
  });

  final JerseyOption selected;
  final ValueChanged<JerseyOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Maillot',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < JerseyOption.values.length; index++) ...[
              _JerseyChoice(
                option: JerseyOption.values[index],
                selected: JerseyOption.values[index] == selected,
                onTap: () => onSelected(JerseyOption.values[index]),
              ),
              if (index != JerseyOption.values.length - 1)
                const SizedBox(width: 4),
            ],
          ],
        ),
      ],
    );
  }
}

class _JerseyChoice extends StatelessWidget {
  const _JerseyChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final JerseyOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 38,
            height: 34,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.accent.withValues(alpha: .12)
                  : AppTheme.surface.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? AppTheme.accent
                    : AppTheme.outline.withValues(alpha: .3),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Image.asset(option.assetPath, fit: BoxFit.contain),
          ),
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
    this.expand = false,
  });

  final InternalCompositionEntry entry;
  final bool editable;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.accent.withValues(alpha: .15)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? AppTheme.accent
              : AppTheme.outline.withValues(alpha: .5),
          width: selected ? 1.7 : 1,
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
        ],
      ),
    );
    if (!editable) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

String _playerCount(int count) => '$count ${count == 1 ? 'joueur' : 'joueurs'}';