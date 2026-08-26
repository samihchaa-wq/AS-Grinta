import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rendu du terrain de football partagé par la composition d'un match, la
/// préparation de l'effectif et le suivi en direct.
///
/// Tout est peint au vecteur, sans image : le poids du bundle web ne bouge
/// pas et le terrain reste net quelle que soit la taille d'écran.
///
/// Les tracés suivent les proportions officielles d'un terrain de 105 m sur
/// 68 m. Les distances horizontales sont converties avec [_mx], les
/// verticales avec [_my] ; les cercles et les arcs utilisent l'échelle
/// horizontale des deux côtés pour rester ronds, la vignette étant un peu
/// plus étroite qu'un vrai terrain.
class FootballPitchPainter extends CustomPainter {
  const FootballPitchPainter({this.highlighted = false});

  /// Éclaircit la pelouse quand un joueur est glissé au-dessus du terrain.
  final bool highlighted;

  /// Nombre de bandes de tonte. Un nombre impair évite que la bande du haut
  /// et celle du bas soient de la même teinte de part et d'autre du rond
  /// central.
  static const int _stripeCount = 9;

  /// Marge entre le bord de la vignette et la ligne de touche.
  static const double _insetRatio = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    final surface = Offset.zero & size;
    final inset = size.shortestSide * _insetRatio;
    final pitch = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    _paintTurf(canvas, surface);
    _paintLighting(canvas, surface);
    _paintMarkings(canvas, pitch);
  }

  /// Pelouse tondue en bandes alternées, comme sur un terrain entretenu.
  void _paintTurf(Canvas canvas, Rect surface) {
    final dark = highlighted
        ? const Color(0xFF1A6B3C)
        : const Color(0xFF14512E);
    final light = highlighted
        ? const Color(0xFF23824B)
        : const Color(0xFF1C6B3B);

    canvas.drawRect(surface, Paint()..color = dark);

    final stripeHeight = surface.height / _stripeCount;
    final stripe = Paint()..color = light;
    for (var i = 0; i < _stripeCount; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(
          surface.left,
          surface.top + i * stripeHeight,
          surface.width,
          stripeHeight,
        ),
        stripe,
      );
    }
  }

  /// Éclairage de stade : un peu plus de lumière au centre, des angles qui
  /// retombent dans l'ombre. Sans ça, les bandes de tonte donnent une surface
  /// plate qui ne ressemble pas à de l'herbe.
  void _paintLighting(Canvas canvas, Rect surface) {
    canvas
      ..drawRect(
        surface,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF), Color(0x1A000000)],
            stops: [0, 0.45, 1],
          ).createShader(surface),
      )
      ..drawRect(
        surface,
        Paint()
          ..shader = const RadialGradient(
            radius: 0.9,
            colors: [Color(0x00000000), Color(0x0F000000), Color(0x73000000)],
            stops: [0.35, 0.65, 1],
          ).createShader(surface),
      );
  }

  void _paintMarkings(Canvas canvas, Rect pitch) {
    // Un mètre réel, en pixels, dans chaque direction.
    final mx = pitch.width / 68;
    final my = pitch.height / 105;
    final stroke = math.max(1.2, pitch.width * 0.005);
    final centreX = pitch.center.dx;

    final markings = Path()
      // Lignes de touche et de but.
      ..addRect(pitch)
      // Ligne médiane.
      ..moveTo(pitch.left, pitch.center.dy)
      ..lineTo(pitch.right, pitch.center.dy)
      // Rond central.
      ..addOval(Rect.fromCircle(center: pitch.center, radius: 9.15 * mx));

    for (final top in const [true, false]) {
      final goalLine = top ? pitch.top : pitch.bottom;
      final inward = top ? 1.0 : -1.0;

      // Surface de réparation (40,32 m sur 16,5 m).
      markings.addRect(
        Rect.fromCenter(
          center: Offset(centreX, goalLine + inward * 16.5 * my / 2),
          width: 40.32 * mx,
          height: 16.5 * my,
        ),
      );

      // Surface de but (18,32 m sur 5,5 m).
      markings.addRect(
        Rect.fromCenter(
          center: Offset(centreX, goalLine + inward * 5.5 * my / 2),
          width: 18.32 * mx,
          height: 5.5 * my,
        ),
      );

      // Arc de cercle de la surface : portion du cercle de 9,15 m centré sur
      // le point de penalty qui dépasse de la surface de réparation.
      final spotY = goalLine + inward * 11 * my;
      final radius = 9.15 * mx;
      final boxGap = 5.5 * my;
      if (boxGap < radius) {
        final half = math.asin(boxGap / radius);
        markings.addArc(
          Rect.fromCircle(center: Offset(centreX, spotY), radius: radius),
          top ? half : math.pi + half,
          math.pi - 2 * half,
        );
      }
    }

    // Arcs de corner (1 m), un quart de cercle tourné vers l'intérieur.
    final cornerRadius = 1.2 * mx;
    final corners = <Offset, double>{
      pitch.topLeft: 0,
      pitch.topRight: math.pi / 2,
      pitch.bottomRight: math.pi,
      pitch.bottomLeft: 3 * math.pi / 2,
    };
    corners.forEach((corner, startAngle) {
      markings.addArc(
        Rect.fromCircle(center: corner, radius: cornerRadius),
        startAngle,
        math.pi / 2,
      );
    });

    // La peinture d'un vrai terrain bave légèrement sur l'herbe : ce halo
    // évite des lignes qui ont l'air collées par-dessus l'image. Il est
    // obtenu par un trait large et transparent plutôt que par un flou, qui
    // coûte beaucoup trop cher à rastériser sur un tracé de cette taille.
    canvas
      ..drawPath(
        markings,
        Paint()
          ..color = const Color(0x26FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        markings,
        Paint()
          ..color = const Color(0x33FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.9
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        markings,
        Paint()
          ..color = const Color(0xE8FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );

    // Points de penalty et point central.
    final spot = Paint()..color = const Color(0xE8FFFFFF);
    final spotRadius = math.max(1.6, stroke * 0.9);
    canvas.drawCircle(pitch.center, spotRadius, spot);
    for (final top in const [true, false]) {
      final goalLine = top ? pitch.top : pitch.bottom;
      final inward = top ? 1.0 : -1.0;
      canvas.drawCircle(
        Offset(centreX, goalLine + inward * 11 * my),
        spotRadius,
        spot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate is! FootballPitchPainter ||
      oldDelegate.highlighted != highlighted;
}

/// Prénom d'un joueur posé sur le terrain.
///
/// Le fond translucide remplace l'ombre portée utilisée jusqu'ici. Sur les
/// tracés blancs — lignes de surface — le texte ombré se confondait avec le
/// décor : le nom du gardien devenait illisible.
class PitchPlayerName extends StatelessWidget {
  const PitchPlayerName({super.key, required this.label, this.fontSize = 11});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD1071527),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
