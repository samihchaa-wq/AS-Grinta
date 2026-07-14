import 'package:flutter/material.dart';

/// Affiche un score entouré en vert, orange ou rouge selon le résultat
/// d’AS Grinta.
class MatchResultScoreChip extends StatelessWidget {
  const MatchResultScoreChip({
    super.key,
    required this.scoreGrinta,
    required this.scoreOpponent,
    this.textStyle,
  });

  final int scoreGrinta;
  final int scoreOpponent;
  final TextStyle? textStyle;

  Color get _color {
    if (scoreGrinta > scoreOpponent) return const Color(0xFF39E784);
    if (scoreGrinta == scoreOpponent) return const Color(0xFFFFB43D);
    return const Color(0xFFFF5F6D);
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.7),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .18),
            blurRadius: 10,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Text(
        '$scoreGrinta–$scoreOpponent',
        style: (textStyle ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
