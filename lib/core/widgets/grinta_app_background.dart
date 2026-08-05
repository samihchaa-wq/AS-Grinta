import 'package:flutter/material.dart';

/// Fond global de l'application.
///
/// Il est dessiné directement par Flutter pour éviter le cache d'un ancien
/// fichier d'image. Il ne contient volontairement ni lettre, ni logo, ni
/// ballon : uniquement une ambiance sombre bleue et rose.
class GrintaAppBackground extends StatelessWidget {
  const GrintaAppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: RepaintBoundary(
        child: CustomPaint(painter: _GrintaAppBackgroundPainter()),
      ),
    );
  }
}

class _GrintaAppBackgroundPainter extends CustomPainter {
  const _GrintaAppBackgroundPainter();

  static const _blue = Color(0xFF1685FF);
  static const _blueBright = Color(0xFF35B8FF);
  static const _pink = Color(0xFFFF1975);
  static const _pinkBright = Color(0xFFFF4CA3);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF02040C),
            Color(0xFF06132B),
            Color(0xFF030711),
          ],
          stops: [0, 0.52, 1],
        ).createShader(rect),
    );

    _drawGlow(
      canvas,
      rect,
      center: Offset(size.width * -0.06, size.height * 0.31),
      radius: size.longestSide * 0.55,
      color: _blue,
      opacity: 0.38,
    );
    _drawGlow(
      canvas,
      rect,
      center: Offset(size.width * 1.04, size.height * 0.68),
      radius: size.longestSide * 0.58,
      color: _pink,
      opacity: 0.34,
    );
    _drawGlow(
      canvas,
      rect,
      center: Offset(size.width * 0.48, size.height * 0.78),
      radius: size.longestSide * 0.38,
      color: const Color(0xFF4730FF),
      opacity: 0.13,
    );

    _drawBlueTrails(canvas, size);
    _drawPinkTrails(canvas, size);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.12),
          radius: 1.05,
          colors: [Color(0x00000000), Color(0x8A00030A)],
          stops: [0.46, 1],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x22000000), Color(0x00000000), Color(0x3D000000)],
          stops: [0, 0.42, 1],
        ).createShader(rect),
    );
  }

  void _drawGlow(
    Canvas canvas,
    Rect rect, {
    required Offset center,
    required double radius,
    required Color color,
    required double opacity,
  }) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _drawBlueTrails(Canvas canvas, Size size) {
    for (var index = 0; index < 7; index++) {
      final shift = index * size.height * 0.027;
      final path = Path()
        ..moveTo(-size.width * 0.22, size.height * 0.67 + shift)
        ..cubicTo(
          size.width * 0.08,
          size.height * 0.60 + shift,
          size.width * 0.20,
          size.height * 0.93 + shift,
          size.width * 0.66,
          size.height * 0.76 + shift,
        )
        ..cubicTo(
          size.width * 0.86,
          size.height * 0.69 + shift,
          size.width * 0.97,
          size.height * 0.61 + shift,
          size.width * 1.18,
          size.height * 0.56 + shift,
        );

      final intensity = (1 - index / 9).clamp(0.25, 1.0);
      _drawLightTrail(
        canvas,
        path,
        color: index.isEven ? _blueBright : _blue,
        width: 1.1 + intensity * 1.7,
        opacity: 0.18 + intensity * 0.24,
      );
    }
  }

  void _drawPinkTrails(Canvas canvas, Size size) {
    for (var index = 0; index < 8; index++) {
      final shift = index * size.height * 0.026;
      final path = Path()
        ..moveTo(size.width * 1.17, size.height * 0.56 + shift)
        ..cubicTo(
          size.width * 0.88,
          size.height * 0.62 + shift,
          size.width * 0.81,
          size.height * 0.90 + shift,
          size.width * 0.44,
          size.height * 0.76 + shift,
        )
        ..cubicTo(
          size.width * 0.24,
          size.height * 0.69 + shift,
          size.width * 0.10,
          size.height * 0.66 + shift,
          -size.width * 0.18,
          size.height * 0.73 + shift,
        );

      final intensity = (1 - index / 10).clamp(0.25, 1.0);
      _drawLightTrail(
        canvas,
        path,
        color: index.isEven ? _pinkBright : _pink,
        width: 1.0 + intensity * 1.8,
        opacity: 0.17 + intensity * 0.25,
      );
    }
  }

  void _drawLightTrail(
    Canvas canvas,
    Path path, {
    required Color color,
    required double width,
    required double opacity,
  }) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: opacity * 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GrintaAppBackgroundPainter oldDelegate) {
    return false;
  }
}
