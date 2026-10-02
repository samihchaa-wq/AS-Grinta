import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

const _teamGreen = Color(0xFF3BD10D);
const _teamYellow = Color(0xFFFFCA1A);
const _teamRed = Color(0xFFFF3B30);

class TeamStatisticsPanel extends ConsumerWidget {
  const TeamStatisticsPanel({required this.period, super.key});

  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(teamStatisticsPeriodProvider(period));

    Future<void> refresh() async {
      ref.invalidate(teamStatisticsPeriodProvider(period));
      await ref.read(teamStatisticsPeriodProvider(period).future);
    }

    return dataAsync.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (error, _) => _ScrollableMessage(
        message: humanizeError(error),
        onRefresh: refresh,
      ),
      data: (statistics) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.contentGap,
            AppSpacing.screenGutter,
            36,
          ),
          children: [
            const _TeamSectionTitle('Bilan'),
            const SizedBox(height: 10),
            _TeamResultsCard(
              statistics: statistics,
              recentResults: period == StatisticsPeriod.current
                  ? statistics.recentResults
                  : const [],
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            const _TeamSectionTitle('Buts'),
            const SizedBox(height: 10),
            _TeamGoalsCard(statistics: statistics),
            if (statistics.scoreMarginDistribution.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sectionGap),
              const _TeamSectionTitle('Écart de score'),
              const SizedBox(height: 3),
              Text(
                'Nombre de matchs selon l’écart de buts final',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
              ),
              const SizedBox(height: 10),
              _ScoreMarginCard(
                distribution: statistics.scoreMarginDistribution,
              ),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
            const _TeamSectionTitle('Séries'),
            const SizedBox(height: 10),
            _TeamStreaksSection(statistics: statistics),
          ],
        ),
      ),
    );
  }
}

class _TeamSectionTitle extends StatelessWidget {
  const _TeamSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w400,
          ),
    );
  }
}

class _TeamResultsCard extends StatelessWidget {
  const _TeamResultsCard({
    required this.statistics,
    required this.recentResults,
  });

