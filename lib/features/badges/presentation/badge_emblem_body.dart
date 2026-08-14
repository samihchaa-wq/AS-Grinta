import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:flutter/material.dart';

/// Proportions des quatre zones de l'emblème, rapportées à sa largeur.
const kBadgeIllustrationRatio = 0.82;
const _valueRatio = 0.26;
const _labelRatio = 0.22;
const _periodRatio = 0.18;

/// Taille d'une étoile de palmarès, rapportée à la largeur de l'emblème.
const kBadgeEmblemStarRatio = 0.2;

/// Ce que les étoiles débordent au-dessus du rectangle : la moitié de leur
/// hauteur, l'autre moitié mordant sur l'illustration.
const kBadgeEmblemStarOverhangRatio = kBadgeEmblemStarRatio / 2;

/// Hauteur totale de l'emblème pour une largeur de 1, débord des étoiles
/// compris.
///
/// L'emblème empile image, nombre, critère et temporalité : les zones absentes
/// (badge sans valeur, critère sans période) ne réservent aucune place.
double badgeEmblemHeightRatio({
  required bool hasValue,
  required bool hasPeriod,
  bool hasStar = false,
}) {
  return (hasStar ? kBadgeEmblemStarOverhangRatio : 0) +
      kBadgeIllustrationRatio +
      (hasValue ? _valueRatio : 0) +
      _labelRatio +
      (hasPeriod ? _periodRatio : 0);
}

/// Le corps de l'emblème : un seul rectangle, découpé en bandes jointives.
///
/// Toutes les bandes textuelles reprennent exactement la couleur principale
/// du badge. Le texte est peint en blanc avec un contour noir afin de rester
/// lisible quelle que soit la couleur choisie pour l'emblème.
class BadgeEmblemBody extends StatelessWidget {
  const BadgeEmblemBody({
    super.key,
    required this.child,
    required this.size,
    required this.base,
    required this.descriptor,
    this.value,
  });

  final Widget child;
  final double size;
  final Color base;
  final BadgeDescriptor descriptor;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.isNotEmpty == true;
    final period = descriptor.period;

    return Container(
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: size * kBadgeIllustrationRatio,
            width: size,
            child: Center(child: child),
          ),
          if (hasValue)
            _Band(
              height: size * _valueRatio,
              color: base,
              child: _BandText(
                value!,
                fontSize: size * 0.17,
                color: Colors.white,
                letterSpacing: 0,
              ),
            ),
          _Band(
            height: size * _labelRatio,
            color: base,
            child: _BandText(
              descriptor.label,
              fontSize: size * 0.12,
              color: Colors.white,
            ),
          ),
          if (period != null)
            _Band(
              height: size * _periodRatio,
              color: base,
              child: _BandText(
                period,
                fontSize: size * 0.1,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

/// Une bande pleine largeur de l'emblème, collée à celle du dessus.
class _Band extends StatelessWidget {
  const _Band({required this.height, required this.color, required this.child});

  final double height;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      color: color,
      child: child,
    );
  }
}

/// Texte d'une bande : réduit pour tenir dans la largeur, jamais tronqué.
///
/// Deux couches strictement superposées sont rendues : une première en trait
/// noir, puis le texte blanc par-dessus. Le contour suit donc exactement les
/// chiffres et lettres sans modifier leur métrique ni la taille du badge.
class _BandText extends StatelessWidget {
  const _BandText(
    this.text, {
    required this.fontSize,
    required this.color,
    this.letterSpacing = 0.2,
  });

  final String text;
  final double fontSize;
  final Color color;
  final double letterSpacing;

  TextStyle _style({Color? fill, Paint? foreground}) {
    return TextStyle(
      color: fill,
      foreground: foreground,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: letterSpacing,
      height: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = fontSize * 0.16
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Text(
            text,
            maxLines: 1,
            style: _style(foreground: outline),
          ),
          Text(text, maxLines: 1, style: _style(fill: color)),
        ],
      ),
    );
  }
}
