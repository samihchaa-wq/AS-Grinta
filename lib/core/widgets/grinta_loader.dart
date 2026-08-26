import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Barre de progression réservée au démarrage de l'application.
///
/// C'est le seul indicateur de chargement visuel autorisé dans l'application.
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
/// Tous les loaders intervenant après le démarrage sont volontairement
/// invisibles. Les écrans conservent simplement leur état d'attente jusqu'à
/// l'arrivée des données.
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

  const GrintaLoader.button({super.key, this.semanticLabel = 'Action en cours'})
    : size = 32,
      message = null;

  final double size;
  final String? message;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Remplacement compatible des anciens [CircularProgressIndicator].
///
/// Les valeurs déterminées restent visibles lorsqu'elles représentent une
/// donnée réelle (statistique, jauge, progression connue). Tout indicateur
/// indéterminé, donc tout loader, est supprimé visuellement.
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
    if (value == null) return const SizedBox.shrink();

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
}

/// Préserve uniquement les barres de progression déterminées.
/// Toute barre indéterminée secondaire est supprimée.
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
