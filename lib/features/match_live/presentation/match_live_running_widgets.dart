part of 'match_live_running_page.dart';

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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.liveScreenGutter,
          vertical: AppSpacing.sectionGap,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
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
        final width = (constraints.maxWidth - AppSpacing.microGap) / 2;

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: AppSpacing.microGap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textAlign: TextAlign.center,
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
          alignment: WrapAlignment.center,
          spacing: AppSpacing.microGap,
          runSpacing: AppSpacing.microGap,
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
    final fixture = ref
        .watch(upcomingMatchFixtureProvider(matchId))
        .valueOrNull;
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.liveScreenGutter,
          vertical: 9,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: home),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.microGap,
              ),
              child: Text(
                '–',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
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
      crossAxisAlignment: CrossAxisAlignment.center,
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
          crossAxisAlignment: CrossAxisAlignment.center,
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

const double _benchGap = AppSpacing.contentGap;
const double _benchColumnMargin = AppSpacing.compactCardPadding;

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
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.compactCardPadding,
          10,
          AppSpacing.compactCardPadding,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.contentGap),
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
            const SizedBox(height: AppSpacing.microGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppSpacing.contentGap),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.compactCardPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long_rounded),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Journal du match',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (events.isNotEmpty)
                    Text(
                      '${events.length}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  const SizedBox(width: AppSpacing.microGap),
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
              padding: EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
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
    final canChooseScorer =
        canEditScorer &&
        event.type == MatchLiveEventType.goalUs &&
        event.needsScorer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              "${event.minute}'",
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.contentGap),
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
            const SizedBox(width: AppSpacing.contentGap),
            Text(
              '${event.scoreAsGrintaAfter} - ${event.scoreAdverseAfter}',
              textAlign: TextAlign.center,
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
                        const SizedBox(width: AppSpacing.contentGap),
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
                      SizedBox(width: AppSpacing.contentGap),
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
