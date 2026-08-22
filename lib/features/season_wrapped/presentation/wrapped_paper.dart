import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Direction artistique du bilan de saison : la feuille de match.
///
/// Papier crème, encre bleu-noir, tampon rouge. Deux familles seulement —
/// une machine à écrire pour ce qu'on lit, une condensée de stade pour ce
/// qu'on retient.
abstract final class WrappedPaper {
  static const Color paper = Color(0xFFEFE6D2);
  static const Color paperDeep = Color(0xFFE2D6BC);
  static const Color ink = Color(0xFF16212F);
  static const Color inkSoft = Color(0xFF5C6A78);
  static const Color rule = Color(0xFFC9BB9C);
  static const Color stamp = Color(0xFFB4322A);
  static const Color club = Color(0xFF1A4AC0);
  static const Color highlight = Color(0xFFF2D34A);

  static const String typewriter = 'Courier Prime';
  static const String stencil = 'Oswald';

  /// Intitulé de rubrique : petites capitales à la machine à écrire.
  static TextStyle label({double size = 12, Color color = inkSoft}) {
    return TextStyle(
      fontFamily: typewriter,
      fontSize: size,
      height: 1.3,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  /// Texte courant, toujours à la machine à écrire.
  static TextStyle body({double size = 14, Color color = ink}) {
    return TextStyle(
      fontFamily: typewriter,
      fontSize: size,
      height: 1.45,
      color: color,
    );
  }

  /// Le chiffre qu'on retient.
  static TextStyle figure({double size = 96, Color color = ink}) {
    return TextStyle(
      fontFamily: stencil,
      fontSize: size,
      height: .95,
      fontWeight: FontWeight.w700,
      color: color,
    );
  }

  /// Titre de rubrique.
  static TextStyle title({double size = 30, Color color = ink}) {
    return TextStyle(
      fontFamily: stencil,
      fontSize: size,
      height: 1.05,
      fontWeight: FontWeight.w500,
      letterSpacing: .4,
      color: color,
    );
  }
}

/// Le fond de chaque écran : papier réglé, grain et ombre de pliure.
///
/// Tout est peint plutôt qu'importé en image : le rendu reste net à toutes
/// les tailles d'écran et ne coûte aucun téléchargement.
class WrappedPaperBackground extends StatelessWidget {
  const WrappedPaperBackground({
    super.key,
    this.seed = 0,
    required this.child,
  });

  /// Deux écrans voisins ne doivent pas avoir exactement le même grain.
  final int seed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: WrappedPaper.paper),
      child: CustomPaint(
        painter: _PaperPainter(seed: seed),
        child: child,
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Réglure du formulaire : des lignes régulières, très pâles.
    final rulePaint = Paint()
      ..color = WrappedPaper.rule.withValues(alpha: .55)
      ..strokeWidth = 1;
    const spacing = 34.0;
    for (var y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rulePaint);
    }

    // Marge de gauche, comme sur une feuille de match.
    final marginPaint = Paint()
      ..color = WrappedPaper.stamp.withValues(alpha: .18)
      ..strokeWidth = 1.4;
    final marginX = size.width * .085;
    canvas.drawLine(
      Offset(marginX, 0),
      Offset(marginX, size.height),
      marginPaint,
    );

    // Grain : des points fixes, tirés d'une graine, donc stables d'une
    // image à l'autre — un grain qui scintille donnerait mal au cœur.
    final random = math.Random(seed * 7919 + 13);
    final grainPaint = Paint()..color = WrappedPaper.ink.withValues(alpha: .05);
    final grainCount =
        (size.width * size.height / 900).clamp(120, 1400).toInt();
    for (var i = 0; i < grainCount; i += 1) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * .9 + .2,
        grainPaint,
      );
    }

    // Ombre douce sur les bords : la feuille n'est pas parfaitement à plat.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 1.15,
          colors: [
            Colors.transparent,
            WrappedPaper.paperDeep.withValues(alpha: .42),
          ],
          stops: const [.45, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) => oldDelegate.seed != seed;
}

/// Le tampon du rang, encré de travers comme un vrai.
class WrappedStamp extends StatelessWidget {
  const WrappedStamp({
    super.key,
    required this.text,
    this.color = WrappedPaper.stamp,
    this.angle = -.14,
    this.size = 15,
  });

  final String text;
  final Color color;
  final double angle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: size * .9, vertical: size * .4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: .8), width: 2.4),
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: .07),
        ),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontFamily: WrappedPaper.stencil,
            fontSize: size * 1.25,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: color,
          ),
        ),
      ),
    );
  }
}
