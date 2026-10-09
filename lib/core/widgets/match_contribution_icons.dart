import 'package:flutter/material.dart';

/// Icônes des faits de match d'un joueur, partagées par la composition d'un
/// match terminé et la fiche joueur : ⚽ pour un but, un crampon pour une
/// passe décisive, 👑 pour l'Homme du match.

/// Ballon d'un but.
class GoalIcon extends StatelessWidget {
  const GoalIcon({super.key, this.size = 11});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text('⚽', style: TextStyle(fontSize: size, height: 1));
  }
}

/// Couronne de l'Homme du match.
class ManOfTheMatchIcon extends StatelessWidget {
  const ManOfTheMatchIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text('👑', style: TextStyle(fontSize: size, height: 1));
  }
}

/// Crampon d'une passe décisive, dessiné à la main : l'emoji 👟 est une
/// basket de course bleue, ni lisible ni dans le ton du ballon noir et blanc.
/// Celui-ci reprend les mêmes codes : tige blanche cerclée de noir, semelle
/// grise à crampons et un liseré jaune aux couleurs du club.
///
/// [size] est la hauteur, comme la taille de police d'un emoji voisin.
class AssistBootIcon extends StatelessWidget {
  const AssistBootIcon({super.key, this.size = 11});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * _bootAspectRatio,
      height: size,
      child: const CustomPaint(painter: _BootPainter()),
    );
  }
}

// Le dessin occupe une grille de 24 × 18.
const double _bootGridWidth = 24;
const double _bootGridHeight = 18;
const double _bootAspectRatio = _bootGridWidth / _bootGridHeight;

class _BootPainter extends CustomPainter {
  const _BootPainter();

  static const _ink = Color(0xFF111827);
  static const _upper = Color(0xFFF8FAFC);
  static const _stripe = Color(0xFFFACC15);

  // Semelle gris clair : un noir disparaîtrait sur le fond sombre de la
  // fiche joueur comme sur le vert du terrain.
  static const _sole = Color(0xFFB6C2D2);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _bootGridWidth, size.height / _bootGridHeight);

    // Tige : talon à gauche, col, cou-de-pied, puis la pointe à droite.
    final upper = Path()
      ..moveTo(2.2, 3.2)
      ..lineTo(7.4, 3.2)
      ..quadraticBezierTo(8.4, 6.4, 11.6, 6.6)
      ..lineTo(16.4, 7.6)
      ..cubicTo(20.6, 8.4, 22.8, 10.2, 22.8, 12.4)
      ..lineTo(22.8, 13.2)
      ..lineTo(1.6, 13.2)
      ..cubicTo(1.0, 9.6, 1.2, 5.8, 2.2, 3.2)
      ..close();

    canvas.drawPath(upper, Paint()..color = _upper);

    // Liseré aux couleurs du club, du talon vers la pointe.
    final stripe = Path()
      ..moveTo(3.2, 11.0)
      ..quadraticBezierTo(10.0, 10.6, 17.0, 8.6)
      ..lineTo(18.6, 9.4)
      ..quadraticBezierTo(10.6, 12.4, 3.0, 12.6)
      ..close();
    canvas.drawPath(stripe, Paint()..color = _stripe);

    // Lacets.
    final laces = Paint()
      ..color = _ink
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(11.4, 7.4), const Offset(12.2, 9.0), laces);
    canvas.drawLine(const Offset(13.8, 7.9), const Offset(14.6, 9.4), laces);

    canvas.drawPath(
      upper,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Semelle et crampons.
    final sole = Paint()..color = _sole;
    for (final x in const [3.6, 8.2, 15.4, 20.0]) {
      canvas.drawRRect(
        RRect.fromLTRBR(
            x - 1.2, 14.0, x + 1.2, 17.6, const Radius.circular(.7)),
        sole,
      );
    }
    final soleShape = RRect.fromLTRBR(
      1.0,
      12.6,
      23.4,
      15.2,
      const Radius.circular(1.2),
    );
    canvas.drawRRect(soleShape, sole);
    canvas.drawRRect(
      soleShape,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BootPainter oldDelegate) => false;
}
