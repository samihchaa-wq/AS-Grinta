import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Aperçu gris du contenu en cours de chargement.
///
/// Afficher la forme de la page pendant l'attente, plutôt qu'un indicateur au
/// centre d'un écran vide, raccourcit l'attente perçue et évite le saut de
/// mise en page au moment où les données arrivent.
class GrintaSkeleton extends StatefulWidget {
  const GrintaSkeleton({super.key, required this.child});

  /// Liste de lignes de contenu, chacune reprenant la hauteur d'une carte.
  GrintaSkeleton.list({
    super.key,
    int itemCount = 4,
    double itemHeight = 96,
    double spacing = 12,
  }) : child = _SkeletonList(
          itemCount: itemCount,
          itemHeight: itemHeight,
          spacing: spacing,
        );

  /// Lignes compactes de classement : rang, nom, valeur.
  GrintaSkeleton.rows({super.key, int itemCount = 6})
      : child = _SkeletonRows(itemCount: itemCount);

  final Widget child;

  @override
  State<GrintaSkeleton> createState() => _GrintaSkeletonState();
}

class _GrintaSkeletonState extends State<GrintaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
    // Le contenu ne porte aucune information : il est masqué aux lecteurs
    // d'écran, qui reçoivent une simple annonce de chargement.
    return Semantics(
      label: 'Chargement du contenu',
      liveRegion: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              const base = AppTheme.surfaceHigh;
              const highlight = AppTheme.surfaceHero;
              if (_reduceMotion) {
                return ColorFiltered(
                  colorFilter: const ColorFilter.mode(base, BlendMode.srcIn),
                  child: child,
                );
              }

              // Une bande claire traverse le bloc de gauche à droite.
              final x = -1.9 + _controller.value * 3.8;
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(x - 0.9, -1),
                  end: Alignment(x + 0.9, 1),
                  colors: const [base, highlight, base],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(bounds),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Forme pleine dont seule la silhouette compte : la couleur est fournie par
/// le dégradé de [GrintaSkeleton].
class _Block extends StatelessWidget {
  const _Block({required this.width, required this.height, this.radius = 8});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList({
    required this.itemCount,
    required this.itemHeight,
    required this.spacing,
  });

  final int itemCount;
  final double itemHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          SizedBox(
            height: itemHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _Block(width: 140, height: 12),
                      const SizedBox(height: 10),
                      _Block(width: 220 - (i.isEven ? 0 : 44), height: 12),
                      const SizedBox(height: 10),
                      const _Block(width: 88, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(
            children: [
              const _Block(width: 26, height: 26, radius: 13),
              const SizedBox(width: 14),
              const _Block(width: 34, height: 34, radius: 17),
              const SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Block(
                    width: 118 + (i.isEven ? 34 : 0),
                    height: 12,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const _Block(width: 44, height: 12),
            ],
          ),
        ],
      ],
    );
  }
}
