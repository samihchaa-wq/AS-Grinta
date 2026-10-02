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
            const _TeamSectionTitle('Résultats'),
            const SizedBox(height: 10),
            _TeamResultsCard(statistics: statistics),
            const SizedBox(height: AppSpacing.sectionGap),
            const _TeamSectionTitle('Buts marqués'),
            const SizedBox(height: 10),
            _TeamGoalsCard(statistics: statistics),
            if (period == StatisticsPeriod.current &&
                statistics.recentResults.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sectionGap),
              const _TeamSectionTitle('Derniers matchs'),
              const SizedBox(height: 10),
              _RecentResultsCard(results: statistics.recentResults),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
            const _TeamSectionTitle('Score moyen'),
            const SizedBox(height: 10),
            _AverageScoreCard(statistics: statistics),
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
  const _TeamResultsCard({required this.statistics});

  final TeamStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.cardPadding,
          22,
          AppSpacing.cardPadding,
          20,
        ),
        child: Column(
          children: [
            Text(
              '${statistics.matchesPlayed}',
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              'match${statistics.matchesPlayed > 1 ? 's' : ''} joué${statistics.matchesPlayed > 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 16.0;
                final ringSize = math.min(
                  96.0,
                  math.max(
                    0.0,
                    (constraints.maxWidth - gap * 2) / 3,
                  ),
                );

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: ringSize,
                      child: _ResultRing(
                        value: statistics.wins,
                        total: statistics.matchesPlayed,
                        label: 'victoires',
                        color: _teamGreen,
                      ),
                    ),
                    const SizedBox(width: gap),
                    SizedBox.square(
                      dimension: ringSize,
                      child: _ResultRing(
                        value: statistics.draws,
                        total: statistics.matchesPlayed,
                        label: 'nuls',
                        color: _teamYellow,
                      ),
                    ),
                    const SizedBox(width: gap),
                    SizedBox.square(
                      dimension: ringSize,
                      child: _ResultRing(
                        value: statistics.losses,
                        total: statistics.matchesPlayed,
                        label: 'défaites',
                        color: _teamRed,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRing extends StatelessWidget {
  const _ResultRing({
    required this.value,
    required this.total,
    required this.label,
    required this.color,
  });

  final int value;
  final int total;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = total == 0 ? 0.0 : value / total;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final strokeWidth = side < 76 ? 7.0 : 9.0;
        final valueFontSize = side < 76 ? 18.0 : 22.0;
        final labelFontSize = side < 76 ? 10.0 : 12.0;

        return AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GrintaProgressIndicator(
                value: progress,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.butt,
                color: color,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: .12),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.all(side * .18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$value',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: valueFontSize,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 1),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: labelFontSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TeamGoalsCard extends StatelessWidget {
  const _TeamGoalsCard({required this.statistics});

  final TeamStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalGoals = statistics.goalsFor + statistics.goalsAgainst;
    final scoredRatio = totalGoals == 0 ? .5 : statistics.goalsFor / totalGoals;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.compactCardPadding,
          vertical: 24,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final donutSize = math.min(88.0, constraints.maxWidth * .27);

            return Row(
              children: [
                Expanded(
                  child: _GoalValue(
                    value: statistics.goalsFor,
                    label: 'buts marqués',
                    color: _teamGreen,
                  ),
                ),
                SizedBox.square(
                  dimension: donutSize,
                  child: CustomPaint(
                    painter: _GoalsDonutPainter(
                      scoredRatio: scoredRatio,
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: .1),
                    ),
                  ),
                ),
                Expanded(
                  child: _GoalValue(
                    value: statistics.goalsAgainst,
                    label: 'buts encaissés',
                    color: _teamRed,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GoalValue extends StatelessWidget {
  const _GoalValue({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.microGap),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$value',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsDonutPainter extends CustomPainter {
  const _GoalsDonutPainter({
    required this.scoredRatio,
    required this.backgroundColor,
  });

  final double scoredRatio;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.min(size.width, size.height) * .22;
    final side = math.min(size.width, size.height);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    final arcRect =
        Rect.fromLTWH(left, top, side, side).deflate(strokeWidth / 2);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = backgroundColor;
    final scoredPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = _teamGreen;
    final concededPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = _teamRed;

    canvas.drawArc(arcRect, 0, math.pi * 2, false, basePaint);
    const start = -math.pi / 2;
    final scoredSweep = math.pi * 2 * scoredRatio.clamp(0.0, 1.0).toDouble();
    canvas.drawArc(arcRect, start, scoredSweep, false, scoredPaint);
    canvas.drawArc(
      arcRect,
      start + scoredSweep,
      math.pi * 2 - scoredSweep,
      false,
      concededPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoalsDonutPainter oldDelegate) {
    return oldDelegate.scoredRatio != scoredRatio ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _RecentResultsCard extends StatelessWidget {
  const _RecentResultsCard({required this.results});

  final List<String> results;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.compactCardPadding,
          vertical: 20,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppSpacing.contentGap;
            final count = results.length;
            final bubbleSize = count == 0
                ? 0.0
                : math.min(
                    48.0,
                    math.max(
                      0.0,
                      (constraints.maxWidth - gap * (count - 1)) / count,
                    ),
                  );

            return Wrap(
              alignment: WrapAlignment.start,
              runAlignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final result in results)
                  _ResultBubble(
                    result: result,
                    dimension: bubbleSize,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResultBubble extends StatelessWidget {
  const _ResultBubble({
    required this.result,
    required this.dimension,
  });

  final String result;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'V' => _teamGreen,
      'N' => _teamYellow,
      _ => _teamRed,
    };

    return SizedBox.square(
      dimension: dimension,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              result,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w400,
                fontSize: dimension * .46,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AverageScoreCard extends StatelessWidget {
  const _AverageScoreCard({required this.statistics});

  final TeamStatistics statistics;

  String _average(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 22,
        ),
        child: Row(
          children: [
            Expanded(
              child: _AverageValue(
                label: 'Moy. buts marqués',
                value: _average(statistics.goalsForPerMatch),
                color: _teamGreen,
              ),
            ),
            Container(
              width: 1,
              height: 58,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .12),
            ),
            Expanded(
              child: _AverageValue(
                label: 'Moy. buts encaissés',
                value: _average(statistics.goalsAgainstPerMatch),
                color: _teamRed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AverageValue extends StatelessWidget {
  const _AverageValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w400,
              ),
        ),
        const SizedBox(height: AppSpacing.microGap),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w400,
              ),
        ),
      ],
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
    final periodMaximum = [
      statistics.bestWinStreak.length,
      statistics.bestUnbeatenStreak.length,
      statistics.worstLossStreak.length,
      statistics.worstWinlessStreak.length,
    ].fold<int>(
      1,
      (maximum, value) => math.max(maximum, value),
    );
    final scale = statistics.period == StatisticsPeriod.allTime
        ? math.max(1, statistics.matchesPlayed)
        : periodMaximum;

    return Column(
      children: [
        _StreakGroupCard(
          title: 'Meilleures séries',
          children: [
            _StreakRow(
              title: 'Meilleure série de victoires',
              streak: statistics.bestWinStreak,
              color: _teamGreen,
              scale: scale,
            ),
            const SizedBox(height: 20),
            _StreakRow(
              title: 'Meilleure série de matchs sans défaite',
              streak: statistics.bestUnbeatenStreak,
              color: _teamGreen,
              scale: scale,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _StreakGroupCard(
          title: 'Pires séries',
          children: [
            _StreakRow(
              title: 'Pire série de défaites',
              streak: statistics.worstLossStreak,
              color: _teamRed,
              scale: scale,
            ),
            const SizedBox(height: 20),
            _StreakRow(
              title: 'Pire série de matchs sans victoire',
              streak: statistics.worstWinlessStreak,
              color: _teamRed,
              scale: scale,
            ),
          ],
        ),
      ],
    );
  }
}

class _StreakGroupCard extends StatelessWidget {
  const _StreakGroupCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.cardPadding,
          18,
          AppSpacing.cardPadding,
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({
    required this.title,
    required this.streak,
    required this.color,
    required this.scale,
  });

  final String title;
  final TeamStreak streak;
  final Color color;
  final int scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = scale == 0 ? 0.0 : streak.length / scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GrintaLinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 10,
                borderRadius: BorderRadius.circular(99),
                color: color,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: .13),
              ),
            ),
            const SizedBox(width: AppSpacing.sectionGap),
            Text(
              '${streak.length} / $scale',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          streak.hasDates
              ? 'Du ${_formatDate(streak.startDate!)} au ${_formatDate(streak.endDate!)}'
              : 'Aucune série enregistrée',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
