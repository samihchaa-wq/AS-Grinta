import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Loader animé et unifié pour toute l'application.
class GrintaLoader extends StatelessWidget {
  const GrintaLoader.page({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement de la page',
  }) : size = 92;

  const GrintaLoader.inline({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement en cours',
  }) : size = 58;

  const GrintaLoader.button({
    super.key,
    this.semanticLabel = 'Action en cours',
  })  : size = 32,
        message = null;

  final double size;

  /// Conservé pour ne pas casser les appels existants. Le loader reste
  /// volontairement sans texte, quelle que soit sa taille.
  final String? message;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: _BouncingBallMark(size: size),
      ),
    );
  }
}

/// Remplacement des anciens [CircularProgressIndicator].
///
/// Une valeur non nulle reste un indicateur circulaire déterminé. Le ballon
/// animé est réservé aux vrais chargements indéterminés, afin d'éviter que les
/// anneaux de statistiques deviennent plusieurs loaders simultanés.
class GrintaProgressIndicator extends StatelessWidget {
  const GrintaProgressIndicator({
    super.key,
    this.value,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.strokeWidth = 4,
    this.strokeAlign = 0,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeCap,
    this.constraints,
    this.padding,
    this.year2023,
  });

  final double? value;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final double strokeWidth;
  final double strokeAlign;
  final String? semanticsLabel;
  final String? semanticsValue;
  final StrokeCap? strokeCap;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final bool? year2023;

