import 'package:flutter/material.dart';

/// Fond global de l'application.
///
/// Il reprend les couleurs du blason AS La Grinta sans afficher le logo :
/// bleu nuit, bleu royal et touches jaunes très légères.
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

  static const _blue = Color(0xFF3475C9);
  static const _blueBright = Color(0xFF67A9F3);
  static const _gold = Color(0xFFFBE80C);
  static const _goldBright = Color(0xFFFFF36A);

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
            Color(0xFF020914),
            Color(0xFF071B34),
            Color(0xFF030B18),
          ],
          stops: [0, 0.52, 1],
        ).createShader(rect),
    );

    _drawGlow(
      canvas,
      rect,
      center: Offset(size.width * -0.08, size.height * 0.28),
      radius: size.longestSide * 0.58,
      color: _blue,
      opacity: 0.43,
    );
    _drawGlow(
      canvas,
      rect,
      center: Offset(size.width * 1.04, size.height * 0.66),
      radius: size.longestSide * 0.54,
      color: _gold,
      opacity: 0.17,
    );
    _drawGlow(
      canvas,
      rect,
      center: Offset(size.width * 0.52, size.height * 0.82),
      radius: size.longestSide * 0.42,
      color: const Color(0xFF1D5A9D),
      opacity: 0.18,
    );

    _drawBlueTrails(canvas, size);
    _drawGoldTrails(canvas, size);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.1),
          radius: 1.08,
          colors: [Color(0x00000000), Color(0x8F00040B)],
          stops: [0.45, 1],
        ).createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x18000000), Color(0x00000000), Color(0x47000000)],
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
        opacity: 0.16 + intensity * 0.24,
      );
    }
  }

  void _drawGoldTrails(Canvas canvas, Size size) {
    for (var index = 0; index < 6; index++) {
      final shift = index * size.height * 0.031;
      final path = Path()
        ..moveTo(size.width * 1.15, size.height * 0.58 + shift)
        ..cubicTo(
          size.width * 0.89,
          size.height * 0.63 + shift,
          size.width * 0.80,
          size.height * 0.88 + shift,
          size.width * 0.47,
          size.height * 0.76 + shift,
        )
        ..cubicTo(
          size.width * 0.27,
          size.height * 0.69 + shift,
          size.width * 0.10,
          size.height * 0.67 + shift,
          -size.width * 0.16,
          size.height * 0.73 + shift,
        );

      final intensity = (1 - index / 8).clamp(0.25, 1.0);
      _drawLightTrail(
        canvas,
        path,
        color: index.isEven ? _goldBright : _gold,
        width: .9 + intensity * 1.4,
        opacity: 0.08 + intensity * 0.15,
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
        ..color = color.withValues(alpha: opacity * 0.24)
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
