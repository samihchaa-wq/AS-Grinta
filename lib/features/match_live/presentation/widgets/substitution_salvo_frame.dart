import 'package:as_grinta/features/match_live/domain/substitution_salvos.dart';
import 'package:flutter/material.dart';

/// Douze couleurs bien distinctes, une par salve de remplacements. Au-delà de
/// douze salves, la série recommence.
const substitutionSalvoPalette = <Color>[
  Color(0xFF42A5F5), // bleu
  Color(0xFFFFA726), // orange
  Color(0xFFAB47BC), // violet
  Color(0xFF26A69A), // vert d'eau
  Color(0xFFEF5350), // rouge
  Color(0xFFD4E157), // citron vert
  Color(0xFFEC407A), // rose
  Color(0xFF8D6E63), // marron
  Color(0xFF5C6BC0), // indigo
  Color(0xFFFFEE58), // jaune
  Color(0xFF26C6DA), // cyan
  Color(0xFF9CCC65), // vert clair
];

Color substitutionSalvoColor(SubstitutionSalvo salvo) =>
    substitutionSalvoPalette[
        salvo.colorIndex % substitutionSalvoPalette.length];

/// Repère « mi-temps.salve » affiché à la place de l'icône de remplacement.
class SubstitutionSalvoBadge extends StatelessWidget {
  const SubstitutionSalvoBadge({super.key, required this.salvo});

  final SubstitutionSalvo salvo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Mi-temps ${salvo.half}, salve ${salvo.number}',
      child: ExcludeSemantics(
        child: Text(
          salvo.label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
        ),
      ),
    );
  }
}

/// Encadré coloré qui regroupe les remplacements d'une même salve.
class SubstitutionSalvoFrame extends StatelessWidget {
  const SubstitutionSalvoFrame({
    super.key,
    required this.salvo,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  final SubstitutionSalvo salvo;
  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final color = substitutionSalvoColor(salvo);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: child,
    );
  }
}
