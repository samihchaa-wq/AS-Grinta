part of 'match_live_running_page.dart';

enum _JournalAction { scorer, assist, delete }

class _LiveJournal extends StatelessWidget {
  const _LiveJournal({
    super.key,
    required this.events,
    required this.expanded,
    required this.canEdit,
    required this.onExpandedChanged,
    required this.onEditScorer,
    required this.onEditAssist,
    required this.onDelete,
    this.plain = false,
    this.title = 'Journal du match',
    this.emptyText = 'Aucun événement pour le moment.',
  });

  /// Vue spectateur : ni encadrés de salve ni repères « passage.série ».
  final bool plain;
  final String title;
  final String emptyText;

  final List<MatchLiveEvent> events;
  final bool expanded;
  final bool canEdit;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onEditAssist;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final ordered = events.reversed.toList();
    final latest = ordered.isEmpty ? null : ordered.first;
    final salvos = plain
        ? <MatchLiveEvent, SubstitutionSalvo>{}
        : substitutionSalvosByEvent(events);
    final marks = plain
        ? <MatchLiveEvent, SubstitutionExitMark>{}
        : substitutionExitMarksByEvent(events);

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
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(emptyText),
              ),
            )
          else if (!expanded) ...[
            const Divider(height: 1),
            _framed(
              salvos[latest],
              _JournalEventRow(
                event: latest,
                mark: marks[latest],
                canEdit: false,
                canEditScorer: canEdit,
                onEditScorer: onEditScorer,
                onEditAssist: onEditAssist,
                onDelete: onDelete,
              ),
            ),
          ] else ...[
            const Divider(height: 1),
            ..._expandedRows(ordered, salvos, marks),
          ],
        ],
      ),
    );
  }

  Widget _framed(SubstitutionSalvo? salvo, Widget child) => salvo == null
      ? child
      : SubstitutionSalvoFrame(
          salvo: salvo,
          margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: child,
        );

  /// Liste dépliée : les remplacements consécutifs d'une même salve partagent
  /// un encadré coloré, les autres lignes restent séparées par un trait.
  List<Widget> _expandedRows(
    List<MatchLiveEvent> ordered,
    Map<MatchLiveEvent, SubstitutionSalvo> salvos,
    Map<MatchLiveEvent, SubstitutionExitMark> marks,
  ) {
    Widget row(MatchLiveEvent event) => _JournalEventRow(
          event: event,
          mark: marks[event],
          canEdit: canEdit,
          canEditScorer: canEdit,
          onEditScorer: onEditScorer,
          onEditAssist: onEditAssist,
          onDelete: onDelete,
        );

    final widgets = <Widget>[];
    var index = 0;
    while (index < ordered.length) {
      if (widgets.isNotEmpty) {
        widgets.add(const Divider(height: 1, indent: 48));
      }
      final salvo = salvos[ordered[index]];
      if (salvo == null) {
        widgets.add(row(ordered[index]));
        index += 1;
        continue;
      }
      final group = <Widget>[];
      while (
          index < ordered.length && identical(salvos[ordered[index]], salvo)) {
        group.add(row(ordered[index]));
        index += 1;
      }
      widgets.add(_framed(salvo, Column(children: group)));
    }
    return widgets;
  }
}

class _JournalEventRow extends StatelessWidget {
  const _JournalEventRow({
    required this.event,
    this.mark,
    required this.canEdit,
    required this.canEditScorer,
    required this.onEditScorer,
    required this.onEditAssist,
    required this.onDelete,
  });

  final MatchLiveEvent event;

  /// Repère du joueur qui sort : il remplace l'icône. `null` sur un but.
  final SubstitutionExitMark? mark;
  final bool canEdit;
  final bool canEditScorer;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onEditAssist;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (event.type) {
      MatchLiveEventType.goalUs => (
          Icons.sports_soccer_rounded,
          theme.colorScheme.onSurface,
          event.isOpponentOwnGoal
              ? 'But AS Grinta · CSC adverse'
              : 'But AS Grinta · ${event.scorerName ?? 'Buteur à désigner'}'
                  '${event.assistName == null ? '' : ' · passe ${event.assistName}'}',
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
    final isSubstitution = event.type == MatchLiveEventType.substitution;
    final isOpponentGoal = event.type == MatchLiveEventType.goalThem;
    final goalIndent =
        (MediaQuery.sizeOf(context).width * .12).clamp(36.0, 64.0).toDouble();

    Widget actions() => PopupMenuButton<_JournalAction>(
          tooltip: 'Corriger',
          onSelected: (action) {
            switch (action) {
              case _JournalAction.scorer:
                onEditScorer(event);
              case _JournalAction.assist:
                onEditAssist(event);
              case _JournalAction.delete:
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
            if (event.type == MatchLiveEventType.goalUs &&
                event.scorerParticipantId != null)
              PopupMenuItem(
                value: _JournalAction.assist,
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined),
                    const SizedBox(width: AppSpacing.contentGap),
                    Text(
                      event.assistName == null
                          ? 'Ajouter la passe décisive'
                          : 'Corriger la passe décisive',
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
        );

    if (isSubstitution) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              child: mark == null ? null : SubstitutionExitBadge(mark: mark!),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: LiveSubstitutionLine(
                playerInName: event.playerInName ?? '?',
                playerOutName: event.playerOutName ?? '?',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "${event.minute}'",
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 2),
              actions(),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: isOpponentGoal
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isOpponentGoal ? 0 : goalIndent,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: canChooseScorer ? () => onEditScorer(event) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: color),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * .52,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: isOpponentGoal
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: isOpponentGoal
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  if (hasScore)
                                    Text(
                                      '${event.scoreAsGrintaAfter}-'
                                      '${event.scoreAdverseAfter}',
                                      textAlign: isOpponentGoal
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "${event.minute}'",
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 2),
                actions(),
              ],
            ],
          ),
        );
      },
    );
  }
}
