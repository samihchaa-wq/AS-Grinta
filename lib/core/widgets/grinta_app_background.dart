import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Fond global de l'application.
///
/// Il affiche l'illustration officielle du club (drapés bleu nuit et filets
/// dorés) à sa résolution native. L'asset est un WebP sans perte, rendu en
/// [BoxFit.cover] avec un filtrage haute qualité : aucune recompression ni
/// rééchantillonnage destructif n'est appliqué à l'image d'origine.
///
/// Un voile bleu nuit est posé par-dessus. C'est lui qui garantit désormais la
/// lisibilité du texte clair, à la place du liseré noir qui entourait
/// auparavant chaque lettre de l'application. L'illustration est déjà très
/// sombre — moins de 1 % de ses pixels dépassent la moitié de l'échelle de
/// luminosité — et seuls ses filets dorés sont réellement clairs : le voile
/// vise ces filets, ce qui explique qu'il reste discret.
class GrintaAppBackground extends StatelessWidget {
  const GrintaAppBackground({super.key});

  /// Illustration de fond, partagée par le démarrage et l'application montée.
  static const String assetPath =
      'assets/images/backgrounds/as_grinta_app_background.webp';

  /// Opacité du voile. Assez basse pour que les drapés et les filets dorés
  /// restent visibles, assez haute pour que le blanc du texte conserve un
  /// contraste confortable même posé sur un filet.
  static const double veilOpacity = .28;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: RepaintBoundary(
        child: ColoredBox(
          // Bleu nuit repris de l'illustration : il évite tout flash clair
          // avant le décodage de l'image et comble les écrans très larges.
          color: AppTheme.background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Image(
                image: AssetImage(assetPath),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
                gaplessPlayback: true,
              ),
              ColoredBox(
                color: AppTheme.background.withValues(alpha: veilOpacity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
