import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:flutter/material.dart';

/// Proportions des quatre zones de l'emblème, rapportées à sa largeur.
const _illustrationRatio = 0.82;
const _valueRatio = 0.26;
const _labelRatio = 0.22;
const _periodRatio = 0.18;

const _footerColor = Color(0xFF0B1D40);

/// Hauteur totale de l'emblème pour une largeur de 1.
///
/// L'emblème empile image, nombre, critère et temporalité : les zones absentes
/// (badge sans valeur, critère sans période) ne réservent aucune place.
double badgeEmblemHeightRatio({
  required bool hasValue,
  required bool hasPeriod,
}) {
  return _illustrationRatio +
      (hasValue ? _valueRatio : 0) +
      _labelRatio +
      (hasPeriod ? _periodRatio : 0);
}

/// Le corps de l'emblème : un seul rectangle, découpé en bandes jointives.
///
/// Rien ne dépasse et rien ne flotte — l'illustration, le nombre et le socle
/// partagent le même fond et le même arrondi, pour se lire comme une pièce
/// unique plutôt que comme un carré surmonté d'éléments rapportés.
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
            height: size * _illustrationRatio,
            width: size,
            child: Center(child: child),
          ),
          if (hasValue)
            _Band(
              height: size * _valueRatio,
              color: Color.alphaBlend(const Color(0x33000000), base),
              child: _BandText(
                value!,
                fontSize: size * 0.17,
                color: Colors.white,
                letterSpacing: 0,
              ),
            ),
          _Band(
            height: size * _labelRatio,
            color: _footerColor,
            child: _BandText(
              descriptor.label,
              fontSize: size * 0.12,
              color: Colors.white,
            ),
          ),
          if (period != null)
            _Band(
              height: size * _periodRatio,
              color: _footerColor,
              child: _BandText(
                period,
                fontSize: size * 0.1,
                color: Colors.white70,
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

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: letterSpacing,
          height: 1,
        ),
      ),
    );
  }
}
