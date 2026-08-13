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
            if (statistics.recentResults.isNotEmpty) ...[
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
                'Répartition des matchs selon le score final',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
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
            fontWeight: FontWeight.w900,
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
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'match${statistics.matchesPlayed > 1 ? 's' : ''} joué${statistics.matchesPlayed > 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
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
                          fontWeight: FontWeight.w900,
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
                  fontWeight: FontWeight.w900,
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
              fontWeight: FontWeight.w700,
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
              alignment: WrapAlignment.spaceBetween,
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
                fontWeight: FontWeight.w900,
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
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: AppSpacing.microGap),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _ScoreMarginCard extends StatelessWidget {
  const _ScoreMarginCard({required this.distribution});

  final Map<int, int> distribution;

  int _sumWhere(bool Function(int margin) test) {
    return distribution.entries.fold<int>(
      0,
      (total, entry) => test(entry.key) ? total + entry.value : total,
    );
  }

  @override
  Widget build(BuildContext context) {
    final losses = _sumWhere((margin) => margin < 0);
    final draws = distribution[0] ?? 0;
    final wins = _sumWhere((margin) => margin > 0);
    final buckets = [
      _MarginBucket('≤-4', _sumWhere((margin) => margin <= -4), _teamRed),
      _MarginBucket('-3', distribution[-3] ?? 0, _teamRed),
      _MarginBucket('-2', distribution[-2] ?? 0, _teamRed),
      _MarginBucket('-1', distribution[-1] ?? 0, _teamRed),
      _MarginBucket('0', draws, _teamYellow),
      _MarginBucket('+1', distribution[1] ?? 0, _teamGreen),
      _MarginBucket('+2', distribution[2] ?? 0, _teamGreen),
      _MarginBucket('+3', distribution[3] ?? 0, _teamGreen),
      _MarginBucket('≥+4', _sumWhere((margin) => margin >= 4), _teamGreen),
    ];
    final maxCount = math.max(
      1,
      buckets.fold<int>(
        0,
        (maximum, bucket) => math.max(maximum, bucket.count),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: [
            _MarginSummaryRow(
              losses: losses,
              draws: draws,
              wins: wins,
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _MarginGroupLabel(
                    label: 'DÉFAITES',
                    color: _teamRed,
                  ),
                ),
                Expanded(
                  child: _MarginGroupLabel(
                    label: 'NUL',
                    color: _teamYellow,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: _MarginGroupLabel(
                    label: 'VICTOIRES',
                    color: _teamGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final bucket in buckets)
                    Expanded(
                      child: _MarginBar(
                        bucket: bucket,
                        maxCount: maxCount,
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

class _MarginBucket {
  const _MarginBucket(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;
}

class _MarginSummaryRow extends StatelessWidget {
  const _MarginSummaryRow({
    required this.losses,
    required this.draws,
    required this.wins,
  });

  final int losses;
  final int draws;
  final int wins;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MarginSummaryItem(
            label: 'Défaites',
            value: losses,
            color: _teamRed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MarginSummaryItem(
            label: 'Nuls',
            value: draws,
            color: _teamYellow,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MarginSummaryItem(
            label: 'Victoires',
            value: wins,
            color: _teamGreen,
          ),
        ),
      ],
    );
  }
}

class _MarginSummaryItem extends StatelessWidget {
  const _MarginSummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            maxLines: 1,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarginGroupLabel extends StatelessWidget {
  const _MarginGroupLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
          ),
    );
  }
}

class _MarginBar extends StatelessWidget {
  const _MarginBar({
    required this.bucket,
    required this.maxCount,
  });

  final _MarginBucket bucket;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heightFactor = bucket.count == 0 ? 0.0 : bucket.count / maxCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 20,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${bucket.count}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: heightFactor,
                child: Container(
                  width: 22,
                  decoration: BoxDecoration(
                    color: bucket.color,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                bucket.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
                    fontWeight: FontWeight.w900,
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
            fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w900,
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
