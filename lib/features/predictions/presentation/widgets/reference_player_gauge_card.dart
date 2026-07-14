import 'dart:math' as math;

import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
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
    final activityIcon = gauge.isGoalkeeper
        ? Icons.sports_handball_outlined
        : Icons.sports_soccer;

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
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final identity = _PlayerIdentity(
                  name: gauge.playerName,
                  icon: activityIcon,
                );
                final metrics = Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: gauge.isGoalkeeper
                            ? 'Clean sheets actuels'
                            : 'Buts actuels',
                        value: gauge.actual.toString(),
                        color: _actualBlue,
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Ton prono',
                        value: personalPrediction?.toString() ?? '—',
                        color: _personalOrange,
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Médiane',
                        value: median?.toString() ?? '—',
                        color: _medianPurple,
                      ),
                    ),
                  ],
                );

                return Column(
                  children: [
                    if (compact) ...[
                      identity,
                      const SizedBox(height: 20),
                      metrics,
                    ] else
                      Row(
                        children: [
                          Expanded(flex: 4, child: identity),
                          Expanded(flex: 6, child: metrics),
                        ],
                      ),
                    const SizedBox(height: 30),
                    _ReferenceGaugeLine(
                      actual: gauge.actual,
                      median: median,
                      personalPrediction: personalPrediction,
                      scaleMax: scaleMax,
                      activityIcon: activityIcon,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerIdentity extends StatelessWidget {
  const _PlayerIdentity({required this.name, required this.icon});

  final String name;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF11172D),
            border: Border.all(color: _medianPurple.withValues(alpha: .38)),
            boxShadow: [
              BoxShadow(
                color: _medianPurple.withValues(alpha: .12),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(icon, color: _medianPurple, size: 36),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF252947))),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 34,
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
    required this.activityIcon,
  });

  final int actual;
  final int? median;
  final int? personalPrediction;
  final int scaleMax;
  final IconData activityIcon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const edge = 24.0;
        final largest = math.max(
          actual.toDouble(),
          math.max(
            median?.toDouble() ?? 0,
            personalPrediction?.toDouble() ?? 0,
          ),
        );
        final visualMax = math.max(
          1.0,
          math.max(scaleMax.toDouble(), largest * 1.12),
        );
        final usable = math.max(1.0, constraints.maxWidth - edge * 2);

        double xFor(num value) {
          final ratio = (value.toDouble() / visualMax).clamp(0.0, 1.0);
          return edge + usable * ratio;
        }

        final actualX = xFor(actual);

        return SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: edge,
                right: edge,
                top: 31,
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
                top: 31,
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
                  top: 35,
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
                left: actualX - 25,
                top: 11,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF5F5FA),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _medianPurple.withValues(alpha: .75),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(
                    activityIcon,
                    color: const Color(0xFF15172B),
                    size: 31,
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
                    BoxShadow(color: color.withValues(alpha: .65), blurRadius: 9),
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
                  BoxShadow(color: color.withValues(alpha: .65), blurRadius: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
