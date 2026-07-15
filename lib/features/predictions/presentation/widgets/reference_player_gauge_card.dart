import 'dart:math' as math;

import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';

const _actualBlue = Color(0xFF397CFF);
const _personalOrange = Color(0xFFFF9D2E);
const _medianPurple = Color(0xFFA33CFF);

class ReferencePlayerGaugeCard extends StatelessWidget {
  const ReferencePlayerGaugeCard({
    super.key,
    required this.gauge,
    required this.scaleMax,
    required this.personalPrediction,
    required this.onTap,
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final int? personalPrediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final median = gauge.predictions.isEmpty ? null : gauge.median.round();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF080D21),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF25284C)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B43FF).withValues(alpha: .10),
            blurRadius: 28,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _PlayerIdentity(
                        name: gauge.playerName,
                        isGoalkeeper: gauge.isGoalkeeper,
                      ),
                    ),
                    Expanded(
                      flex: 7,
                      child: Row(
                        children: [
                          Expanded(
                            child: _Metric(
                              label: gauge.isGoalkeeper
                                  ? 'Clean sheets :'
                                  : 'Buts actuel :',
                              value: gauge.actual.toString(),
                              color: _actualBlue,
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              label: 'Ton prono :',
                              value: personalPrediction?.toString() ?? '—',
                              color: _personalOrange,
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              label: 'Médiane :',
                              value: median?.toString() ?? '—',
                              color: _medianPurple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _ReferenceGaugeLine(
                  actual: gauge.actual,
                  median: median,
                  personalPrediction: personalPrediction,
                  scaleMax: scaleMax,
                  isGoalkeeper: gauge.isGoalkeeper,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerIdentity extends StatelessWidget {
  const _PlayerIdentity({
    required this.name,
    required this.isGoalkeeper,
  });

  final String name;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF11172D),
            border: Border.all(color: _medianPurple.withValues(alpha: .42)),
            boxShadow: [
              BoxShadow(
                color: _medianPurple.withValues(alpha: .15),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(
            isGoalkeeper
                ? Icons.sports_handball_outlined
                : Icons.sports_soccer,
            color: _medianPurple,
            size: 30,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF252947))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceGaugeLine extends StatelessWidget {
  const _ReferenceGaugeLine({
    required this.actual,
    required this.median,
    required this.personalPrediction,
    required this.scaleMax,
    required this.isGoalkeeper,
  });

  final int actual;
  final int? median;
  final int? personalPrediction;
  final int scaleMax;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const edge = 22.0;
        final largest = math.max(
          actual.toDouble(),
          math.max(
            median?.toDouble() ?? 0,
            personalPrediction?.toDouble() ?? 0,
          ),
        );
        final visualMax = math.max(
          1.0,
          math.max(scaleMax.toDouble(), largest * 1.10),
        );
        final usable = math.max(1.0, constraints.maxWidth - edge * 2);

        double xFor(num value) {
          final ratio = (value.toDouble() / visualMax).clamp(0.0, 1.0);
          return edge + usable * ratio;
        }

        final actualX = xFor(actual);

        return SizedBox(
          height: 78,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: edge,
                right: edge,
                top: 32,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A47),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFF3B4060)),
                  ),
                ),
              ),
              Positioned(
                left: edge,
                top: 32,
                width: math.max(8, actualX - edge),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(
                      colors: [_actualBlue, Color(0xFF702EFF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6338FF).withValues(alpha: .55),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
              for (var index = 1; index < 12; index++)
                Positioned(
                  left: edge + usable * index / 12,
                  top: 36,
                  child: Container(
                    width: 1.5,
                    height: 7,
                    color: Colors.white.withValues(alpha: .18),
                  ),
                ),
              if (personalPrediction != null)
                _VerticalMarker(
                  x: xFor(personalPrediction!),
                  color: _personalOrange,
                ),
              if (median != null)
                _VerticalMarker(
                  x: xFor(median!),
                  color: _medianPurple,
                ),
              Positioned(
                left: actualX - 24,
                top: 10,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF7F7FB),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _medianPurple.withValues(alpha: .78),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Text(
                    isGoalkeeper ? '🧤' : '⚽',
                    style: const TextStyle(fontSize: 29, height: 1),
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

class _VerticalMarker extends StatelessWidget {
  const _VerticalMarker({required this.x, required this.color});

  final double x;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - 6,
      top: 2,
      child: SizedBox(
        width: 12,
        height: 70,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 0,
              bottom: 8,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .65),
                      blurRadius: 9,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .65),
                    blurRadius: 9,
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
