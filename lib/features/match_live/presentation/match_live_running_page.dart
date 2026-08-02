import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_recap_page.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_clock.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Un changement préparé mais pas encore envoyé.
typedef PendingSubstitution = ({String playerIn, String playerOut});

/// Le match est en cours (running/paused/halftime) ou terminé mais pas
/// encore exporté : c'est l'écran principal du Tableau Blanc.
class MatchLiveRunningPage extends ConsumerStatefulWidget {
  const MatchLiveRunningPage({
    super.key,
    required this.matchId,
    required this.bundle,
    required this.canEdit,
  });

  final String matchId;
  final MatchLiveStateBundle bundle;
  final bool canEdit;

  @override
  ConsumerState<MatchLiveRunningPage> createState() =>
      _MatchLiveRunningPageState();
}

class _MatchLiveRunningPageState extends ConsumerState<MatchLiveRunningPage> {
  final List<PendingSubstitution> _pending = [];
  final GlobalKey _journalKey = GlobalKey();
  bool _saving = false;
  bool _journalExpanded = false;

  String get matchId => widget.matchId;
  MatchLiveStateBundle get bundle => widget.bundle;
  bool get canEdit => widget.canEdit;

  @override
  Widget build(BuildContext context) {
    if (bundle.session.state == MatchLiveState.finished) {
      if (!canEdit) {
        return const _Message(
          message: 'Le match est terminé. En attente de la publication du '
              'compte rendu par le coach.',
        );
      }
      return MatchLiveRecapPage(matchId: matchId, bundle: bundle);
    }

    final lineup = bundle.lineup;
    if (lineup == null) {
      return const _Message(message: 'Composition indisponible.');
    }

    // Les changements en attente sont visibles immédiatement, sans être
    // persistés tant que le coach ne les a pas validés.
    final previewLineup = _previewLineup(lineup);
    final field = previewLineup.entriesFor(MatchCompositionZone.field);
    final bench = previewLineup.entriesFor(MatchCompositionZone.bench);
    final scorerCandidates = [...field, ...bench];
    final pendingOutIds = {for (final pair in _pending) pair.playerOut};
    final controller = ref.read(matchLiveStateProvider(matchId).notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _LiveTopBar(
          session: bundle.session,
          canEdit: canEdit,
          onPause: () => controller.setClockState('pause'),
          onResume: () => controller.setClockState('resume'),
          onResumeSecondHalf: () =>
              controller.setClockState('resume_second_half'),
          onHalftime: () => _confirmHalftime(context, controller),
          onRestart: () => _confirmRestart(context, controller),
          onEndMatch: () => _confirmEndMatch(context, controller),
        ),
        const SizedBox(height: 10),
        _ScoreCard(bundle: bundle, canEdit: canEdit),
        if (canEdit && _pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PendingSubstitutions(
            pending: _pending,
            nameOf: (participantId) => _nameOf(lineup, participantId),
            busy: _saving,
            onRemove: (pair) => setState(() => _pending.remove(pair)),
            onClear: () => setState(_pending.clear),
            onValidate: () => _validatePending(lineup, controller),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = benchAndPitchMetrics(constraints.maxWidth);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BenchColumn(
                    bench: bench,
                    bundle: bundle,
                    canEdit: canEdit,
                    metrics: metrics,
                    pendingOutIds: pendingOutIds,
                    onFieldPlayerDropped: (playerOut, playerIn) =>
                        _stage(playerIn: playerIn, playerOut: playerOut),
                  ),
                  const SizedBox(width: _benchGap),
                  Expanded(
                    child: FormationPitchEditor(
                      slots: formationForCode(lineup.formationCode).slots,
                      entries: field,
                      editable: canEdit,
                      finishedBenchCounts: bundle.substituteCounts,
                      markerMetrics: metrics,
                      onDroppedOnSlot: (moving, slot) => _handlePitchDrop(
                        context,
                        controller,
                        lineup,
                        moving,
                        slot,
                      ),
                      onRemoveFromField: (entry) =>
                          _explainHowToSubstitute(context),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _LiveJournal(
          key: _journalKey,
          events: bundle.events,
          expanded: _journalExpanded,
          canEdit: canEdit,
          onExpandedChanged: (value) =>
              setState(() => _journalExpanded = value),
          onEditScorer: (event) =>
              _pickGoalScorer(context, controller, event, scorerCandidates),
          onDelete: (event) => _confirmDeleteEvent(context, controller, event),
        ),
      ],
    );
  }

  MatchComposition _previewLineup(MatchComposition lineup) {
    if (_pending.isEmpty) return lineup;

    final positions = {
      for (final entry in lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {
      for (final pair in _pending) pair.playerIn: pair.playerOut,
    };
    final outgoing = {for (final pair in _pending) pair.playerOut};
    var benchOrder = lineup.entriesFor(MatchCompositionZone.bench).length;

    return lineup.copyWith(
      entries: [
        for (final entry in lineup.entries)
          if (incomingOf.containsKey(entry.participantId))
            entry.moveTo(
              MatchCompositionZone.field,
              x: positions[incomingOf[entry.participantId]]?.dx ?? .5,
              y: positions[incomingOf[entry.participantId]]?.dy ?? .5,
            )
          else if (outgoing.contains(entry.participantId))
            entry.moveTo(MatchCompositionZone.bench, sortOrder: benchOrder++)
          else
            entry,
      ],
    );
  }

  bool _isPendingParticipant(String participantId) {
    return _pending.any(
      (pair) =>
          pair.playerIn == participantId || pair.playerOut == participantId,
    );
  }

  void _stage({
    required MatchCompositionEntry playerIn,
    required MatchCompositionEntry playerOut,
  }) {
    final alreadyUsed = _pending.any(
      (pair) =>
          pair.playerIn == playerIn.participantId ||
          pair.playerOut == playerIn.participantId ||
          pair.playerIn == playerOut.participantId ||
          pair.playerOut == playerOut.participantId,
    );
    if (alreadyUsed) {
      _showMessage(
        context,
        'Ce joueur fait déjà partie des changements en attente.',
      );
      return;
    }
    setState(() {
      _pending.add((
        playerIn: playerIn.participantId,
        playerOut: playerOut.participantId,
      ));
    });
  }

  String _nameOf(MatchComposition lineup, String participantId) {
    for (final entry in lineup.entries) {
      if (entry.participantId == participantId) return entry.displayName;
    }
    return '?';
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _explainHowToSubstitute(BuildContext context) {
    _showMessage(
      context,
      'Glisse ce joueur sur le remplaçant qui entre, à gauche du terrain.',
    );
  }

  Future<void> _validatePending(
    MatchComposition lineup,
    MatchLiveStateController controller,
  ) async {
    if (_pending.isEmpty || _saving) return;
    final pairs = [..._pending];

    final positions = {
      for (final entry in lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {for (final p in pairs) p.playerIn: p.playerOut};
    final outgoing = {for (final p in pairs) p.playerOut};
    var benchOrder = lineup.entriesFor(MatchCompositionZone.bench).length;

    final entries = [
      for (final entry in lineup.entries)
        if (incomingOf.containsKey(entry.participantId))
          entry.moveTo(
            MatchCompositionZone.field,
            x: positions[incomingOf[entry.participantId]]?.dx ?? .5,
            y: positions[incomingOf[entry.participantId]]?.dy ?? .5,
          )
        else if (outgoing.contains(entry.participantId))
          entry.moveTo(MatchCompositionZone.bench, sortOrder: benchOrder++)
        else
          entry,
    ];

    setState(() => _saving = true);
    try {
      await controller.saveLiveLineup(
        entries: [for (final entry in entries) entry.toRpcJson()],
        substitutions: pairs,
      );
      if (mounted) setState(() => _pending.clear());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickGoalScorer(
    BuildContext context,
    MatchLiveStateController controller,
    MatchLiveEvent event,
    List<MatchCompositionEntry> candidates,
  ) async {
    final choice = await pickMatchLiveScorer(
      context,
      candidates: candidates,
      title: 'Qui a marqué à la ${event.minute}ᵉ minute ?',
      extraChoiceLabel: 'CSC adverse',
      extraChoiceIcon: Icons.shield_moon_outlined,
    );
    if (choice == null) return;
    if (choice == kMatchLiveExtraChoiceId) {
      await controller.setEventScorer(event.id, isOpponentOwnGoal: true);
      return;
    }
    await controller.setEventScorer(event.id, scorerParticipantId: choice);
  }

  Future<void> _confirmDeleteEvent(
    BuildContext context,
    MatchLiveStateController controller,
    MatchLiveEvent event,
  ) async {
    final description = switch (event.type) {
      MatchLiveEventType.goalUs => event.isOpponentOwnGoal
          ? "But AS Grinta (CSC adverse) · ${event.minute}'"
          : "But AS Grinta · ${event.scorerName ?? 'buteur à désigner'} · "
              "${event.minute}'",
      MatchLiveEventType.goalThem => "But adverse · ${event.minute}'",
      MatchLiveEventType.substitution => '${event.playerInName ?? '?'} entre · '
          '${event.playerOutName ?? '?'} sort · ${event.minute}\'',
    };
    final title = event.type == MatchLiveEventType.substitution
        ? 'Retirer ce remplacement ?'
        : 'Retirer ce but ?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteEvent(event.id);
    }
  }

  Future<void> _confirmHalftime(
    BuildContext context,
    MatchLiveStateController controller,
  ) async {
    final planned = bundle.session.planPlannedDurationMinutes;
    final target = Duration(seconds: planned * 30);
    final minutes = target.inMinutes.toString().padLeft(2, '0');
    final seconds = (target.inSeconds % 60).toString().padLeft(2, '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Passer à la mi-temps ?'),
        content: Text(
          'Le chronomètre sera calé sur $minutes:$seconds — la moitié des '
          '$planned minutes de jeu prévues — puis mis en pause.\n\n'
          'Le temps affiché actuellement sera donc remplacé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Oui, mi-temps'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.setClockState('halftime');
    }
  }

  Future<void> _confirmEndMatch(
    BuildContext context,
    MatchLiveStateController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fin du match'),
        content: const Text('Êtes-vous sûr de vouloir finir le match ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, terminer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.endMatch();
    }
  }

  Future<void> _confirmRestart(
    BuildContext context,
    MatchLiveStateController controller,
  ) async {
    final goals = bundle.ownGoals.length + bundle.opponentGoals.length;
    final substitutions = bundle.substitutions.length;
    final details = [
      if (goals > 0) goals == 1 ? '1 but' : '$goals buts',
      if (substitutions > 0)
        substitutions == 1 ? '1 remplacement' : '$substitutions remplacements',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recommencer le match ?'),
        content: Text(
          details.isEmpty
              ? 'Le chronomètre et le score repartent à zéro, et la '
                  'composition redevient celle du coup d’envoi.\n\n'
                  'Cette action est définitive.'
              : 'Tout ce qui a été saisi sera effacé : ${details.join(' et ')}, '
                  'le chronomètre et le score.\n\n'
                  'La composition redevient celle du coup d’envoi et tu '
                  'reviens à l’écran de préparation.\n\n'
                  'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(_pending.clear);
    await controller.restartSession();
  }

  Future<void> _handlePitchDrop(
    BuildContext context,
    MatchLiveStateController controller,
    MatchComposition lineup,
    MatchCompositionEntry moving,
    FootballFormationSlot slot,
  ) async {
    if (_isPendingParticipant(moving.participantId)) {
      _showMessage(
        context,
        'Valide ou annule ce changement avant de déplacer ce joueur.',
      );
      return;
    }

    final currentAtSlot = lineup.entries
        .where((entry) => entry.zone == MatchCompositionZone.field)
        .cast<MatchCompositionEntry?>()
        .firstWhere(
          (entry) =>
              entry != null &&
              (Offset(entry.x ?? .5, entry.y ?? .5) - slot.position).distance <
                  .12,
          orElse: () => null,
        );

    if (currentAtSlot != null &&
        _isPendingParticipant(currentAtSlot.participantId)) {
      _showMessage(
        context,
        'Cette position fait déjà partie d’un changement en attente.',
      );
      return;
    }

    if (moving.zone != MatchCompositionZone.field) {
      if (currentAtSlot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dépose ce joueur sur un titulaire déjà sur le terrain pour '
              'faire une entrée.',
            ),
          ),
        );
        return;
      }
      _stage(playerIn: moving, playerOut: currentAtSlot);
      return;
    }

    final oldPosition = Offset(moving.x ?? .5, moving.y ?? .5);
    final entries = [
      for (final entry in lineup.entries)
        if (entry.participantId == moving.participantId)
          entry.moveTo(
            MatchCompositionZone.field,
            x: slot.position.dx,
            y: slot.position.dy,
          )
        else if (currentAtSlot != null &&
            entry.participantId == currentAtSlot.participantId)
          entry.moveTo(
            MatchCompositionZone.field,
            x: oldPosition.dx,
            y: oldPosition.dy,
          )
        else
          entry,
    ];
    await controller.saveLiveLineup(
      entries: [for (final entry in entries) entry.toRpcJson()],
    );
  }
}

class _LiveTopBar extends StatelessWidget {
  const _LiveTopBar({
    required this.session,
    required this.canEdit,
    required this.onPause,
    required this.onResume,
    required this.onResumeSecondHalf,
    required this.onHalftime,
    required this.onRestart,
    required this.onEndMatch,
  });

  final MatchLiveSession session;
  final bool canEdit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onResumeSecondHalf;
  final VoidCallback onHalftime;
  final VoidCallback onRestart;
  final VoidCallback onEndMatch;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: MatchLiveClock(session: session, compact: true),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: canEdit
                  ? _LiveMatchControls(
                      session: session,
                      onPause: onPause,
                      onResume: onResume,
                      onResumeSecondHalf: onResumeSecondHalf,
                      onHalftime: onHalftime,
                      onRestart: onRestart,
                      onEndMatch: onEndMatch,
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 9,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Suivi en direct',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMatchControls extends StatelessWidget {
  const _LiveMatchControls({
    required this.session,
    required this.onPause,
    required this.onResume,
    required this.onResumeSecondHalf,
    required this.onHalftime,
    required this.onRestart,
    required this.onEndMatch,
  });

  final MatchLiveSession session;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onResumeSecondHalf;
  final VoidCallback onHalftime;
  final VoidCallback onRestart;
  final VoidCallback onEndMatch;

  @override
  Widget build(BuildContext context) {
    final firstAction = switch (session.state) {
      MatchLiveState.running => (
          label: 'Pause',
          icon: Icons.pause_rounded,
          callback: onPause,
          filled: false,
        ),
      MatchLiveState.paused => (
          label: 'Reprendre',
          icon: Icons.play_arrow_rounded,
          callback: onResume,
          filled: false,
        ),
      MatchLiveState.halftime => (
          label: 'Reprendre 2e',
          icon: Icons.play_arrow_rounded,
          callback: onResumeSecondHalf,
          filled: true,
        ),
      _ => (
          label: 'Pause',
          icon: Icons.pause_rounded,
          callback: null,
          filled: false,
        ),
    };
    final canGoHalftime =
        session.half == 1 && session.state != MatchLiveState.halftime;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 6) / 2;

        Widget button({
          required String label,
          required IconData icon,
          required VoidCallback? onPressed,
          bool filled = false,
          bool danger = false,
        }) {
          final style = danger
              ? OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 9,
                  ),
                  visualDensity: VisualDensity.compact,
                )
              : filled
                  ? FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 9,
                      ),
                      visualDensity: VisualDensity.compact,
                    )
                  : OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 9,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
          final child = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          );

          return SizedBox(
            width: width,
            child: filled
                ? FilledButton(onPressed: onPressed, style: style, child: child)
                : OutlinedButton(
                    onPressed: onPressed,
                    style: style,
                    child: child,
                  ),
          );
        }

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            button(
              label: firstAction.label,
              icon: firstAction.icon,
              onPressed: firstAction.callback,
              filled: firstAction.filled,
            ),
            button(
              label: 'Mi-temps',
              icon: Icons.sports_rounded,
              onPressed: canGoHalftime ? onHalftime : null,
            ),
            button(
              label: 'Recommencer',
              icon: Icons.restart_alt_rounded,
              onPressed: onRestart,
            ),
            button(
              label: 'Fin du match',
              icon: Icons.flag_rounded,
              onPressed: onEndMatch,
              danger: true,
            ),
          ],
        );
      },
    );
  }
}

