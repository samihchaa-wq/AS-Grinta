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
        child: _GrintaSpinnerMark(size: size),
      ),
    );
  }
}

/// Remplacement des anciens [CircularProgressIndicator].
///
/// Une valeur non nulle reste un indicateur circulaire déterminé. La signature
/// animée est réservée aux vrais chargements indéterminés, afin d'éviter que
/// les anneaux de statistiques deviennent plusieurs loaders simultanés.
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
                return Center(child: _GrintaSpinnerMark(size: size));
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Préserve les barres déterminées et remplace seulement leur état
/// indéterminé par la signature animée du club.
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
          child: Center(child: _GrintaSpinnerMark(size: 32)),
        ),
      ),
    );
  }
}

/// Signature animée de chargement : deux arcs aux couleurs du club qui
/// tournent l'un derrière l'autre.
///
/// Le tracé est purement géométrique, donc il reste lisible aussi bien à 16
/// pixels dans un bouton qu'à 92 pixels au centre d'une page. L'écusson, lui,
/// est réservé aux écrans de démarrage où il dispose de la place nécessaire.
class _GrintaSpinnerMark extends StatefulWidget {
  const _GrintaSpinnerMark({required this.size});

  final double size;

  @override
  State<_GrintaSpinnerMark> createState() => _GrintaSpinnerMarkState();
}

class _GrintaSpinnerMarkState extends State<_GrintaSpinnerMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
            painter: _GrintaSpinnerPainter(
              progress: _controller.value,
              reduceMotion: _reduceMotion,
            ),
          ),
        ),
      ),
    );
  }
}

class _GrintaSpinnerPainter extends CustomPainter {
  const _GrintaSpinnerPainter({
    required this.progress,
    required this.reduceMotion,
  });

  final double progress;
  final bool reduceMotion;

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = math.min(size.width, size.height);
    final stroke = (shortestSide * 0.115).clamp(2.0, 9.0).toDouble();
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (shortestSide - stroke) / 2,
    );

    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..color = AppTheme.primaryBright.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (reduceMotion) {
      _drawArc(
          canvas, rect, stroke, -math.pi / 2, _tau * 0.72, AppTheme.accent);
      return;
    }

    // L'arc principal s'allonge puis se rétracte pendant qu'il tourne : c'est
    // ce qui donne l'impression d'un mouvement continu sans jamais s'arrêter.
    final head = progress * _tau * 1.45;
    final breath = (math.sin(progress * _tau - math.pi / 2) + 1) / 2;
    final mainSweep = (0.16 + Curves.easeInOut.transform(breath) * 0.54) * _tau;

    const trailSweep = _tau * 0.13;
    const gap = _tau * 0.085;

    _drawArc(
      canvas,
      rect,
      stroke,
      head - gap - trailSweep,
      trailSweep,
      AppTheme.primaryBright,
    );
    _drawArc(canvas, rect, stroke, head, mainSweep, AppTheme.accent);
  }

  void _drawArc(
    Canvas canvas,
    Rect rect,
    double stroke,
    double start,
    double sweep,
    Color color,
  ) {
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GrintaSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}
