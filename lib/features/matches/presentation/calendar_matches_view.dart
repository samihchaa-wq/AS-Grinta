import 'dart:math' as math;

import 'package:as_grinta/core/calendar/ics_calendar_export.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/domain/calendar_export.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/predictions/presentation/merged_matches_view.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _CalendarDisplayMode { scroll, month }

/// Calendrier principal du club.
///
/// Deux lectures coexistent :
/// - Défilé : cycle temporel complet (à venir, prochain, live, à valider,
///   passés), identique au fonctionnement historique de l'application ;
/// - Par mois : une saison et un mois à la fois, sans section métier, avec une
///   navigation continue qui traverse automatiquement les saisons disponibles.
class CalendarMatchesView extends ConsumerStatefulWidget {
  const CalendarMatchesView({super.key});

  @override
  ConsumerState<CalendarMatchesView> createState() =>
      _CalendarMatchesViewState();
}

class _CalendarMatchesViewState extends ConsumerState<CalendarMatchesView> {
  _CalendarDisplayMode _displayMode = _CalendarDisplayMode.scroll;
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, Future<List<HistoricalMatchResult>>> _historyLoads = {};

  Future<List<HistoricalMatchResult>> _historyForSeason(String seasonName) {
    return _historyLoads.putIfAbsent(
      seasonName,
      () => ref.read(calendarHistoryRepositoryProvider).fetchSeason(seasonName),
    );
  }

  Future<void> _refreshHistory(String seasonName) async {
    setState(() {
      _historyLoads[seasonName] =
          ref.read(calendarHistoryRepositoryProvider).fetchSeason(seasonName);
    });
    await _historyLoads[seasonName];
  }

  Future<void> _refreshModernMatches() async {
    final state = ref.read(matchesControllerProvider);
    await ref.read(matchesControllerProvider.notifier).load(
          seasonId: state.selectedSeasonId,
          allSeasons: true,
        );
  }

  Future<void> _exportCurrentSeason({
    required String seasonId,
    required String seasonName,
  }) async {
    final state = ref.read(matchesControllerProvider);
    final matches = state.matches
        .where((match) => match.seasonId == seasonId)
        .toList(growable: false);

    if (matches.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun match à ajouter au calendrier.')),
      );
      return;
    }

    try {
      final contents = buildSeasonIcs(
        seasonName: seasonName,
        matches: matches,
      );
      await downloadIcsFile(
        contents: contents,
        filename: 'sporteasy-grinta-$seasonName.ics',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Calendrier .ics généré. Ouvre le fichier pour l’ajouter à ton agenda.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    }
  }

