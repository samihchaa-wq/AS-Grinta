part of 'calendar_matches_view.dart';

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.displayMode,
    required this.onDisplayModeChanged,
    required this.onExport,
    required this.onCreate,
    required this.seasons,
    required this.selectedSeasonName,
    required this.currentSeasonName,
    required this.monthCursor,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onSeasonChanged,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final _CalendarDisplayMode displayMode;
  final ValueChanged<_CalendarDisplayMode> onDisplayModeChanged;
  final VoidCallback? onExport;
  final VoidCallback? onCreate;
  final List<Map<String, dynamic>> seasons;
  final String? selectedSeasonName;
  final String? currentSeasonName;
  final DateTime monthCursor;
  final bool canGoPrevious;
  final bool canGoNext;
  final ValueChanged<String?> onSeasonChanged;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final outerInset = math.max(
          AppSpacing.screenGutter,
          (constraints.maxWidth - 1120) / 2 + AppSpacing.screenGutter,
        );
        final compact = constraints.maxWidth < 720;

        final modeSelector = SegmentedButton<_CalendarDisplayMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _CalendarDisplayMode.scroll,
              label: Text('Défilé'),
            ),
            ButtonSegment(
              value: _CalendarDisplayMode.month,
              label: Text('Par mois'),
            ),
          ],
          selected: {displayMode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onDisplayModeChanged(selection.first);
          },
        );

        // Boutons d'action compactes (icônes seules avec tooltip) : la barre
        // du haut est désormais partagée à 2/3 pour le mode d'affichage
        // Défilé/Par mois et à 1/3 pour ces deux actions.
        final exportIconButton = IconButton.outlined(
          onPressed: onExport,
          tooltip: 'Ajouter au calendrier ics',
          icon: const Icon(Icons.calendar_month_outlined),
        );
        final createIconButton = IconButton.outlined(
          onPressed: onCreate,
          tooltip: 'Ajouter un événement',
          icon: const Icon(Icons.add_rounded),
        );
        final hasActions = onExport != null || onCreate != null;
        final actionsRow = hasActions
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (onCreate != null) Expanded(child: createIconButton),
                  if (onCreate != null && onExport != null)
                    const SizedBox(width: AppSpacing.microGap),
                  if (onExport != null) Expanded(child: exportIconButton),
                ],
              )
            : const SizedBox.shrink();

        // Les saisons arrivent triées de la plus récente à la plus ancienne :
        // la flèche gauche recule donc vers l'index suivant.
        final seasonNames = [
          for (final season in seasons) season['name'].toString(),
        ];
        final selectedName = selectedSeasonName;
        final seasonIndex =
            selectedName == null ? -1 : seasonNames.indexOf(selectedName);
        final seasonSelector = selectedName == null || seasonIndex < 0
            ? null
            : _StepNavigator(
                label: selectedName == currentSeasonName
                    ? '$selectedName — actuelle'
                    : selectedName,
                previousTooltip: 'Saison précédente',
                nextTooltip: 'Saison suivante',
                onPrevious: seasonIndex < seasonNames.length - 1
                    ? () => onSeasonChanged(seasonNames[seasonIndex + 1])
                    : null,
                onNext: seasonIndex > 0
                    ? () => onSeasonChanged(seasonNames[seasonIndex - 1])
                    : null,
              );

        final monthNavigator = _StepNavigator(
          label: _monthLabel(monthCursor),
          previousTooltip: 'Mois précédent',
          nextTooltip: 'Mois suivant',
          onPrevious: canGoPrevious ? onPreviousMonth : null,
          onNext: canGoNext ? onNextMonth : null,
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            outerInset,
            AppSpacing.contentGap,
            outerInset,
            AppSpacing.microGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 2, child: modeSelector),
                  if (hasActions) ...[
                    const SizedBox(width: AppSpacing.contentGap),
                    Expanded(flex: 1, child: actionsRow),
                  ],
                ],
              ),
              if (displayMode == _CalendarDisplayMode.month) ...[
                const SizedBox(height: AppSpacing.contentGap),
                if (compact) ...[
                  if (seasonSelector != null) seasonSelector,
                  const SizedBox(height: AppSpacing.microGap),
                  monthNavigator,
                ] else
                  Row(
                    children: [
                      if (seasonSelector != null)
                        SizedBox(width: 300, child: seasonSelector),
                      const Spacer(),
                      SizedBox(width: 320, child: monthNavigator),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Sélecteur « ‹ libellé › » partagé par le choix de la saison et du mois.
/// Une flèche passée à `null` est affichée désactivée.
class _StepNavigator extends StatelessWidget {
  const _StepNavigator({
    required this.label,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final String previousTooltip;
  final String nextTooltip;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.outline.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: previousTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400),
            ),
          ),
          IconButton(
            tooltip: nextTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _ModernMonthView extends ConsumerWidget {
  const _ModernMonthView({
    required this.month,
    required this.matches,
    required this.events,
    required this.onRefresh,
  });

  final DateTime month;
  final List<MatchModel> matches;
  final List<ClubEvent> events;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminViewProvider);
    final entries = <_ModernMonthEntry>[
      for (final match in matches)
        if (_sameMonth(match.kickoffAt, month)) _ModernMonthEntry.match(match),
      for (final event in events)
        if (_sameMonth(event.startsAt, month)) _ModernMonthEntry.event(event),
    ]..sort((a, b) => a.date.compareTo(b.date));

    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: _MonthEmptyState(
                title: 'Aucun rendez-vous en ${_monthLabel(month)}',
                message: 'Change de mois avec les flèches pour continuer.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.contentGap,
          AppSpacing.screenGutter,
          32,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final match = entry.match;
          final adminActions = match != null &&
                  isAdmin &&
                  AdminMatchOptionsButton.hasOptions(match)
              ? AdminMatchOptionsButton(match: match)
              : null;
          return Padding(
            padding: const EdgeInsets.only(
              bottom: CalendarCardSpacing.betweenCards,
            ),
            child: match != null
                ? match.isFinished
                    ? MatchHistoryCard(
                        match: match,
                        adminActions: adminActions,
                      )
                    : MonthlyMatchCard(
                        match: match,
                        adminActions: adminActions,
                      )
                : ClubEventCard(event: entry.event!, isAdmin: isAdmin),
          );
        },
      ),
    );
  }
}

