import 'dart:math' as math;

import 'package:as_grinta/core/calendar/ics_calendar_export.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/domain/calendar_export.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/presentation/merged_matches_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Calendrier principal du club.
///
/// La saison ouverte conserve le cycle de match complet. Les saisons archivées
/// affichent uniquement les résultats historiques importés, en lecture seule.
class CalendarMatchesView extends ConsumerStatefulWidget {
  const CalendarMatchesView({super.key});

  @override
  ConsumerState<CalendarMatchesView> createState() =>
      _CalendarMatchesViewState();
}

class _CalendarMatchesViewState extends ConsumerState<CalendarMatchesView> {
  String? _selectedSeasonName;
  String? _historySeasonName;
  Future<List<HistoricalMatchResult>>? _historyFuture;

  void _selectSeason(String? seasonName, String? currentSeasonName) {
    if (seasonName == null) return;
    setState(() {
      _selectedSeasonName = seasonName;
      if (seasonName == currentSeasonName) {
        _historySeasonName = null;
        _historyFuture = null;
      } else {
        _historySeasonName = seasonName;
        _historyFuture =
            ref.read(calendarHistoryRepositoryProvider).fetchSeason(seasonName);
      }
    });
  }

  void _refreshHistory() {
    final seasonName = _historySeasonName;
    if (seasonName == null) return;
    setState(() {
      _historyFuture =
          ref.read(calendarHistoryRepositoryProvider).fetchSeason(seasonName);
    });
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
      final contents = buildSeasonIcs(seasonName: seasonName, matches: matches);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final seasons = [...state.seasons]
      ..sort((a, b) => b['name'].toString().compareTo(a['name'].toString()));
    final currentSeason = seasons.cast<Map<String, dynamic>?>().firstWhere(
          (season) => season?['status']?.toString() == 'open',
          orElse: () => null,
        );
    final currentSeasonName = currentSeason?['name']?.toString();
    final currentSeasonId = currentSeason?['id']?.toString();
    final selectedSeasonName = _selectedSeasonName ??
        currentSeasonName ??
        (seasons.isNotEmpty ? seasons.first['name']?.toString() : null);
    final showCurrentSeason = selectedSeasonName == null ||
        currentSeasonName == null ||
        selectedSeasonName == currentSeasonName;

    return Column(
      children: [
        if (seasons.isNotEmpty && selectedSeasonName != null)
          _CalendarToolbar(
            seasons: seasons,
            selectedSeasonName: selectedSeasonName,
            currentSeasonName: currentSeasonName,
            onSeasonChanged: (value) => _selectSeason(value, currentSeasonName),
            onExport: showCurrentSeason &&
                    currentSeasonId != null &&
                    currentSeasonName != null
                ? () => _exportCurrentSeason(
                      seasonId: currentSeasonId,
                      seasonName: currentSeasonName,
                    )
                : null,
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
                  child: showCurrentSeason
                      ? const MergedMatchesView()
                      : _HistoricalSeasonView(
                          seasonName: selectedSeasonName!,
                          future: _historySeasonName == selectedSeasonName
                              ? _historyFuture
                              : ref
                                  .read(calendarHistoryRepositoryProvider)
                                  .fetchSeason(selectedSeasonName),
                          onRefresh: () async => _refreshHistory(),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.seasons,
    required this.selectedSeasonName,
    required this.currentSeasonName,
    required this.onSeasonChanged,
    required this.onExport,
  });

  final List<Map<String, dynamic>> seasons;
  final String selectedSeasonName;
  final String? currentSeasonName;
  final ValueChanged<String?> onSeasonChanged;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final outerInset = math.max(
          AppSpacing.screenGutter,
          (constraints.maxWidth - 1120) / 2 + AppSpacing.screenGutter,
        );
        final compact = constraints.maxWidth < 620;

        final selector = DropdownButtonFormField<String>(
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

        final exportButton = OutlinedButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: const Text('Ajouter à mon calendrier (.ics)'),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            outerInset,
            AppSpacing.contentGap,
            outerInset,
            AppSpacing.microGap,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    selector,
                    if (onExport != null) ...[
                      const SizedBox(height: AppSpacing.microGap),
                      exportButton,
                    ],
                  ],
                )
              : Row(
                  children: [
                    SizedBox(width: 300, child: selector),
                    const Spacer(),
                    if (onExport != null) exportButton,
                  ],
                ),
        );
      },
    );
  }
}

class _HistoricalSeasonView extends StatelessWidget {
  const _HistoricalSeasonView({
    required this.seasonName,
    required this.future,
    required this.onRefresh,
  });

  final String seasonName;
  final Future<List<HistoricalMatchResult>>? future;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final load = future;
    if (load == null) {
      return const Center(child: GrintaProgressIndicator());
    }

    return FutureBuilder<List<HistoricalMatchResult>>(
      future: load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: GrintaProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
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
          );
        }

        final matches = snapshot.data ?? const <HistoricalMatchResult>[];
        if (matches.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: [
                GrintaEmptyState(
                  icon: Icons.history_rounded,
                  title: 'Aucun match en $seasonName',
                  message:
                      'Aucun résultat historique n’est enregistré pour cette saison.',
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
            itemCount: matches.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.contentGap),
                  child: _HistoricalNotice(),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.contentGap),
                child: _HistoricalMatchCard(match: matches[index - 1]),
              );
            },
          ),
        );
      },
    );
  }
}

class _HistoricalNotice extends StatelessWidget {
  const _HistoricalNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            const Icon(Icons.lock_clock_outlined, color: AppTheme.textFaint),
            const SizedBox(width: AppSpacing.contentGap),
            Expanded(
              child: Text(
                'Historique importé — consultation uniquement.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoricalMatchCard extends StatelessWidget {
  const _HistoricalMatchCard({required this.match});

  final HistoricalMatchResult match;

  @override
  Widget build(BuildContext context) {
    final resultColor = match.isWin
        ? AppTheme.success
        : match.isLoss
            ? AppTheme.error
            : AppTheme.reward;
    final resultLabel = match.isWin
        ? 'Victoire'
        : match.isLoss
            ? 'Défaite'
            : 'Nul';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                _formatDate(match.date),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.textFaint,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: AppSpacing.contentGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AS Grinta - ${match.opponentName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    resultLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: resultColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.contentGap),
            Text(
              '${match.grintaScore} - ${match.opponentScore}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: resultColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}\n${value.year}';
  }
}