  void _selectSeason(
    String? seasonName,
    List<Map<String, dynamic>> seasons,
  ) {
    if (seasonName == null) return;
    final season = seasons.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['name']?.toString() == seasonName,
          orElse: () => null,
        );
    if (season == null) return;
    setState(() => _monthCursor = _initialMonthForSeason(season));
  }

  void _moveMonth(
    int delta,
    List<Map<String, dynamic>> seasons,
  ) {
    if (seasons.isEmpty) return;
    final candidate = DateTime(_monthCursor.year, _monthCursor.month + delta);
    final bounds = _monthBounds(seasons);
    if (bounds == null ||
        candidate.isBefore(bounds.$1) ||
        candidate.isAfter(bounds.$2)) {
      return;
    }
    setState(() => _monthCursor = candidate);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final seasons = [...state.seasons]..sort(
        (a, b) => b['name'].toString().compareTo(a['name'].toString()),
      );
    final currentSeason = seasons.cast<Map<String, dynamic>?>().firstWhere(
          (season) => season?['status']?.toString() == 'open',
          orElse: () => null,
        );
    final currentSeasonName = currentSeason?['name']?.toString();
    final currentSeasonId = currentSeason?['id']?.toString();
    final selectedSeason =
        _seasonForMonth(seasons, _monthCursor) ?? currentSeason;
    final selectedSeasonName = selectedSeason?['name']?.toString();
    final selectedSeasonId = selectedSeason?['id']?.toString();
    final bounds = _monthBounds(seasons);
    final canGoPrevious = bounds != null && _monthCursor.isAfter(bounds.$1);
    final canGoNext = bounds != null && _monthCursor.isBefore(bounds.$2);

    final exportAction = currentSeasonId != null && currentSeasonName != null
        ? () => _exportCurrentSeason(
              seasonId: currentSeasonId,
              seasonName: currentSeasonName,
            )
        : null;

    return Column(
      children: [
        _CalendarToolbar(
          displayMode: _displayMode,
          onDisplayModeChanged: (mode) {
            setState(() => _displayMode = mode);
          },
          onExport: exportAction,
          seasons: seasons,
          selectedSeasonName: selectedSeasonName,
          currentSeasonName: currentSeasonName,
          monthCursor: _monthCursor,
          canGoPrevious: canGoPrevious,
          canGoNext: canGoNext,
          onSeasonChanged: (value) => _selectSeason(value, seasons),
          onPreviousMonth: () => _moveMonth(-1, seasons),
          onNextMonth: () => _moveMonth(1, seasons),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = math.min(constraints.maxWidth, 1120.0);
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  height: constraints.maxHeight,
                  child: _displayMode == _CalendarDisplayMode.scroll
                      ? const MergedMatchesView()
                      : _buildMonthView(
                          state: state,
                          selectedSeason: selectedSeason,
                          selectedSeasonName: selectedSeasonName,
                          selectedSeasonId: selectedSeasonId,
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthView({
    required MatchesState state,
    required Map<String, dynamic>? selectedSeason,
    required String? selectedSeasonName,
    required String? selectedSeasonId,
  }) {
    if (state.isLoading && state.seasons.isEmpty) {
      return const Center(child: GrintaProgressIndicator());
    }
    if (state.error != null && state.seasons.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          GrintaEmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Calendrier indisponible',
            message: state.error!,
            tone: GrintaEmptyTone.alert,
          ),
        ],
      );
    }
    if (selectedSeason == null ||
        selectedSeasonName == null ||
        selectedSeasonId == null) {
      return const _MonthEmptyState(
        title: 'Aucune saison disponible',
        message: 'Les saisons apparaîtront ici dès qu’elles seront créées.',
      );
    }

    final modernMatches = state.matches
        .where((match) => match.seasonId == selectedSeasonId)
        .toList(growable: false);
    final isOpenSeason = selectedSeason['status']?.toString() == 'open';
    final usesModernMatches = isOpenSeason || modernMatches.isNotEmpty;

    if (usesModernMatches) {
      return _ModernMonthView(
        month: _monthCursor,
        matches: modernMatches,
        onRefresh: _refreshModernMatches,
      );
    }

    return _HistoricalMonthView(
      month: _monthCursor,
      seasonName: selectedSeasonName,
      future: _historyForSeason(selectedSeasonName),
      onRefresh: () => _refreshHistory(selectedSeasonName),
    );
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.displayMode,
    required this.onDisplayModeChanged,
    required this.onExport,
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
              icon: Icon(Icons.view_agenda_outlined, size: 18),
              label: Text('Défilé'),
            ),
            ButtonSegment(
              value: _CalendarDisplayMode.month,
              icon: Icon(Icons.calendar_view_month_outlined, size: 18),
              label: Text('Par mois'),
            ),
          ],
          selected: {displayMode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onDisplayModeChanged(selection.first);
          },
        );

        final exportButton = OutlinedButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: const Text('Ajouter à mon calendrier (.ics)'),
        );

        final seasonSelector = selectedSeasonName == null || seasons.isEmpty
            ? null
            : DropdownButtonFormField<String>(
                initialValue: selectedSeasonName,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Saison',
                  prefixIcon: Icon(Icons.history_rounded),
                ),
                items: seasons
                    .map(
                      (season) => DropdownMenuItem<String>(
                        value: season['name'].toString(),
                        child: Text(
                          season['name'].toString() == currentSeasonName
                              ? '${season['name']} — actuelle'
                              : season['name'].toString(),
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onSeasonChanged,
              );

        final monthNavigator = _MonthNavigator(
          month: monthCursor,
          canGoPrevious: canGoPrevious,
          canGoNext: canGoNext,
          onPrevious: onPreviousMonth,
          onNext: onNextMonth,
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
              if (compact) ...[
                modeSelector,
                if (onExport != null) ...[
                  const SizedBox(height: AppSpacing.microGap),
                  exportButton,
                ],
              ] else
                Row(
                  children: [
                    modeSelector,
                    const Spacer(),
                    if (onExport != null) exportButton,
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

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.month,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

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
            tooltip: 'Mois précédent',
            onPressed: canGoPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              _monthLabel(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Mois suivant',
            onPressed: canGoNext ? onNext : null,
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
    required this.onRefresh,
  });

  final DateTime month;
  final List<MatchModel> matches;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminViewProvider);
    final monthMatches = matches
        .where((match) => _sameMonth(match.kickoffAt, month))
        .toList()
      ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));

    if (monthMatches.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: _MonthEmptyState(
                title: 'Aucun match en ${_monthLabel(month)}',
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
        itemCount: monthMatches.length,
        itemBuilder: (context, index) {
          final match = monthMatches[index];
          final adminActions =
              isAdmin ? AdminMatchOptionsButton(match: match) : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.contentGap),
            child: match.isFinished
                ? MatchHistoryCard(
                    match: match,
                    adminActions: adminActions,
                  )
                : _MonthlyMatchCard(
                    match: match,
                    adminActions: adminActions,
                  ),
          );
        },
      ),
    );
  }
}

