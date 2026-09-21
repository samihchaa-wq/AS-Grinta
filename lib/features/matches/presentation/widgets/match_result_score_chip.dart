import 'package:flutter/material.dart';

/// Affiche un score entouré en vert, orange ou rouge selon le résultat
/// d’AS Grinta.
class MatchResultScoreChip extends StatelessWidget {
  const MatchResultScoreChip({
    super.key,
    required this.scoreGrinta,
    required this.scoreOpponent,
    this.textStyle,
    this.subtitle,
    this.onTap,
    this.semanticLabel,
  });

  final int scoreGrinta;
  final int scoreOpponent;
  final TextStyle? textStyle;
  final String? subtitle;
  final VoidCallback? onTap;
  final String? semanticLabel;

  Color get _color {
    if (scoreGrinta > scoreOpponent) return const Color(0xFF39E784);
    if (scoreGrinta == scoreOpponent) return const Color(0xFFFFB43D);
    return const Color(0xFFFF5F6D);
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final chip = Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$scoreGrinta–$scoreOpponent',
            style:
                (textStyle ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
              color: color,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              style: TextStyle(
                color: color.withValues(alpha: .82),
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: chip,
      ),
    );
  }
}