  @override
  Widget build(BuildContext context) {
    if (value != null) {
      return CircularProgressIndicator(
        value: value,
        backgroundColor: backgroundColor,
        color: color,
        valueColor: valueColor,
        strokeWidth: strokeWidth,
        strokeAlign: strokeAlign,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
        strokeCap: strokeCap,
        constraints: constraints,
        padding: padding,
      );
    }

    final effectiveConstraints = constraints ?? const BoxConstraints();
    return Semantics(
      label: semanticsLabel ?? 'Chargement en cours',
      value: semanticsValue,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: effectiveConstraints,
            child: LayoutBuilder(
              builder: (context, box) {
                final candidates = <double>[
                  if (box.hasBoundedWidth) box.maxWidth,
                  if (box.hasBoundedHeight) box.maxHeight,
                ];
                final available =
                    candidates.isEmpty ? 32.0 : candidates.reduce(math.min);
                final size = available >= 160
                    ? 92.0
                    : available.clamp(16.0, 32.0).toDouble();
                return Center(child: _BouncingBallMark(size: size));
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Préserve les barres déterminées et remplace seulement leur état
/// indéterminé par le ballon rebondissant.
class GrintaLinearProgressIndicator extends StatelessWidget {
  const GrintaLinearProgressIndicator({
    super.key,
    this.value,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.minHeight,
    this.semanticsLabel,
    this.semanticsValue,
    this.borderRadius,
    this.stopIndicatorColor,
    this.stopIndicatorRadius,
    this.trackGap,
    this.year2023,
  });

  final double? value;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final double? minHeight;
  final String? semanticsLabel;
  final String? semanticsValue;
  final BorderRadiusGeometry? borderRadius;
  final Color? stopIndicatorColor;
  final double? stopIndicatorRadius;
  final double? trackGap;
  final bool? year2023;

  @override
  Widget build(BuildContext context) {
    if (value != null) {
      return LinearProgressIndicator(
        value: value,
        backgroundColor: backgroundColor,
        color: color,
        valueColor: valueColor,
        minHeight: minHeight,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
      );
    }

    return Semantics(
      label: semanticsLabel ?? 'Chargement en cours',
      value: semanticsValue,
      liveRegion: true,
      child: const ExcludeSemantics(
        child: SizedBox(
          height: 32,
          child: Center(child: _BouncingBallMark(size: 32)),
        ),
      ),
    );
  }
}

class _BouncingBallMark extends StatefulWidget {
  const _BouncingBallMark({required this.size});

  final double size;

  @override
  State<_BouncingBallMark> createState() => _BouncingBallMarkState();
}

class _BouncingBallMarkState extends State<_BouncingBallMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion == _reduceMotion && _controller.isAnimating) return;

    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            isComplex: false,
            willChange: !_reduceMotion,
            painter: _BouncingBallPainter(
              progress: _reduceMotion ? 0 : _controller.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _BouncingBallPainter extends CustomPainter {
  const _BouncingBallPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = math.min(size.width, size.height);
    final radius = shortestSide * 0.205;
    final groundY = size.height * 0.78;
    final bounce = 4 * progress * (1 - progress);
    final center = Offset(
      size.width / 2,
      groundY - radius - size.height * 0.42 * bounce,
    );

    _drawImpactRipple(canvas, size, groundY, radius);
    _drawShadow(canvas, size, groundY, radius, bounce);
    _drawBall(canvas, center, radius, progress);
  }

  void _drawImpactRipple(
    Canvas canvas,
    Size size,
    double groundY,
    double radius,
  ) {
    const rippleDuration = 0.2;
    if (progress > rippleDuration) return;

    final phase = Curves.easeOut.transform(progress / rippleDuration);
    final opacity = (1 - phase) * 0.68;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, groundY + radius * 0.08),
      width: radius * (2.05 + phase * 2.35),
      height: radius * (0.38 + phase * 0.42),
    );

    canvas.drawOval(
      rect,
      Paint()
        ..color = AppTheme.primaryBright.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.018),
    );
    canvas.drawArc(
      rect,
      math.pi * 0.96,
      math.pi * 0.7,
      false,
      Paint()
        ..color = AppTheme.accent.withValues(alpha: opacity * 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.022)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawShadow(
    Canvas canvas,
    Size size,
    double groundY,
    double radius,
    double bounce,
  ) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, groundY + radius * 0.08),
        width: radius * (2.25 - bounce * 0.72),
        height: radius * (0.38 - bounce * 0.1),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.25 - bounce * 0.12),
    );
  }

  void _drawBall(
    Canvas canvas,
    Offset center,
    double radius,
    double progress,
  ) {
    final distanceFromImpact = math.min(progress, 1 - progress);
    final impact = (1 - (distanceFromImpact / 0.13)).clamp(0.0, 1.0).toDouble();
    final easedImpact = Curves.easeOut.transform(impact);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1 + easedImpact * 0.14, 1 - easedImpact * 0.18);
    canvas.rotate(progress * math.pi * 2);

    final ballRect = Rect.fromCircle(center: Offset.zero, radius: radius);
    canvas.drawCircle(
      Offset.zero,
      radius * 1.08,
      Paint()..color = AppTheme.primaryBright.withValues(alpha: 0.1),
    );
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.38, -0.44),
          radius: 1.05,
          colors: [
            Colors.white,
            Color(0xFFF3F6FC),
            AppTheme.primaryBright,
          ],
          stops: [0, 0.68, 1],
        ).createShader(ballRect),
    );

    final darkPaint = Paint()..color = AppTheme.background;
    final seamPaint = Paint()
      ..color = AppTheme.background.withValues(alpha: 0.58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, radius * 0.075)
      ..strokeCap = StrokeCap.round;

    final pentagon = Path();
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 5;
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
      final angle = -math.pi / 2 + i * math.pi * 2 / 5;
      final inner = Offset(
        math.cos(angle) * radius * 0.31,
        math.sin(angle) * radius * 0.31,
      );
      final outer = Offset(
        math.cos(angle) * radius * 0.78,
        math.sin(angle) * radius * 0.78,
      );
      canvas.drawLine(inner, outer, seamPaint);
      canvas.drawCircle(outer, radius * 0.125, darkPaint);
    }

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius * 0.82),
      -2.45,
      0.92,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, radius * 0.1)
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BouncingBallPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
