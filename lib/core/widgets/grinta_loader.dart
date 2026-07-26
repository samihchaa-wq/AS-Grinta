import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Loader animé et unifié pour toute l'application.
///
/// L'animation affiche un ballon stylisé qui tourne sur lui-même. Elle reste
/// lisible dans les formats page, inline et bouton.
class GrintaLoader extends StatefulWidget {
  const GrintaLoader.page({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement de la page',
  })  : size = 92,
        showShadow = true;

  const GrintaLoader.inline({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement en cours',
  })  : size = 58,
        showShadow = true;

  const GrintaLoader.button({super.key, this.semanticLabel = 'Action en cours'})
      : size = 32,
        showShadow = false,
        message = null;

  final double size;
  final bool showShadow;
  final String? message;
  final String semanticLabel;

  @override
  State<GrintaLoader> createState() => _GrintaLoaderState();
}

class _GrintaLoaderState extends State<GrintaLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final mark = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SpinningBallPainter(
              progress: reduceMotion ? 0.16 : _controller.value,
              showShadow: widget.showShadow,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: widget.message == null
            ? mark
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mark,
                  const SizedBox(height: 14),
                  Text(
                    widget.message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SpinningBallPainter extends CustomPainter {
  const _SpinningBallPainter({
    required this.progress,
    required this.showShadow,
  });

  final double progress;
  final bool showShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    final radius = size.width * 0.29;
    final rotation = progress * math.pi * 2;

    if (showShadow) {
      final pulse = 0.88 + (math.sin(progress * math.pi * 2) * 0.08);
      final shadowRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.84),
        width: radius * 1.45 * pulse,
        height: radius * 0.34,
      );
      canvas.drawOval(
        shadowRect,
        Paint()
          ..color = AppTheme.background.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.045),
      );
    }

    canvas.drawCircle(
      center,
      radius * 1.18,
      Paint()
        ..color = AppTheme.primaryBright.withValues(alpha: 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.075),
    );

    final ballPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 1.05,
        colors: [
          AppTheme.textPrimary,
          AppTheme.textPrimary.withValues(alpha: 0.96),
          AppTheme.primaryBright.withValues(alpha: 0.9),
        ],
        stops: const [0, 0.58, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, ballPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final darkPaint = Paint()..color = AppTheme.background.withValues(alpha: 0.9);
    final bluePaint = Paint()..color = AppTheme.primary;
    final pinkPaint = Paint()..color = AppTheme.accent;
    final seamPaint = Paint()
      ..color = AppTheme.background.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.width * 0.018)
      ..strokeCap = StrokeCap.round;

    final pentagon = Path();
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + (i * math.pi * 2 / 5);
      final point = Offset(
        math.cos(angle) * radius * 0.31,
        math.sin(angle) * radius * 0.31,
      );
      if (i == 0) {
        pentagon.moveTo(point.dx, point.dy);
      } else {
        pentagon.lineTo(point.dx, point.dy);
      }
    }
    pentagon.close();
    canvas.drawPath(pentagon, darkPaint);

    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + (i * math.pi * 2 / 5);
      final start = Offset(
        math.cos(angle) * radius * 0.31,
        math.sin(angle) * radius * 0.31,
      );
      final end = Offset(
        math.cos(angle) * radius * 0.78,
        math.sin(angle) * radius * 0.78,
      );
      canvas.drawLine(start, end, seamPaint);
      canvas.drawCircle(
        end,
        radius * 0.13,
        i.isEven ? bluePaint : pinkPaint,
      );
    }

    canvas.restore();

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.84),
      -2.35,
      0.95,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.028)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinningBallPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.showShadow != showShadow;
  }
}
