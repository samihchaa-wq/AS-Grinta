import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
import 'package:flutter/material.dart';

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
    final accent = gaugeAccentFor(gauge.playerId);
    final activityIcon = gauge.isGoalkeeper
        ? Icons.sports_handball_outlined
        : Icons.sports_soccer;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF09152B),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF2B315D)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B6FFF).withValues(alpha: .10),
            blurRadius: 26,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 460;
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PlayerIdentity(
                            name: gauge.playerName,
                            accent: accent,
                            icon: activityIcon,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: gauge.isGoalkeeper
                                      ? 'Clean sheets'
                                      : 'Buts actuels',
                                  value: gauge.actual.toString(),
                                  color: accent,
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: 'Ton prono',
                                  value: personalPrediction?.toString() ?? '—',
                                  color: const Color(0xFFFF9F2D),
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: 'Médiane',
                                  value: median?.toString() ?? '—',
                                  color: const Color(0xFF9B35FF),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: _PlayerIdentity(
                            name: gauge.playerName,
                            accent: accent,
                            icon: activityIcon,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _Metric(
                            label: gauge.isGoalkeeper
                                ? 'Clean sheets'
                                : 'Buts actuels',
                            value: gauge.actual.toString(),
                            color: accent,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _Metric(
                            label: 'Ton prono',
                            value: personalPrediction?.toString() ?? '—',
                            color: const Color(0xFFFF9F2D),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _Metric(
                            label: 'Médiane',
                            value: median?.toString() ?? '—',
                            color: const Color(0xFF9B35FF),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: .12),
                        border: Border.all(
                          color: accent.withValues(alpha: .42),
                        ),
                      ),
                      child: Icon(activityIcon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PremiumGaugeLine(
                        actual: gauge.actual,
                        fallbackMax: scaleMax,
                        median: median?.toDouble(),
                        personalPrediction: personalPrediction,
                        accent: accent,
                        onMedianTap: onTap,
                      ),
                    ),
                  ],
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
    required this.accent,
    required this.icon,
  });

  final String name;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: .10),
            border: Border.all(color: accent.withValues(alpha: .35)),
          ),
          child: Icon(icon, color: accent, size: 32),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
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
        border: Border(left: BorderSide(color: Color(0xFF222B50))),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
