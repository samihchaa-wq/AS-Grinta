import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MomentWatermarkKind { event, friendly, championship, internal }

/// Filigrane vectoriel dessiné directement dans Flutter.
///
/// Le pictogramme reste carré et conserve toujours ses proportions : seule
/// l'intégration est légèrement inclinée, agrandie puis rognée par la carte.
class MomentCardWatermark extends StatelessWidget {
  const MomentCardWatermark({
    super.key,
    required this.kind,
    required this.color,
    required this.child,
    this.opacity = .075,
  });

  final MomentWatermarkKind kind;
  final Color color;
  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final side = (MediaQuery.sizeOf(context).width * .56).clamp(205.0, 285.0);

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          right: -side * .18,
          top: -side * .16,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: -.115,
                child: SizedBox.square(
                  dimension: side,
                  child: CustomPaint(
                    painter: _MomentWatermarkPainter(kind: kind, color: color),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

MomentWatermarkKind momentWatermarkKindForMatchType(String? matchType) {
  return switch (matchType) {
    'amical' => MomentWatermarkKind.friendly,
    'entre_nous' => MomentWatermarkKind.internal,
    _ => MomentWatermarkKind.championship,
  };
}

class _MomentWatermarkPainter extends CustomPainter {
  const _MomentWatermarkPainter({required this.kind, required this.color});

  final MomentWatermarkKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 240;
    canvas.scale(scale, scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const center = Offset(120, 120);
    canvas.drawCircle(center, 105, stroke);
    canvas.drawCircle(center, 98, thin);

    if (kind == MomentWatermarkKind.event) {
      _drawEvent(canvas, stroke, thin);
    } else if (kind == MomentWatermarkKind.friendly) {
      _drawFriendly(canvas, stroke, thin);
    } else if (kind == MomentWatermarkKind.championship) {
      _drawChampionship(canvas, stroke, thin);
    } else {
      _drawInternal(canvas, stroke, thin);
    }
  }

  void _drawEvent(Canvas canvas, Paint stroke, Paint thin) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(63, 62, 105, 92),
        const Radius.circular(8),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(63, 86), const Offset(168, 86), stroke);
    canvas.drawLine(const Offset(84, 54), const Offset(84, 73), stroke);
    canvas.drawLine(const Offset(145, 54), const Offset(145, 73), stroke);

    for (final y in <double>[105, 125]) {
      for (final x in <double>[82, 104, 126, 148]) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 7, height: 7),
          thin,
        );
      }
    }

    _drawStar(canvas, const Offset(157, 151), 29, 13, stroke);
    _drawSpark(canvas, const Offset(48, 109), 7, thin);
    _drawSpark(canvas, const Offset(189, 109), 7, thin);
  }

  void _drawFriendly(Canvas canvas, Paint stroke, Paint thin) {
    final leftArm = Path()
      ..moveTo(48, 139)
      ..lineTo(83, 110)
      ..lineTo(105, 126)
      ..lineTo(80, 154)
      ..close();
    final rightArm = Path()
      ..moveTo(192, 139)
      ..lineTo(157, 110)
      ..lineTo(135, 126)
      ..lineTo(160, 154)
      ..close();
    canvas.drawPath(leftArm, stroke);
    canvas.drawPath(rightArm, stroke);

    final clasp = Path()
      ..moveTo(83, 110)
      ..cubicTo(93, 92, 103, 89, 114, 98)
      ..lineTo(123, 106)
      ..lineTo(133, 98)
      ..cubicTo(143, 91, 153, 94, 159, 108)
      ..cubicTo(151, 118, 143, 124, 135, 129)
      ..cubicTo(130, 134, 124, 134, 119, 129)
      ..lineTo(111, 121)
      ..lineTo(102, 128)
      ..cubicTo(96, 132, 90, 130, 85, 124);
    canvas.drawPath(clasp, stroke);
    canvas.drawLine(const Offset(104, 105), const Offset(134, 126), thin);
    canvas.drawLine(const Offset(99, 112), const Offset(127, 132), thin);

    _drawBall(canvas, const Offset(120, 169), 27, stroke, thin);
  }

  void _drawChampionship(Canvas canvas, Paint stroke, Paint thin) {
    final bowl = Path()
      ..moveTo(82, 62)
      ..lineTo(158, 62)
      ..lineTo(151, 118)
      ..quadraticBezierTo(145, 140, 120, 146)
      ..quadraticBezierTo(95, 140, 89, 118)
      ..close();
    canvas.drawPath(bowl, stroke);
    canvas.drawLine(const Offset(82, 70), const Offset(158, 70), thin);

    final leftHandle = Path()
      ..moveTo(83, 78)
      ..cubicTo(59, 70, 53, 83, 58, 101)
      ..cubicTo(63, 118, 75, 126, 91, 128);
    final rightHandle = Path()
      ..moveTo(157, 78)
      ..cubicTo(181, 70, 187, 83, 182, 101)
      ..cubicTo(177, 118, 165, 126, 149, 128);
    canvas.drawPath(leftHandle, stroke);
    canvas.drawPath(rightHandle, stroke);

    _drawStar(canvas, const Offset(120, 101), 19, 8, thin);
    canvas.drawLine(const Offset(120, 146), const Offset(120, 166), stroke);
    canvas.drawLine(const Offset(105, 166), const Offset(135, 166), stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(94, 172, 52, 13),
        const Radius.circular(3),
      ),
      stroke,
    );

    _drawLaurel(canvas, const Offset(71, 145), -1, thin);
    _drawLaurel(canvas, const Offset(169, 145), 1, thin);
  }

  void _drawInternal(Canvas canvas, Paint stroke, Paint thin) {
    for (final head in const <Offset>[
      Offset(78, 86),
      Offset(120, 76),
      Offset(162, 86),
    ]) {
      canvas.drawCircle(head, 15, stroke);
    }

    final shoulders = Path()
      ..moveTo(54, 127)
      ..cubicTo(59, 108, 70, 102, 84, 103)
      ..cubicTo(95, 104, 102, 111, 105, 124)
      ..moveTo(95, 111)
      ..cubicTo(101, 97, 110, 92, 120, 92)
      ..cubicTo(130, 92, 139, 97, 145, 111)
      ..moveTo(135, 124)
      ..cubicTo(138, 111, 145, 104, 156, 103)
      ..cubicTo(170, 102, 181, 108, 186, 127);
    canvas.drawPath(shoulders, stroke);
    canvas.drawLine(const Offset(88, 109), const Offset(105, 101), thin);
    canvas.drawLine(const Offset(135, 101), const Offset(152, 109), thin);
    canvas.drawLine(const Offset(61, 128), const Offset(61, 160), stroke);
    canvas.drawLine(const Offset(179, 128), const Offset(179, 160), stroke);

    _drawBall(canvas, const Offset(120, 169), 29, stroke, thin);
  }

  void _drawBall(
    Canvas canvas,
    Offset center,
    double radius,
    Paint stroke,
    Paint thin,
  ) {
    canvas.drawCircle(center, radius, stroke);
    final pentagon = Path();
    for (var i = 0; i < 5; i += 1) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 5;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * .34;
      if (i == 0) {
        pentagon.moveTo(point.dx, point.dy);
      } else {
        pentagon.lineTo(point.dx, point.dy);
      }
    }
    pentagon.close();
    canvas.drawPath(pentagon, thin);

    for (var i = 0; i < 5; i += 1) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 5;
      final from =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * .34;
      final to =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * .82;
      canvas.drawLine(from, to, thin);
    }
  }

  void _drawLaurel(Canvas canvas, Offset origin, int direction, Paint paint) {
    final stem = Path()
      ..moveTo(origin.dx, origin.dy + 42)
      ..quadraticBezierTo(
        origin.dx + direction * 20,
        origin.dy + 20,
        origin.dx + direction * 18,
        origin.dy - 18,
      );
    canvas.drawPath(stem, paint);

    for (var i = 0; i < 5; i += 1) {
      final y = origin.dy + 30 - i * 13;
      final x = origin.dx + direction * (5 + i * 3);
      final leaf = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + direction * 15,
          y - 8,
          x + direction * 14,
          y - 17,
        )
        ..quadraticBezierTo(x + direction * 4, y - 14, x, y)
        ..close();
      canvas.drawPath(leaf, paint);
    }
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double outerRadius,
    double innerRadius,
    Paint paint,
  ) {
    final path = Path();
    for (var i = 0; i < 10; i += 1) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSpark(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - radius)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MomentWatermarkPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
