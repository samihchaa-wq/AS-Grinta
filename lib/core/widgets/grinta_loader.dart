import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_skeleton.dart';
import 'package:flutter/material.dart';

/// Barre de progression réservée au démarrage de l'application.
///
/// C'est le seul indicateur de chargement animé conservé dans l'interface.
/// Tous les chargements intervenant une fois l'application ouverte utilisent
/// des aperçus gris du contenu ou, dans les petits contrôles, aucun indicateur.
class GrintaStartupProgressBar extends StatelessWidget {
  const GrintaStartupProgressBar({
    super.key,
    this.width = 132,
    this.semanticLabel = 'Démarrage de ASG',
  });

  final double width;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: AppTheme.primaryBright.withValues(alpha: 0.2),
              color: AppTheme.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compatibilité avec les anciens appels de chargement.
///
/// Les variantes page et inline affichent désormais des blocs gris qui
/// préfigurent le contenu. La variante bouton est volontairement invisible :
/// le bouton reste simplement désactivé pendant l'action.
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
  final String? message;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (size <= 32) return const SizedBox.shrink();

    final viewportWidth = MediaQuery.sizeOf(context).width;
    final width = (viewportWidth - 48).clamp(180.0, 420.0).toDouble();
    final rows = size >= 80 ? 5 : 2;

    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: GrintaSkeleton.rows(itemCount: rows),
        ),
      ),
    );
  }
}

/// Remplacement compatible des anciens [CircularProgressIndicator].
///
/// Une valeur non nulle reste un indicateur circulaire déterminé : ces anneaux
/// servent notamment à afficher des statistiques et ne sont pas des loaders.
/// Un indicateur indéterminé n'affiche plus jamais de cercle. Dans un grand
/// espace il devient un aperçu gris ; dans un petit contrôle il disparaît.
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

    return Semantics(
      label: semanticsLabel ?? 'Chargement du contenu',
      value: semanticsValue,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: constraints ?? const BoxConstraints(),
            child: LayoutBuilder(
              builder: (context, box) {
                final candidates = <double>[
                  if (box.hasBoundedWidth) box.maxWidth,
                  if (box.hasBoundedHeight) box.maxHeight,
                ];
                if (candidates.isEmpty) return const SizedBox.shrink();

                var available = candidates.first;
                for (final candidate in candidates.skip(1)) {
                  if (candidate < available) available = candidate;
                }

                // Dans un bouton, une icône ou une petite cellule, aucun
                // remplacement visuel : l'état désactivé suffit.
                if (available < 120) return const SizedBox.shrink();

                final width = (box.hasBoundedWidth ? box.maxWidth : 360.0)
                    .clamp(180.0, 420.0)
                    .toDouble();
                final rows = available >= 260 ? 4 : 2;
                return Center(
                  child: SizedBox(
                    width: width,
                    child: GrintaSkeleton.rows(itemCount: rows),
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

/// Préserve uniquement les barres de progression déterminées.
/// Les anciennes barres indéterminées secondaires sont supprimées.
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
    if (value == null) return const SizedBox.shrink();

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
}
