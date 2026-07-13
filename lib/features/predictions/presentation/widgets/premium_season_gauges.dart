import 'dart:math' as math;

import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';

const _green = Color(0xFF39E784);
const _personalPrediction = Color(0xFFFFBE3D);
const _medianPrediction = Color(0xFF9B6CFF);

Color gaugeAccentFor(String key) {
  return const Color(0xFF4B6FFF);
}

class PremiumSeasonGaugeCard extends StatelessWidget {
  const PremiumSeasonGaugeCard({
    super.key,
    required this.gauge,
    required this.scaleMax,
    required this.onOpenAll,
    required this.onOpenMedian,
    this.personalPrediction,
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenMedian;
  final int? personalPrediction;

  @override
  Widget build(BuildContext context) {
    final accent = gaugeAccentFor(gauge.playerId);
    final roundedMedian =
        gauge.predictions.isEmpty ? null : gauge.median.roundToDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF08162C),
        border: Border.all(color: accent.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .12),
            blurRadius: 26,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenAll,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gauge.playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.3,
                      ),
                ),
                const SizedBox(height: 12),
                PremiumGaugeLine(
                  actual: gauge.actual,
                  fallbackMax: scaleMax,
                  median: roundedMedian,
                  personalPrediction: personalPrediction,
                  accent: accent,
                  onMedianTap: roundedMedian == null ? null : onOpenMedian,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumGaugeLine extends StatelessWidget {
  const PremiumGaugeLine({
    super.key,
    required this.actual,
    required this.fallbackMax,
    required this.median,
    required this.personalPrediction,
    required this.accent,
    required this.onMedianTap,
  });

  final int actual;
  final int fallbackMax;
  final double? median;
  final int? personalPrediction;
  final Color accent;
  final VoidCallback? onMedianTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const markerRadius = 16.0;
        final usable = math.max(1.0, constraints.maxWidth - markerRadius * 2);
        final roundedMedian = median?.roundToDouble();
        final largestMarker = math.max(
          actual.toDouble(),
          math.max(
            roundedMedian ?? 0,
            personalPrediction?.toDouble() ?? 0,
          ),
        );
        final visualMax = math.max(
          math.max(1.0, fallbackMax.toDouble()),
          largestMarker * 1.15,
        );

        double xFor(num value) {
          if (roundedMedian == null) {
            final ratio = (value / visualMax).clamp(0.0, 1.0);
            return markerRadius + usable * ratio;
          }

          const centerRatio = .5;
          final numericValue = value.toDouble();
          final medianValue = roundedMedian;
          if (numericValue <= medianValue) {
            final leftRatio = medianValue <= 0
                ? centerRatio
                : (numericValue / medianValue).clamp(0.0, 1.0) * centerRatio;
            return markerRadius + usable * leftRatio;
          }

          final rightMax = math.max(
            medianValue + 1,
            math.max(visualMax, largestMarker),
          );
          final rightRatio =
              ((numericValue - medianValue) / (rightMax - medianValue))
                  .clamp(0.0, 1.0);
          return markerRadius + usable * (centerRatio + rightRatio * .5);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: markerRadius,
                    right: markerRadius,
                    top: 20,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(
                          colors: [accent.withValues(alpha: .72), accent],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: .3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (roundedMedian != null)
                    Positioned(
                      left: xFor(roundedMedian) - 1,
                      top: 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onMedianTap,
                        child: SizedBox(
                          width: 2,
                          height: 39,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _medianPrediction,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      _medianPrediction.withValues(alpha: .55),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (personalPrediction != null)
                    Positioned(
                      left: xFor(personalPrediction!) - 6,
                      top: 16,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _personalPrediction,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _personalPrediction.withValues(alpha: .65),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: xFor(actual) - 6,
                    top: 16,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: .65),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _GaugeValueLabel(
                    icon: Icons.circle,
                    label: 'Actuel',
                    value: '$actual',
                    color: accent,
                    alignment: CrossAxisAlignment.start,
                  ),
                ),
                Expanded(
                  child: _GaugeValueLabel(
                    icon: Icons.circle,
                    label: 'Ton prono',
                    value: personalPrediction?.toString() ?? '—',
                    color: _personalPrediction,
                    alignment: CrossAxisAlignment.center,
                  ),
                ),
                Expanded(
                  child: _GaugeValueLabel(
                    icon: Icons.circle,
                    label: 'Médiane',
                    value: roundedMedian?.round().toString() ?? '—',
                    color: _medianPrediction,
                    alignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _GaugeValueLabel extends StatelessWidget {
  const _GaugeValueLabel({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.alignment,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class PremiumPlayerDetailsSheet extends StatefulWidget {
  const PremiumPlayerDetailsSheet({
    super.key,
    required this.gauge,
    required this.currentUserId,
    required this.scrollController,
  });

  final PlayerGauge gauge;
  final String? currentUserId;
  final ScrollController scrollController;

  @override
  State<PremiumPlayerDetailsSheet> createState() =>
      _PremiumPlayerDetailsSheetState();
}

class _PremiumPlayerDetailsSheetState extends State<PremiumPlayerDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final gauge = widget.gauge;
    final accent = gaugeAccentFor(gauge.playerId);
    final predictions = [...gauge.predictions]..sort((a, b) {
        final aDistance = (a.value - gauge.actual).abs();
        final bDistance = (b.value - gauge.actual).abs();
        final byDistance = aDistance.compareTo(bDistance);
        if (byDistance != 0) return byDistance;

        final byValue = a.value.compareTo(b.value);
        if (byValue != 0) return byValue;

        return a.predictorName.toLowerCase().compareTo(
              b.predictorName.toLowerCase(),
            );
      });

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF061226),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gauge.playerName,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      gauge.isGoalkeeper
                          ? AppFormats.counted(
                              gauge.actual,
                              'clean sheet actuel',
                              'clean sheets actuels',
                            )
                          : AppFormats.counted(
                              gauge.actual,
                              'but actuel',
                              'buts actuels',
                            ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Tous les pronostics (${predictions.length})',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1932),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withValues(alpha: .22)),
            ),
            child: Column(
              children: [
                for (var index = 0; index < predictions.length; index++)
                  _PredictionRow(
                    prediction: predictions[index],
                    rank: _rankFor(
                      predictions,
                      index,
                      gauge.actual,
                    ),
                    maxValue: math.max(1, gauge.maximum),
                    isMine:
                        predictions[index].predictorId == widget.currentUserId,
                    accent: accent,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _rankFor(
    List<GaugePrediction> predictions,
    int index,
    int actual,
  ) {
    if (index == 0) return 1;

    final currentDistance = (predictions[index].value - actual).abs();
    final previousDistance = (predictions[index - 1].value - actual).abs();
    if (currentDistance == previousDistance) {
      return _rankFor(predictions, index - 1, actual);
    }
    return index + 1;
  }
}

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({
    required this.prediction,
    required this.rank,
    required this.maxValue,
    required this.isMine,
    required this.accent,
  });

  final GaugePrediction prediction;
  final int rank;
  final int maxValue;
  final bool isMine;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = (prediction.value / maxValue).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? _green.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border:
            isMine ? Border.all(color: _green.withValues(alpha: .18)) : null,
      ),
      child: Row(
        children: [
          SizedBox(width: 34, child: _RankBadge(rank: rank)),
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withValues(alpha: .18),
            child: Text(
              prediction.predictorName.trim().isEmpty
                  ? '?'
                  : prediction.predictorName.trim()[0].toUpperCase(),
              style: TextStyle(
                color: isMine ? _green : Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              isMine
                  ? '${prediction.predictorName} (moi)'
                  : prediction.predictorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMine ? _green : Colors.white,
                fontWeight: isMine ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: .06),
                color: isMine ? _green : accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text(
              '${prediction.value}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isMine ? _green : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => const Color(0xFFFFC43D),
      2 => const Color(0xFFD7E0EE),
      3 => const Color(0xFFFF925D),
      _ => Colors.transparent,
    };
    if (rank > 3) {
      return Text(
        '$rank',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60),
      );
    }
    return CircleAvatar(
      radius: 13,
      backgroundColor: color,
      child: Text(
        '$rank',
        style: const TextStyle(
          color: Color(0xFF071326),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