class _ModernMonthEntry {
  const _ModernMonthEntry._({this.match, this.event, required this.date});

  final MatchModel? match;
  final ClubEvent? event;
  final DateTime date;

  factory _ModernMonthEntry.match(MatchModel match) =>
      _ModernMonthEntry._(match: match, date: match.kickoffAt);

  factory _ModernMonthEntry.event(ClubEvent event) =>
      _ModernMonthEntry._(event: event, date: event.startsAt);
}

class _HistoricalMonthView extends StatelessWidget {
  const _HistoricalMonthView({
    required this.month,
    required this.seasonName,
    required this.future,
    required this.events,
    required this.onRefresh,
  });

  final DateTime month;
  final String seasonName;
  final Future<List<HistoricalMatchResult>> future;
  final List<ClubEvent> events;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HistoricalMatchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: GrintaProgressIndicator());
        }
        if (snapshot.hasError) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: [
                GrintaEmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: 'Historique indisponible',
                  message: humanizeError(snapshot.error!),
                  tone: GrintaEmptyTone.alert,
                ),
              ],
            ),
          );
        }

        final entries = <_HistoricalMonthEntry>[
          for (final match in snapshot.data ?? const <HistoricalMatchResult>[])
            if (_sameMonth(match.date, month))
              _HistoricalMonthEntry.match(match),
          for (final event in events)
            if (_sameMonth(event.startsAt, month))
              _HistoricalMonthEntry.event(event),
        ]..sort((a, b) => a.date.compareTo(b.date));

        if (entries.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 360,
                  child: _MonthEmptyState(
                    title: 'Aucun rendez-vous en ${_monthLabel(month)}',
                    message:
                        'Historique $seasonName — change de mois avec les flèches.',
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.contentGap,
              AppSpacing.screenGutter,
              32,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Padding(
                padding: const EdgeInsets.only(
                  bottom: CalendarCardSpacing.betweenCards,
                ),
                child: entry.match != null
                    ? HistoricalMatchCard(match: entry.match!)
                    : ClubEventCard(event: entry.event!),
              );
            },
          ),
        );
      },
    );
  }
}

class _HistoricalMonthEntry {
  const _HistoricalMonthEntry._({this.match, this.event, required this.date});

  final HistoricalMatchResult? match;
  final ClubEvent? event;
  final DateTime date;

  factory _HistoricalMonthEntry.match(HistoricalMatchResult match) =>
      _HistoricalMonthEntry._(match: match, date: match.date);

  factory _HistoricalMonthEntry.event(ClubEvent event) =>
      _HistoricalMonthEntry._(event: event, date: event.startsAt);
}

class ClubEventCard extends ConsumerWidget {
  const ClubEventCard({super.key, required this.event, this.isAdmin = false});

  final ClubEvent event;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> edit() async {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CalendarEntryFormPage(event: event)),
      );
      if (changed == true) ref.invalidate(clubEventsProvider);
    }

    final editButton = isAdmin
        ? IconButton(
            tooltip: 'Modifier l’événement',
            onPressed: edit,
            color: CalendarCardPalette.eventBorder,
            icon: const Icon(Icons.edit_rounded),
          )
        : null;

    return Card(
      color: CalendarCardPalette.eventSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(
          color: CalendarCardPalette.eventBorder,
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CalendarCardActionsOverlay(
        actions: editButton,
        child: CalendarCardSections(
          header: CalendarDateLine(
            kickoffAt: event.startsAt,
            label: 'Événement',
            endInset:
                editButton != null ? CalendarCardActionsOverlay.dateInset : 0,
          ),
          body: CalendarCenteredTitle(event.title),
          footer: event.location.trim().isEmpty
              ? null
              : CalendarAddressLine(event.location),
        ),
      ),
    );
  }
}

