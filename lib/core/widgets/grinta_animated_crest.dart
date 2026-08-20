import 'package:flutter/material.dart';

/// Écusson du club animé, réservé aux écrans d'attente qui disposent de place.
///
/// L'animation reste volontairement discrète : une respiration lente et un
/// reflet qui balaie le blason. Elle signale que l'application travaille sans
/// jamais donner l'impression de clignoter.
class GrintaAnimatedCrest extends StatefulWidget {
  const GrintaAnimatedCrest({
    super.key,
    this.width = 240,
    this.semanticLabel = 'AS La Grinta',
  });

  final double width;
  final String semanticLabel;

  @override
  State<GrintaAnimatedCrest> createState() => _GrintaAnimatedCrestState();
}

class _GrintaAnimatedCrestState extends State<GrintaAnimatedCrest>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
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
    final crest = Image.asset(
      'assets/images/as_grinta_logo.webp',
      width: widget.width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (_reduceMotion) {
      return Semantics(label: widget.semanticLabel, image: true, child: crest);
    }

    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            // Respiration : une pulsation sinusoïdale de 3,5 % d'amplitude.
            final breath = 1 + 0.035 * (1 - (2 * t - 1).abs());
            // Reflet : il traverse le blason sur la première moitié du cycle,
            // puis attend hors champ pour laisser respirer l'animation.
            final sweep = (t / 0.55).clamp(0.0, 1.0).toDouble();
            final shine = -1.6 + sweep * 3.2;

            return Transform.scale(
              scale: breath,
              child: ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(shine - 0.22, -1),
                  end: Alignment(shine + 0.22, 1),
                  colors: const [
                    Color(0x00FFFFFF),
                    Color(0x4DFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(bounds),
                child: child,
              ),
            );
          },
          child: crest,
        ),
      ),
    );
  }
}
