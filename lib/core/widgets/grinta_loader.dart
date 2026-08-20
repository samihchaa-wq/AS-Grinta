import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// États d'attente d'AS Grinta.
///
/// Un seul dessin ne peut pas servir à la fois de chargement de page, de bloc,
/// de bouton et de barre indéterminée. Quatre échelles, quatre réponses :
///
/// * une liste encore vide affiche un **squelette** de sa propre structure
///   ([GrintaSkeletonLines]) ;
/// * un contenu déjà à l'écran n'est jamais effacé : il pâlit et un **fil de
///   progression** apparaît sous la barre du haut ([GrintaProgressThread]) ;
/// * un bouton ou une petite zone garde son libellé et gagne un **arc** de
///   16 px ([GrintaLoader.button]) ou trois points ([GrintaDotsLoader]) ;
/// * le **démarrage** de l'application est le seul endroit où la marque
///   s'anime ([GrintaLoader.startup]).
///
/// Tous respectent « Réduire les animations » : squelettes fixes, arcs
/// remplacés par un indicateur statique.
class GrintaLoader extends StatelessWidget {
  /// Chargement d'un écran encore vide : squelette de sa structure.
  const GrintaLoader.page({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement de la page',
  })  : _style = _LoaderStyle.skeleton,
        _lines = 4;

  /// Chargement d'un bloc encore vide, à l'intérieur d'un écran déjà monté.
  const GrintaLoader.inline({
    super.key,
    this.message,
    this.semanticLabel = 'Chargement en cours',
  })  : _style = _LoaderStyle.skeleton,
        _lines = 3;

  /// Action en cours dans un bouton ou une petite zone.
  const GrintaLoader.button({
    super.key,
    this.semanticLabel = 'Action en cours',
  })  : _style = _LoaderStyle.arc,
        _lines = 0,
        message = null;

  /// Démarrage de l'application : le blason, une seule fois par ouverture.
  const GrintaLoader.startup({
    super.key,
    this.message,
    this.semanticLabel = 'Démarrage de ASG',
  })  : _style = _LoaderStyle.startup,
        _lines = 0;

  final _LoaderStyle _style;
  final int _lines;

  /// Sous-titre. Affiché au démarrage seulement : les squelettes et les arcs
  /// restent volontairement muets, le contexte est déjà à l'écran.
  final String? message;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: switch (_style) {
          _LoaderStyle.skeleton => GrintaSkeletonLines(lines: _lines),
          _LoaderStyle.arc => const GrintaSpinnerArc(),
          _LoaderStyle.startup => _StartupMark(message: message),
        },
      ),
    );
  }
}

enum _LoaderStyle { skeleton, arc, startup }

/// Vrai quand l'utilisateur a demandé de réduire les animations.
bool _reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

// ---------------------------------------------------------------------------
// 4.1 — Liste ou tableau encore vide : squelette
// ---------------------------------------------------------------------------

/// Blocs arrondis qui tiennent la place du contenu à venir.
///
/// L'écran garde sa structure (barre du haut, onglets, en-têtes) et seul le
/// contenu est remplacé. Un balayage clair traverse chaque ligne de gauche à
/// droite, décalé d'une ligne à l'autre.
class GrintaSkeletonLines extends StatefulWidget {
  const GrintaSkeletonLines({
    super.key,
    this.lines = 4,
    this.lineHeight = 14,
    this.spacing = 12,
  });

  /// Base et crête du balayage.
  static const Color base = Color(0xFF152F4C);
  static const Color crest = Color(0xFF22415F);

  /// Largeurs relatives des lignes, pour éviter un pavé parfaitement régulier.
  static const List<double> _widths = [1, .88, .94, .72];

  final int lines;
  final double lineHeight;
  final double spacing;

  @override
  State<GrintaSkeletonLines> createState() => _GrintaSkeletonLinesState();
}