class _ScoreCard extends ConsumerWidget {
  const _ScoreCard({required this.bundle, required this.canEdit});

  final MatchLiveStateBundle bundle;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchId = bundle.session.matchId;
    final controller = ref.read(matchLiveStateProvider(matchId).notifier);
    final fixture =
        ref.watch(upcomingMatchFixtureProvider(matchId)).valueOrNull;
    final opponentName = fixture?.opponentName ?? 'Adversaire';
    final grintaIsHome = fixture?.grintaIsHome ?? true;

    final home = _ScoreTeamControl(
      label: grintaIsHome ? 'AS Grinta' : opponentName,
      score: grintaIsHome
          ? bundle.session.scoreAsGrinta
          : bundle.session.scoreAdverse,
      canEdit: canEdit,
      onIncrement: () =>
          controller.adjustScore(team: grintaIsHome ? 'us' : 'them', delta: 1),
      onDecrement: () =>
          controller.adjustScore(team: grintaIsHome ? 'us' : 'them', delta: -1),
    );
    final away = _ScoreTeamControl(
      label: grintaIsHome ? opponentName : 'AS Grinta',
      score: grintaIsHome
          ? bundle.session.scoreAdverse
          : bundle.session.scoreAsGrinta,
      canEdit: canEdit,
      onIncrement: () =>
          controller.adjustScore(team: grintaIsHome ? 'them' : 'us', delta: 1),
      onDecrement: () =>
          controller.adjustScore(team: grintaIsHome ? 'them' : 'us', delta: -1),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Expanded(child: home),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '–',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(child: away),
          ],
        ),
      ),
    );
  }
}