/// Carte d'un match à venir dans la vue « Par mois » du calendrier.
class MonthlyMatchCard extends StatelessWidget {
  const MonthlyMatchCard({
    super.key,
    required this.match,
    required this.adminActions,
  });

  final MatchModel match;
  final Widget? adminActions;

  @override
  Widget build(BuildContext context) {
    final phase = match.phase();
    final address = match.address?.trim();
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final surface = match.isCancelled
        ? CalendarCardPalette.cancelledSurface
        : CalendarCardPalette.matchSurface(match.matchType);
    final border = match.isCancelled
        ? CalendarCardPalette.cancelledBorder
        : CalendarCardPalette.matchBorder(match.matchType);
    final statusColor = switch (phase) {
      MatchDisplayPhase.live => AppTheme.error,
      MatchDisplayPhase.awaitingValidation => AppTheme.reward,
      MatchDisplayPhase.cancelled => AppTheme.error,
      MatchDisplayPhase.next => border,
      _ => border,
    };

    return Card(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onTap(context, phase),
        child: CalendarCardActionsOverlay(
          actions: adminActions,
          child: CalendarCardSections(
            header: CalendarDateLine(
              kickoffAt: match.kickoffAt,
              label: match.isInternal ? null : match.calendarTypeLabel,
              endInset: adminActions != null
                  ? CalendarCardActionsOverlay.dateInset
                  : 0,
            ),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (match.isInternal)
                  const CalendarCenteredTitle('Match entre nous')
                else
                  CalendarScoreline(
                    homeName: homeName,
                    awayName: awayName,
                    grintaIsHome: match.isHome,
                    foreground: match.isCancelled
                        ? AppTheme.textFaint
                        : AppTheme.textPrimary,
                  ),
                const SizedBox(height: CalendarCardSpacing.line),
                Text(
                  match.statusLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ],
            ),
            footer: address != null && address.isNotEmpty
                ? CalendarAddressLine(
                    address,
                    onTap: () => showMatchAddressSheet(context, address),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  VoidCallback? _onTap(BuildContext context, MatchDisplayPhase phase) {
    switch (phase) {
      case MatchDisplayPhase.past:
        return () => context.push('/matches/${match.id}');
      case MatchDisplayPhase.upcoming:
        return () => context.push(
              '/matches/${match.id}/lineup?section=info&infoOnly=true',
            );
      case MatchDisplayPhase.next:
        return () => context.push('/matches/${match.id}/lineup?section=info');
      case MatchDisplayPhase.live:
        return () => context.push(
              '/matches/${match.id}/lineup?section=${match.isInternal ? 'composition' : 'live'}',
            );
      case MatchDisplayPhase.awaitingValidation:
        final section = match.liveState == null
            ? 'info'
            : match.isInternal
                ? 'composition'
                : 'live';
        return () =>
            context.push('/matches/${match.id}/lineup?section=$section');
      case MatchDisplayPhase.cancelled:
        return null;
    }
  }
}

class _MonthEmptyState extends StatelessWidget {
  const _MonthEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: GrintaEmptyState(
          icon: Icons.event_busy_rounded,
          title: title,
          message: message,
          compact: true,
        ),
      ),
    );
  }
}

Map<String, dynamic>? _seasonForMonth(
  List<Map<String, dynamic>> seasons,
  DateTime month,
) {
  for (final season in seasons) {
    final range = _seasonRange(season['name']?.toString());
    if (range == null) continue;
    final start = DateTime(range.$1, DateTime.july);
    final end = DateTime(range.$2, DateTime.june);
    if (!month.isBefore(start) && !month.isAfter(end)) return season;
  }
  return null;
}

(DateTime, DateTime)? _monthBounds(List<Map<String, dynamic>> seasons) {
  DateTime? earliest;
  DateTime? latest;
  for (final season in seasons) {
    final range = _seasonRange(season['name']?.toString());
    if (range == null) continue;
    final start = DateTime(range.$1, DateTime.july);
    final end = DateTime(range.$2, DateTime.june);
    if (earliest == null || start.isBefore(earliest)) earliest = start;
    if (latest == null || end.isAfter(latest)) latest = end;
  }
  if (earliest == null || latest == null) return null;
  return (earliest, latest);
}

DateTime _initialMonthForSeason(Map<String, dynamic> season) {
  final range = _seasonRange(season['name']?.toString());
  if (range == null) {
    return DateTime(DateTime.now().year, DateTime.now().month);
  }
  final start = DateTime(range.$1, DateTime.july);
  final end = DateTime(range.$2, DateTime.june);
  final now = DateTime(DateTime.now().year, DateTime.now().month);
  if (!now.isBefore(start) && !now.isAfter(end)) return now;
  return now.isBefore(start) ? start : end;
}

(int, int)? _seasonRange(String? seasonName) {
  if (seasonName == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(seasonName);
  if (match == null) return null;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  if (start == null || end == null || end != start + 1) return null;
  return (start, end);
}

bool _sameMonth(DateTime value, DateTime month) =>
    value.year == month.year && value.month == month.month;

String _monthLabel(DateTime month) {
  const names = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];
  return '${names[month.month - 1]} ${month.year}';
}
