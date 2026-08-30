import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_player_grouping.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_history.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart'
    show PlayerAvatar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composition d'un « match entre nous » : pas de terrain ni de formation,
/// juste une réserve de joueurs convoqués répartie en deux équipes. Les deux
/// équipes choisissent chacune un maillot distinct parmi le catalogue.
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
    _entries = List.of(composition.entries);

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

  void _moveSelectedTo(int teamNo) {
    final entries = _entries;
    final selectedId = _selectedParticipantId;
    if (!widget.editable || entries == null || selectedId == null) return;
    final index = entries.indexWhere((entry) => entry.participantId == selectedId);
    if (index == -1) return;

    setState(() {
      final entry = entries[index];
      // Toucher le maillot de son équipe actuelle retire le joueur. Toucher
      // l'autre maillot le transfère directement, sans étape intermédiaire.
      final nextTeam = entry.teamNo == teamNo ? null : teamNo;
      entries[index] = entry.copyWith(
        teamNo: nextTeam,
        clearTeam: nextTeam == null,
      );
      _selectedParticipantId = null;
      _dirty = true;
    });
  }

  void _changeJersey(int teamNo, JerseyOption jersey) {
    if (!widget.editable) return;
    if (teamNo == 1 && jersey == _team2Jersey) return;
    if (teamNo == 2 && jersey == _team1Jersey) return;
    setState(() {
      if (teamNo == 1) {
        _team1Jersey = jersey;
      } else {
        _team2Jersey = jersey;
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
      ref.invalidate(_internalPlayerProfilesProvider(widget.matchId));
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
    final profilesAsync = ref.watch(
      _internalPlayerProfilesProvider(widget.matchId),
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
        if (!_dirty && _team1Controller.text.isEmpty) {
          _initFrom(composition);
        }
        final entries = _entries!;
        final unassigned = entries.where((e) => e.teamNo == null).toList();
        final team1 = entries.where((e) => e.teamNo == 1).toList();
        final team2 = entries.where((e) => e.teamNo == 2).toList();
        final profiles = profilesAsync.valueOrNull;

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
              _UnassignedPlayers(
                entries: unassigned,
                profiles: profiles,
                editable: widget.editable,
                selectedParticipantId: _selectedParticipantId,
                onPlayerTap: _selectPlayer,
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
                    unavailableJersey: _team2Jersey,
                    entries: team1,
                    editable: widget.editable,
                    hasSelectedPlayer: _selectedParticipantId != null,
                    selectedParticipantId: _selectedParticipantId,
                    onJerseyTap: () => _moveSelectedTo(1),
                    onJerseySelected: (jersey) => _changeJersey(1, jersey),
                    onPlayerTap: _selectPlayer,
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
                    unavailableJersey: _team1Jersey,
                    entries: team2,
                    editable: widget.editable,
                    hasSelectedPlayer: _selectedParticipantId != null,
                    selectedParticipantId: _selectedParticipantId,
                    onJerseyTap: () => _moveSelectedTo(2),
                    onJerseySelected: (jersey) => _changeJersey(2, jersey),
                    onPlayerTap: _selectPlayer,
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

class _UnassignedPlayers extends StatelessWidget {
  const _UnassignedPlayers({
    required this.entries,
    required this.profiles,
    required this.editable,
    required this.selectedParticipantId,
    required this.onPlayerTap,
  });

  final List<InternalCompositionEntry> entries;
  final Map<String, PlayerPositionProfile>? profiles;
  final bool editable;
  final String? selectedParticipantId;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                'Aucun joueur à répartir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : profiles == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : _GroupedPlayerChips(
                  entries: entries,
                  profiles: profiles!,
                  editable: editable,
                  selectedParticipantId: selectedParticipantId,
                  onPlayerTap: onPlayerTap,
                ),
    );
  }
}

class _GroupedPlayerChips extends StatelessWidget {
  const _GroupedPlayerChips({
    required this.entries,
    required this.profiles,
    required this.editable,
    required this.selectedParticipantId,
    required this.onPlayerTap,
  });

  final List<InternalCompositionEntry> entries;
  final Map<String, PlayerPositionProfile> profiles;
  final bool editable;
  final String? selectedParticipantId;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final groups = <InternalPlayerGroup, List<InternalCompositionEntry>>{
      for (final group in InternalPlayerGroup.values) group: [],
    };
    for (final entry in entries) {
      groups[internalPlayerGroupFor(
        isGoalkeeper: entry.isGoalkeeper,
        profile: profiles[entry.participantId],
      )]!
          .add(entry);
    }
    for (final players in groups.values) {
      players.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    }

    final visibleGroups = InternalPlayerGroup.values
        .where((group) => groups[group]!.isNotEmpty)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < visibleGroups.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 10),
          Text(
            '${_groupLabel(visibleGroups[index])} '
            '(${groups[visibleGroups[index]]!.length})',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in groups[visibleGroups[index]]!)
                _PlayerChip(
                  entry: entry,
                  editable: editable,
                  selected: selectedParticipantId == entry.participantId,
                  onTap: () => onPlayerTap(entry),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _groupLabel(InternalPlayerGroup group) => switch (group) {
        InternalPlayerGroup.defenders => 'Défenseurs',
        InternalPlayerGroup.midfielders => 'Milieux',
        InternalPlayerGroup.attackers => 'Attaquants',
        InternalPlayerGroup.other => 'Autre',
      };
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.name,
    required this.teamNo,
    required this.jersey,
    required this.unavailableJersey,
    required this.entries,
    required this.editable,
    required this.hasSelectedPlayer,
    required this.selectedParticipantId,
    required this.onJerseyTap,
    required this.onJerseySelected,
    required this.onPlayerTap,
    this.controller,
  });

  final String name;
  final int teamNo;
  final JerseyOption jersey;
  final JerseyOption unavailableJersey;
  final List<InternalCompositionEntry> entries;
  final bool editable;
  final bool hasSelectedPlayer;
  final String? selectedParticipantId;
  final VoidCallback onJerseyTap;
  final ValueChanged<JerseyOption> onJerseySelected;
  final ValueChanged<InternalCompositionEntry> onPlayerTap;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final controllerName = controller?.text.trim();
    final semanticName = controllerName != null && controllerName.isNotEmpty
        ? controllerName
        : name;
    final countLabel = '${entries.length} joueur${entries.length > 1 ? 's' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JerseyAssignmentTile(
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
                labelText: 'Nom de l’équipe $teamNo',
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
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
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
                          expand: true,
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

class _JerseyAssignmentTile extends StatelessWidget {
  const _JerseyAssignmentTile({
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
      label: '$semanticName, $playerCountLabel, maillot ${jersey.label}',
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
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text(
                    playerCountLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
                        enabled: option != unavailableJersey,
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
                            Text(option.label),
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

/// Profils indexés par participant du match. On réutilise exactement la même
/// identité canonique, le même historique et la même fusion que « Simuler la
/// compo » afin d'éviter deux logiques de poste qui dériveraient avec le temps.
final _internalPlayerProfilesProvider = FutureProvider.autoDispose
    .family<Map<String, PlayerPositionProfile>, String>((ref, matchId) async {
  final composition =
      await ref.watch(internalMatchCompositionProvider(matchId).future);
  if (composition == null) return const {};

  final seasonPlayerIds = composition.entries
      .map((entry) => entry.seasonPlayerId?.trim())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (seasonPlayerIds.isEmpty) return const {};

  final repository = ref.watch(matchCompositionRepositoryProvider);
  try {
    final canonicalIds =
        await repository.fetchCanonicalPlayerIds(seasonPlayerIds);
    var positionProfiles = kPlayerPositionProfiles;
    try {
      positionProfiles = mergePlayerPositionProfiles(
        history: await repository.fetchPlayerPositionHistory(
          kLivePositionHistoryStart,
        ),
      );
    } catch (_) {
      positionProfiles = kPlayerPositionProfiles;
    }

    return {
      for (final entry in composition.entries)
        if (entry.seasonPlayerId case final seasonPlayerId?)
          if (canonicalIds[seasonPlayerId] case final canonicalId?)
            if (positionProfiles[canonicalId] case final profile?)
              entry.participantId: profile,
    };
  } catch (_) {
    return const {};
  }
});
