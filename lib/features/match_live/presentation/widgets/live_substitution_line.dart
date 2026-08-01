import 'package:flutter/material.dart';

/// Un remplacement, écrit avec des flèches plutôt qu'avec « entre / sort » :
/// flèche verte vers le haut pour l'entrant, flèche rouge vers le bas pour
/// le sortant. Se lit d'un coup d'œil au bord du terrain.
class LiveSubstitutionLine extends StatelessWidget {
  const LiveSubstitutionLine({
    super.key,
    required this.playerInName,
    required this.playerOutName,
    this.trailingText,
  });

  final String playerInName;
  final String playerOutName;

  /// Complément affiché à la suite, typiquement la minute (« 45' »).
  final String? trailingText;

  static const _inColor = Color(0xFF27AE60);
  static const _outColor = Color(0xFFE74C3C);

  /// Version texte, pour les dialogues de confirmation et l'accessibilité.
  static String describe({
    required String playerInName,
    required String playerOutName,
    String? trailingText,
  }) {
    final suffix = trailingText == null ? '' : ' · $trailingText';
    return '$playerInName entre, $playerOutName sort$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return Semantics(
      label: describe(
        playerInName: playerInName,
        playerOutName: playerOutName,
        trailingText: trailingText,
      ),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Side(
              icon: Icons.arrow_upward_rounded,
              color: _inColor,
              name: playerInName,
              style: style,
            ),
            _Side(
              icon: Icons.arrow_downward_rounded,
              color: _outColor,
              name: playerOutName,
              style: style,
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: style.copyWith(color: style.color?.withValues(alpha: .7)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.icon,
    required this.color,
    required this.name,
    required this.style,
  });

  final IconData icon;
  final Color color;
  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 2),
        Text(name, style: style),
      ],
    );
  }
}