class _GrintaSkeletonLinesState extends State<GrintaSkeletonLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionOf(context)) {
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
    final reduceMotion = _reduceMotionOf(context);
    final count = math.max(1, widget.lines);
    return LayoutBuilder(
      builder: (context, box) {
        // Le squelette peut être posé dans une zone sans largeur imposée
        // (feuille, ligne défilante) : il garde alors une largeur de repli.
        final width = box.hasBoundedWidth ? box.maxWidth : 240.0;
        return RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < count; index++) ...[
                if (index > 0) SizedBox(height: widget.spacing),
                Opacity(
                  // La dernière ligne s'efface : le contenu continue au-delà.
                  opacity: index == count - 1 ? .5 : 1,
                  child: SizedBox(
                    width: width *
                        GrintaSkeletonLines._widths[
                            index % GrintaSkeletonLines._widths.length],
                    height: widget.lineHeight,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => CustomPaint(
                        painter: _SkeletonLinePainter(
                          // 0,1 s de décalage par ligne sur un cycle de 1,5 s.
                          phase: reduceMotion
                              ? null
                              : (_controller.value - index * .0667) % 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonLinePainter extends CustomPainter {
  const _SkeletonLinePainter({required this.phase});

  /// Position du balayage, ou `null` quand les animations sont réduites.
  final double? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.drawRRect(
      rrect,
      Paint()..color = GrintaSkeletonLines.base,
    );

    final current = phase;
    if (current == null || size.width <= 0) return;

    canvas
      ..save()
      ..clipRRect(rrect);
    final bandWidth = size.width * .38;
    final center = (current * 1.6 - .3) * size.width;
    final band = Rect.fromLTWH(
      center - bandWidth / 2,
      0,
      bandWidth,
      size.height,
    );
    canvas
      ..drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              GrintaSkeletonLines.crest.withValues(alpha: 0),
              GrintaSkeletonLines.crest,
              GrintaSkeletonLines.crest.withValues(alpha: 0),
            ],
          ).createShader(band),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _SkeletonLinePainter oldDelegate) =>
      oldDelegate.phase != phase;
}

// ---------------------------------------------------------------------------
// 4.2 — Des données sont déjà à l'écran : fil de progression
// ---------------------------------------------------------------------------

/// Fil de 2 px qui signale un rafraîchissement sans effacer le contenu.
class GrintaProgressThread extends StatefulWidget {
  const GrintaProgressThread({super.key, this.height = 2});

  /// Opacité du contenu déjà affiché pendant un rafraîchissement.
  static const double contentOpacity = .55;

  final double height;

  @override
  State<GrintaProgressThread> createState() => _GrintaProgressThreadState();
}

class _GrintaProgressThreadState extends State<GrintaProgressThread>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionOf(context)) {
      _controller
        ..stop()
        ..value = .5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotionOf(context);
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ProgressThreadPainter(
              progress: Curves.easeInOut.transform(_controller.value),
              still: reduceMotion,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressThreadPainter extends CustomPainter {
  const _ProgressThreadPainter({required this.progress, required this.still});

  final double progress;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppTheme.progressTrack,
    );
    if (size.width <= 0) return;

    final indicator = Paint()..color = AppTheme.accent;
    if (still) {
      canvas.drawRect(Offset.zero & size, indicator);
      return;
    }

    const share = .32;
    final width = size.width * share;
    final left = (size.width - width) * progress;
    canvas.drawRect(Rect.fromLTWH(left, 0, width, size.height), indicator);
  }

  @override
  bool shouldRepaint(covariant _ProgressThreadPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.still != still;
}

// ---------------------------------------------------------------------------
// 4.3 — Bouton ou petite zone
// ---------------------------------------------------------------------------

/// Arc circulaire de 16 px posé à côté du libellé d'un bouton.
class GrintaSpinnerArc extends StatefulWidget {
  const GrintaSpinnerArc({
    super.key,
    this.size = 16,
    this.strokeWidth = 2,
    this.color = Colors.white,
  });

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  State<GrintaSpinnerArc> createState() => _GrintaSpinnerArcState();
}

class _GrintaSpinnerArcState extends State<GrintaSpinnerArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionOf(context)) {
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
    final reduceMotion = _reduceMotionOf(context);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SpinnerArcPainter(
              turn: reduceMotion ? null : _controller.value,
              strokeWidth: widget.strokeWidth,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerArcPainter extends CustomPainter {
  const _SpinnerArcPainter({
    required this.turn,
    required this.strokeWidth,
    required this.color,
  });

  /// Rotation, ou `null` quand les animations sont réduites : l'arc devient
  /// alors un repère fixe.
  final double? turn;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (math.min(size.width, size.height) - strokeWidth) / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = color.withValues(alpha: .3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    canvas.drawArc(
      rect,
      (turn ?? 0) * math.pi * 2 - math.pi / 2,
      math.pi * .62,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerArcPainter oldDelegate) =>
      oldDelegate.turn != turn ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Trois points en fondu décalé, pour une zone minuscule : une ligne de
/// tableau qui se met à jour, une cellule, une pastille.
class GrintaDotsLoader extends StatefulWidget {
  const GrintaDotsLoader({
    super.key,
    this.dotSize = 6,
    this.spacing = 4,
    this.color = AppTheme.textFaint,
  });

  final double dotSize;
  final double spacing;
  final Color color;

  @override
  State<GrintaDotsLoader> createState() => _GrintaDotsLoaderState();
}

class _GrintaDotsLoaderState extends State<GrintaDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionOf(context)) {
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
    final reduceMotion = _reduceMotionOf(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 3; index++) ...[
              if (index > 0) SizedBox(width: widget.spacing),
              Opacity(
                opacity: reduceMotion
                    ? .55
                    : _dotOpacity(
                        // 0,18 s de décalage sur un cycle de 1,1 s.
                        (_controller.value - index * .1636) % 1,
                      ),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static double _dotOpacity(double phase) {
    final wave = math.sin(phase * math.pi);
    return .28 + wave.abs() * .72;
  }
}

// ---------------------------------------------------------------------------
// 4.4 — Démarrage de l'application
// ---------------------------------------------------------------------------

class _StartupMark extends StatefulWidget {
  const _StartupMark({this.message});

  final String? message;

  @override
  State<_StartupMark> createState() => _StartupMarkState();
}

class _StartupMarkState extends State<_StartupMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionOf(context)) {
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
    final reduceMotion = _reduceMotionOf(context);
    final subtitle = widget.message?.trim();
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _StartupRingPainter(
                        turn: reduceMotion ? null : _controller.value,
                      ),
                    ),
                  ),
                ),
                Image.asset(
                  'assets/images/as_grinta_logo.webp',
                  height: 56,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
              ],
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              subtitle.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTypography.label(
                color: AppTheme.textLabel,
                fontSize: 11,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StartupRingPainter extends CustomPainter {
  const _StartupRingPainter({required this.turn});

  final double? turn;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (math.min(size.width, size.height) - stroke) / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = AppTheme.progressTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      (turn ?? 0) * math.pi * 2 - math.pi / 2,
      math.pi * .5,
      false,
      Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StartupRingPainter oldDelegate) =>
      oldDelegate.turn != turn;
}

// ---------------------------------------------------------------------------
// Remplacements des indicateurs Material
// ---------------------------------------------------------------------------

/// Remplacement des anciens [CircularProgressIndicator].
///
/// Une valeur non nulle reste un indicateur circulaire déterminé. Un
/// chargement indéterminé prend l'échelle de la place qu'on lui laisse :
/// squelette dans une grande zone vide, arc de 16 px dans un bouton.
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
                if (available >= 160) {
                  return const Center(child: GrintaSkeletonLines(lines: 3));
                }
                return Center(
                  child: GrintaSpinnerArc(
                    size: available.clamp(14.0, 20.0).toDouble(),
                    color: color ?? Colors.white,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Préserve les barres déterminées et remplace leur état indéterminé par le
/// fil de progression du § 4.2.
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
      child: ExcludeSemantics(
        child: GrintaProgressThread(height: minHeight ?? 2),
      ),
    );
  }
}