class _HistoricalMonthView extends StatelessWidget {
  const _HistoricalMonthView({
    required this.month,
    required this.seasonName,
    required this.future,
    required this.onRefresh,
  });

  final DateTime month;
  final String seasonName;
  final Future<List<HistoricalMatchResult>> future;
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

        final matches = (snapshot.data ?? const <HistoricalMatchResult>[])
            .where((match) => _sameMonth(match.date, month))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        if (matches.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 360,
                  child: _MonthEmptyState(
                    title: 'Aucun match en ${_monthLabel(month)}',
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
            itemCount: matches.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.contentGap),
              child: _HistoricalMatchCard(match: matches[index]),
            ),
          ),
        );
      },
    );
  }
}

class _MonthlyMatchCard extends StatelessWidget {
  const _MonthlyMatchCard({
    required this.match,
    required this.adminActions,
  });

  final MatchModel match;
  final Widget? adminActions;

  @override
  Widget build(BuildContext context) {
    final phase = match.phase();
    final opponent = match.isInternal
        ? 'Match entre nous'
        : match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final statusColor = switch (phase) {
      MatchDisplayPhase.live => AppTheme.error,
      MatchDisplayPhase.awaitingValidation => AppTheme.reward,
      MatchDisplayPhase.cancelled => AppTheme.error,
      MatchDisplayPhase.next => AppTheme.primaryBright,
      _ => AppTheme.textSecondary,
    };

    return Card(
      color: const Color(0xFF20242C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF626A78), width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onTap(context, phase),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 12, 14),
          child: MatchDateHeader(
            kickoffAt: match.kickoffAt,
            secondary: AppTheme.textSecondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MatchFixture(
                  homeName: homeName,
                  awayName: awayName,
                  grintaIsHome: match.isHome,
                  finished: false,
                  nameStyle: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 17, height: 1.1),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.statusLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    if (adminActions != null) ...[
                      const SizedBox(width: 4),
                      SizedBox(width: 38, child: adminActions),
                    ],
                  ],
                ),
              ],
            ),
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
        return () => context.push('/matches/${match.id}/lineup?section=$section');
      case MatchDisplayPhase.cancelled:
        return null;
    }
  }
}

class _HistoricalMatchCard extends StatelessWidget {
  const _HistoricalMatchCard({required this.match});

  final HistoricalMatchResult match;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF20242C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF626A78), width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 12, 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 52,
                child: _HistoricalDateColumn(date: match.date),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: AppTheme.textSecondary.withValues(alpha: .25),
              ),
              Expanded(
                child: MatchFixture(
                  homeName: 'AS Grinta',
                  awayName: match.opponentName,
                  grintaIsHome: true,
                  homeScore: match.grintaScore,
                  awayScore: match.opponentScore,
                  finished: true,
                  nameStyle: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 17, height: 1.1),
                  scoreFontSize: 20,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoricalDateColumn extends StatelessWidget {
  const _HistoricalDateColumn({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final main = Theme.of(context).textTheme.bodyMedium?.color;
    const soft = AppTheme.textSecondary;

    Widget line(String text, {bool bold = false}) => Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bold ? main : soft,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            fontSize: 14,
            height: 1.15,
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line(AppFormats.weekdayShort(date)),
        line(AppFormats.dayNumber(date), bold: true),
        line(AppFormats.monthShort(date)),
        line('${date.year}'),
      ],
    );
  }
}

class _MonthEmptyState extends StatelessWidget {
  const _MonthEmptyState({
    required this.title,
    required this.message,
  });

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