  final TeamStatistics statistics;
  final List<String> recentResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final played = statistics.matchesPlayed;
    final percents = _roundedPercents(
      [statistics.wins, statistics.draws, statistics.losses],
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final donutSize = math.min(132.0, constraints.maxWidth * .4);

                return Row(
                  children: [
                    SizedBox.square(
                      dimension: donutSize,
                      child: CustomPaint(
                        painter: _ResultsDonutPainter(
                          values: [
                            statistics.wins,
                            statistics.draws,
                            statistics.losses,
                          ],
                          trackColor:
                              theme.colorScheme.onSurface.withValues(alpha: .1),
                        ),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(donutSize * .2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$played',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.w400),
                                  ),
                                  Text(
                                    played > 1 ? 'matchs' : 'match',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _ResultLegendRow(
                            label: 'Victoires',
                            percent: percents[0],
                            value: statistics.wins,
                            color: _teamGreen,
                          ),
                          const SizedBox(height: 12),
                          _ResultLegendRow(
                            label: 'Nuls',
                            percent: percents[1],
                            value: statistics.draws,
                            color: _teamYellow,
                          ),
                          const SizedBox(height: 12),
                          _ResultLegendRow(
                            label: 'Défaites',
                            percent: percents[2],
                            value: statistics.losses,
                            color: _teamRed,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (recentResults.isNotEmpty) ...[
              const SizedBox(height: 18),
              Divider(
                height: 1,
                color: theme.colorScheme.onSurface.withValues(alpha: .1),
              ),
              const SizedBox(height: 14),
              Text(
                'Derniers matchs',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 10),
              _RecentResultsRow(results: recentResults),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pourcentages entiers dont la somme fait toujours 100 (méthode du plus
/// fort reste), pour ne jamais afficher 68 % + 15 % + 18 % = 101 %.
List<int> _roundedPercents(List<int> values) {
  final total = values.fold<int>(0, (sum, value) => sum + value);
  if (total == 0) return [for (final _ in values) 0];
  final exact = [for (final value in values) value * 100 / total];
  final rounded = [for (final value in exact) value.floor()];
  final byRemainder = List.generate(values.length, (index) => index)
    ..sort(
      (a, b) => (exact[b] - rounded[b]).compareTo(exact[a] - rounded[a]),
    );
  var missing = 100 - rounded.fold<int>(0, (sum, value) => sum + value);
  for (final index in byRemainder) {
    if (missing == 0) break;
    rounded[index]++;
    missing--;
  }
  return rounded;
}

class _ResultLegendRow extends StatelessWidget {
  const _ResultLegendRow({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
  });

  final String label;
  final int value;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$percent %',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Un seul anneau découpé en victoires, nuls et défaites, dans cet ordre.
class _ResultsDonutPainter extends CustomPainter {
  const _ResultsDonutPainter({
    required this.values,
    required this.trackColor,
  });

  final List<int> values;
  final Color trackColor;

  static const _colors = [_teamGreen, _teamYellow, _teamRed];

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final strokeWidth = side * .12;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    ).deflate(strokeWidth / 2);
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    canvas.drawArc(rect, 0, math.pi * 2, false, stroke(trackColor));

    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return;
    final visible = values.where((value) => value > 0).length;
    // Un petit espace sépare les parts, sauf quand une seule existe.
    final gap = visible > 1 ? .04 : 0.0;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      if (values[index] == 0) continue;
      final sweep = math.pi * 2 * values[index] / total;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0.0, sweep - gap),
        false,
        stroke(_colors[index]),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_ResultsDonutPainter oldDelegate) =>
      oldDelegate.trackColor != trackColor ||
      oldDelegate.values.length != values.length ||
      [
        for (var index = 0; index < values.length; index++)
          oldDelegate.values[index] != values[index],
      ].contains(true);
}

class _RecentResultsRow extends StatelessWidget {
  const _RecentResultsRow({required this.results});

  final List<String> results;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final result in results)
          SizedBox.square(
            dimension: 30,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: switch (result) {
                  'V' => _teamGreen,
                  'N' => _teamYellow,
                  _ => _teamRed,
                },
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  result,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TeamGoalsCard extends StatelessWidget {
  const _TeamGoalsCard({required this.statistics});

  final TeamStatistics statistics;

  static String _average(double value) =>
      value.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = statistics.goalDifference;
    final differenceColor = difference > 0
        ? _teamGreen
        : difference < 0
            ? _teamRed
            : _teamYellow;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _GoalValue(
                      value: statistics.goalsFor,
                      label: 'marqués',
                      average: _average(statistics.goalsForPerMatch),
                      color: _teamGreen,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.onSurface.withValues(alpha: .12),
                  ),
                  Expanded(
                    child: _GoalValue(
                      value: statistics.goalsAgainst,
                      label: 'encaissés',
                      average: _average(statistics.goalsAgainstPerMatch),
                      color: _teamRed,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: theme.colorScheme.onSurface.withValues(alpha: .1),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Différence de buts',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  difference > 0 ? '+$difference' : '$difference',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: differenceColor,
                    fontWeight: FontWeight.w400,
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

class _GoalValue extends StatelessWidget {
  const _GoalValue({
    required this.value,
    required this.label,
    required this.average,
    required this.color,
  });

  final int value;
  final String label;
  final String average;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.microGap),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$value',
              maxLines: 1,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$average par match',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreMarginCard extends StatelessWidget {
  const _ScoreMarginCard({required this.distribution});

  final Map<int, int> distribution;

  static const _chartHeight = 190.0;
  static const _valueLabelSpace = 18.0;
  static const _yAxisWidth = 26.0;

  // En dessous de cette largeur, une colonne devient illisible : le graphique
  // défile alors horizontalement plutôt que de regrouper des écarts.
  static const _minColumnWidth = 20.0;

  /// Une colonne par écart, de la plus large défaite à la plus large
  /// victoire réellement observées, en passant toujours par le nul.
  static List<_MarginBucket> bucketsFor(Map<int, int> distribution) {
    final observed = [
      for (final entry in distribution.entries)
        if (entry.value > 0) entry.key,
    ];
    final lowest = observed.fold<int>(0, math.min);
    final highest = observed.fold<int>(0, math.max);

    return [
      for (var margin = lowest; margin <= highest; margin++)
        _MarginBucket(
          '${margin.abs()}',
          distribution[margin] ?? 0,
          margin < 0
              ? _teamRed
              : margin == 0
                  ? _teamYellow
                  : _teamGreen,
        ),
    ];
  }

  /// Pas de graduation « rond » (1, 2, 5, 10, 20…) pour environ 4 lignes.
  static int tickStepFor(int maxCount) {
    final raw = math.max(1, maxCount) / 4;
    var magnitude = 1;
    while (true) {
      for (final factor in const [1, 2, 5]) {
        if (factor * magnitude >= raw) return factor * magnitude;
      }
      magnitude *= 10;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = bucketsFor(distribution);
    final maxCount = buckets.fold<int>(
      0,
      (maximum, bucket) => math.max(maximum, bucket.count),
    );
    final step = tickStepFor(maxCount);
    final yMax = math.max(step, (maxCount / step).ceil() * step);
    final ticks = [for (var tick = 0; tick <= yMax; tick += step) tick];
    final axisColor = theme.colorScheme.onSurfaceVariant;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: axisColor,
      fontWeight: FontWeight.w400,
    );

    double tickY(int tick) =>
        _valueLabelSpace +
        (1 - tick / yMax) * (_chartHeight - _valueLabelSpace);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [
                _MarginLegend(label: 'Défaites', color: _teamRed),
                _MarginLegend(label: 'Nuls', color: _teamYellow),
                _MarginLegend(label: 'Victoires', color: _teamGreen),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _yAxisWidth,
                  height: _chartHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final tick in ticks)
                        Positioned(
                          top: tickY(tick) - 8,
                          left: 0,
                          right: 6,
                          height: 16,
                          child: Text(
                            '$tick',
                            textAlign: TextAlign.right,
                            style: axisStyle,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final neededWidth = buckets.length * _minColumnWidth;
                      final scrolls = neededWidth > constraints.maxWidth;
                      final plot = SizedBox(
                        width: scrolls ? neededWidth : constraints.maxWidth,
                        child: Column(
                          children: [
                            SizedBox(
                              height: _chartHeight,
                              child: CustomPaint(
                                painter: _MarginGridPainter(
                                  lineYs: [
                                    for (final tick in ticks) tickY(tick),
                                  ],
                                  color: axisColor.withValues(alpha: .18),
                                  baselineColor:
                                      axisColor.withValues(alpha: .45),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final bucket in buckets)
                                      Expanded(
                                        child: _MarginBar(
                                          bucket: bucket,
                                          barMaxHeight:
                                              _chartHeight - _valueLabelSpace,
                                          yMax: yMax,
                                          valueStyle: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                for (final bucket in buckets)
                                  Expanded(
                                    child: SizedBox(
                                      height: 18,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          bucket.label,
                                          maxLines: 1,
                                          textAlign: TextAlign.center,
                                          style: axisStyle?.copyWith(
                                            color: bucket.color,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );

                      if (!scrolls) return plot;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: plot,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: _yAxisWidth),
              child: Text(
                'Écart de buts',
                textAlign: TextAlign.center,
                style: axisStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarginBucket {
  const _MarginBucket(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;
}

class _MarginLegend extends StatelessWidget {
  const _MarginLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _MarginBar extends StatelessWidget {
  const _MarginBar({
    required this.bucket,
    required this.barMaxHeight,
    required this.yMax,
    required this.valueStyle,
  });

  final _MarginBucket bucket;
  final double barMaxHeight;
  final int yMax;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = math.min(28.0, constraints.maxWidth * .62);

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (bucket.count > 0)
              SizedBox(
                height: 16,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${bucket.count}', style: valueStyle),
                ),
              ),
            const SizedBox(height: 2),
            Container(
              width: barWidth,
              height: bucket.count / yMax * barMaxHeight,
              decoration: BoxDecoration(
                color: bucket.color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MarginGridPainter extends CustomPainter {
  const _MarginGridPainter({
    required this.lineYs,
    required this.color,
    required this.baselineColor,
  });

  final List<double> lineYs;
  final Color color;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < lineYs.length; index++) {
      final y = lineYs[index];
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = index == 0 ? baselineColor : color
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_MarginGridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.baselineColor != baselineColor ||
      !_sameLines(oldDelegate.lineYs, lineYs);

  static bool _sameLines(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

class _TeamStreaksSection extends StatelessWidget {
  const _TeamStreaksSection({required this.statistics});

  final TeamStatistics statistics;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.compactCardPadding),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _StreakTile(
                      streak: statistics.bestWinStreak,
                      label: 'victoires d’affilée',
                      color: _teamGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StreakTile(
                      streak: statistics.bestUnbeatenStreak,
                      label: 'matchs sans défaite',
                      color: _teamGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _StreakTile(
                      streak: statistics.worstLossStreak,
                      label: 'défaites d’affilée',
                      color: _teamRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StreakTile(
                      streak: statistics.worstWinlessStreak,
                      label: 'matchs sans victoire',
                      color: _teamRed,
                    ),
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

/// Un record de série : sa longueur, ce qu'elle mesure et quand elle a eu lieu.
class _StreakTile extends StatelessWidget {
  const _StreakTile({
    required this.streak,
    required this.label,
    required this.color,
  });

  final TeamStreak streak;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${streak.length}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          if (streak.hasDates) ...[
            Text('du ${_formatDate(streak.startDate!)}', style: muted),
            Text('au ${_formatDate(streak.endDate!)}', style: muted),
          ] else
            Text('Aucune série', style: muted),
        ],
      ),
    );
  }
}

String _formatDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;

  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
}

class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({
    required this.message,
    required this.onRefresh,
  });

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sectionGap,
          AppSpacing.screenGutter,
          32,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
