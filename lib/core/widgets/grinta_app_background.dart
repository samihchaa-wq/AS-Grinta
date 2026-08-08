import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Fond global de l'application.
///
/// Il affiche l'illustration officielle du club (drapés bleu nuit et filets
/// dorés) à sa résolution native. L'asset est un WebP sans perte, rendu en
/// [BoxFit.cover] avec un filtrage haute qualité : aucune recompression ni
/// rééchantillonnage destructif n'est appliqué à l'image d'origine.
class GrintaAppBackground extends StatelessWidget {
  const GrintaAppBackground({super.key});

  /// Illustration de fond, partagée par le démarrage et l'application montée.
  static const String assetPath =
      'assets/images/backgrounds/as_grinta_app_background.webp';

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: RepaintBoundary(
        child: ColoredBox(
          // Bleu nuit repris de l'illustration : il évite tout flash clair
          // avant le décodage de l'image et comble les écrans très larges.
          color: AppTheme.background,
          child: Image(
            image: AssetImage(assetPath),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
