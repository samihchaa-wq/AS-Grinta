import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Loader animé et unifié pour toute l'application.
///
/// L'animation représente une passe entre trois joueurs : elle remplace les
/// roues Material génériques par un signal visuel propre à Ma Petite Grinta.
class GrintaLoader extends StatefulWidget {
  const GrintaLoader.page({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement de la page',
  })  : size = 92,
        showPlayers = true;

  const GrintaLoader.inline({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement en cours',
  })  : size = 58,
        showPlayers = true;

  const GrintaLoader.button({super.key, this.semanticLabel = 'Action en cours'})
      : size = 32,
        showPlayers = false,
        message = null;

  final double size;
  final bool showPlayers;
  final String? message;
  final String semanticLabel;

  @override
  State<GrintaLoader> createState() => _GrintaLoaderState();
}

class _GrintaLoaderState extends State<GrintaLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
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
            painter: _PassingDrillPainter(
              progress: reduceMotion ? 0.35 : _controller.value,
              showPlayers: widget.showPlayers,
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

class _PassingDrillPainter extends CustomPainter {
  const _PassingDrillPainter({
    required this.progress,
    required this.showPlayers,
  });

  final double progress;
  final bool showPlayers;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * 0.54;
    final startX = size.width * 0.18;
    final endX = size.width * 0.82;
    final route = endX - startX;

    final linePaint = Paint()
      ..color = AppTheme.primaryBright.withValues(alpha: 0.24)
      ..strokeWidth = math.max(1.5, size.width * 0.025)
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(startX, centerY), Offset(endX, centerY), linePaint);

    if (showPlayers) {
      final playerRadius = size.width * 0.07;
      final playerPaint = Paint()..color = AppTheme.primary;
      final accentPaint = Paint()..color = AppTheme.accent;
      final whitePaint = Paint()..color = AppTheme.textPrimary;

      canvas.drawCircle(Offset(startX, centerY), playerRadius, playerPaint);
      canvas.drawCircle(
        Offset(size.width * 0.5, centerY),
        playerRadius,
        whitePaint,
      );
      canvas.drawCircle(Offset(endX, centerY), playerRadius, accentPaint);
    }

    final eased = Curves.easeInOutCubic.transform(progress);
    final x = startX + route * eased;
    final jump = math.sin(progress * math.pi) * size.height * 0.28;
    final ballCenter = Offset(x, centerY - jump);
    final ballRadius = size.width * (showPlayers ? 0.105 : 0.14);

    final glowPaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.08);
    canvas.drawCircle(ballCenter, ballRadius * 1.55, glowPaint);

    final ballPaint = Paint()..color = AppTheme.textPrimary;
    canvas.drawCircle(ballCenter, ballRadius, ballPaint);

    final seamPaint = Paint()
      ..color = AppTheme.background.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.width * 0.018)
      ..strokeCap = StrokeCap.round;

    final rotation = progress * math.pi * 4;
    for (var i = 0; i < 3; i++) {
      final angle = rotation + (i * math.pi * 2 / 3);
      final inner = Offset(
        ballCenter.dx + math.cos(angle) * ballRadius * 0.25,
        ballCenter.dy + math.sin(angle) * ballRadius * 0.25,
      );
      final outer = Offset(
        ballCenter.dx + math.cos(angle) * ballRadius * 0.7,
        ballCenter.dy + math.sin(angle) * ballRadius * 0.7,
      );
      canvas.drawLine(inner, outer, seamPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PassingDrillPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.showPlayers != showPlayers;
  }
}