class _ScoreTeamControl extends StatelessWidget {
  const _ScoreTeamControl({
    required this.label,
    required this.score,
    required this.canEdit,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String label;
  final int score;
  final bool canEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (canEdit)
              IconButton(
                tooltip: 'Retirer un but',
                onPressed: score > 0 ? onDecrement : null,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 34),
              child: Text(
                '$score',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'Ajouter un but',
                onPressed: onIncrement,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
          ],
        ),
      ],
    );
  }
}

const double _benchGap = 10;
const double _benchColumnMargin = 14;

FormationMarkerMetrics benchAndPitchMetrics(double availableWidth) {
  final pitchWidth =
      (availableWidth - _benchGap - _benchColumnMargin) * 5.6 / 6.6;
  return FormationMarkerMetrics.forPitch(pitchWidth);
}

double benchColumnWidth(FormationMarkerMetrics metrics) =>
    metrics.width + _benchColumnMargin;

class _BenchColumn extends StatelessWidget {
  const _BenchColumn({
    required this.bench,
    required this.bundle,
    required this.canEdit,
    required this.metrics,
    required this.pendingOutIds,
    required this.onFieldPlayerDropped,
  });

  final List<MatchCompositionEntry> bench;
  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final FormationMarkerMetrics metrics;
  final Set<String> pendingOutIds;
  final void Function(MatchCompositionEntry, MatchCompositionEntry)
      onFieldPlayerDropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: metrics.width + _benchColumnMargin,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _benchColumnMargin / 2,
            vertical: 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Banc (${bench.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              if (bench.isEmpty)
                Text(
                  'Personne',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final entry in bench)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DragTarget<MatchCompositionEntry>(
                      onWillAcceptWithDetails: (details) =>
                          canEdit &&
                          details.data.zone == MatchCompositionZone.field,
                      onAcceptWithDetails: (details) =>
                          onFieldPlayerDropped(details.data, entry),
                      builder: (context, candidates, rejected) {
                        final isPendingOut = pendingOutIds.contains(
                          entry.participantId,
                        );
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: candidates.isNotEmpty
                                  ? theme.colorScheme.primary
                                  : isPendingOut
                                      ? theme.colorScheme.error
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: LiveBenchTile(
                            entry: entry,
                            draggable: canEdit,
                            metrics: metrics,
                            timesBenched: bundle.timesBenched(
                              entry.participantId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingSubstitutions extends StatelessWidget {
  const _PendingSubstitutions({
    required this.pending,
    required this.nameOf,
    required this.busy,
    required this.onRemove,
    required this.onClear,
    required this.onValidate,
  });

  final List<PendingSubstitution> pending;
  final String Function(String participantId) nameOf;
  final bool busy;
  final ValueChanged<PendingSubstitution> onRemove;
  final VoidCallback onClear;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending.length == 1
                        ? 'Changement en attente'
                        : '${pending.length} changements en attente',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final pair in pending)
              Row(
                children: [
                  Expanded(
                    child: LiveSubstitutionLine(
                      playerInName: nameOf(pair.playerIn),
                      playerOutName: nameOf(pair.playerOut),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Annuler ce changement',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.undo_rounded),
                    onPressed: busy ? null : () => onRemove(pair),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onValidate,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: GrintaProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      pending.length == 1
                          ? 'Valider'
                          : 'Valider (${pending.length})',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _JournalAction { scorer, delete }

class _LiveJournal extends StatelessWidget {
  const _LiveJournal({
    super.key,
    required this.events,
    required this.expanded,
    required this.canEdit,
    required this.onExpandedChanged,
    required this.onEditScorer,
    required this.onDelete,
  });

  final List<MatchLiveEvent> events;
  final bool expanded;
  final bool canEdit;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final ordered = events.reversed.toList();
    final latest = ordered.isEmpty ? null : ordered.first;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Journal du match',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  if (events.isNotEmpty)
                    Text(
                      '${events.length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (latest == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Aucun événement pour le moment.'),
              ),
            )
          else if (!expanded) ...[
            const Divider(height: 1),
            _JournalEventRow(
              event: latest,
              canEdit: false,
              canEditScorer: canEdit,
              onEditScorer: onEditScorer,
              onDelete: onDelete,
            ),
          ] else ...[
            const Divider(height: 1),
            for (var index = 0; index < ordered.length; index++) ...[
              _JournalEventRow(
                event: ordered[index],
                canEdit: canEdit,
                canEditScorer: canEdit,
                onEditScorer: onEditScorer,
                onDelete: onDelete,
              ),
              if (index != ordered.length - 1)
                const Divider(height: 1, indent: 48),
            ],
          ],
        ],
      ),
    );
  }
}

class _JournalEventRow extends StatelessWidget {
  const _JournalEventRow({
    required this.event,
    required this.canEdit,
    required this.canEditScorer,
    required this.onEditScorer,
    required this.onDelete,
  });

  final MatchLiveEvent event;
  final bool canEdit;
  final bool canEditScorer;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (event.type) {
      MatchLiveEventType.goalUs => (
          Icons.sports_soccer_rounded,
          theme.colorScheme.primary,
          event.isOpponentOwnGoal
              ? 'But AS Grinta · CSC adverse'
              : 'But AS Grinta · ${event.scorerName ?? 'Buteur à désigner'}',
        ),
      MatchLiveEventType.goalThem => (
          Icons.sports_soccer_outlined,
          theme.colorScheme.error,
          'But adverse',
        ),
      MatchLiveEventType.substitution => (
          Icons.swap_horiz_rounded,
          theme.colorScheme.secondary,
          '${event.playerInName ?? '?'} entre · '
              '${event.playerOutName ?? '?'} sort',
        ),
    };
    final hasScore =
        event.scoreAsGrintaAfter != null && event.scoreAdverseAfter != null;
    final canChooseScorer = canEditScorer &&
        event.type == MatchLiveEventType.goalUs &&
        event.needsScorer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              "${event.minute}'",
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: canChooseScorer ? () => onEditScorer(event) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: canChooseScorer
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          if (hasScore) ...[
            const SizedBox(width: 8),
            Text(
              '${event.scoreAsGrintaAfter} - ${event.scoreAdverseAfter}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (canEdit) ...[
            const SizedBox(width: 2),
            PopupMenuButton<_JournalAction>(
              tooltip: 'Corriger',
              onSelected: (action) {
                if (action == _JournalAction.scorer) {
                  onEditScorer(event);
                } else {
                  onDelete(event);
                }
              },
              itemBuilder: (context) => [
                if (event.type == MatchLiveEventType.goalUs)
                  PopupMenuItem(
                    value: _JournalAction.scorer,
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_rounded),
                        const SizedBox(width: 8),
                        Text(
                          event.needsScorer
                              ? 'Choisir le buteur'
                              : 'Corriger le buteur',
                        ),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: _JournalAction.delete,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded),
                      SizedBox(width: 8),
                      Text('Retirer'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
