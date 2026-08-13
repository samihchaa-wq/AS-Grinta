import 'package:flutter/material.dart';

/// Proportions de l'emblème, rapportées à sa largeur.
const _squareRatio = 0.82;
const _medalRatio = 0.32;
const _footerRatio = 0.30;

/// La médaille mord sur l'illustration, et le socle remonte sous la médaille
/// pour rester soudé au reste de l'emblème.
const _medalOverlap = 0.05;
const _footerOverlap = 0.10;

/// Hauteur totale de l'emblème pour une largeur de 1, médaille comprise.
///
/// Sert à réserver au badge exactement la place qu'il occupe : la disposition
/// précédente laissait une bande transparente sous le socle, qui rognait
/// d'autant la taille utile de l'emblème dans une ligne de tableau.
double badgeEmblemHeightRatio({required bool hasValue}) {
  final medal = hasValue ? _medalRatio - _footerOverlap : 0.0;
  return _squareRatio + medal + _footerRatio;
}

class BadgeEmblemBody extends StatelessWidget {
  const BadgeEmblemBody({
    super.key,
    required this.child,
    required this.size,
    required this.base,
    required this.footer,
    this.value,
  });

  final Widget child;
  final double size;
  final Color base;
  final String footer;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.isNotEmpty == true;
    final height = size * badgeEmblemHeightRatio(hasValue: hasValue);

    return SizedBox(
      width: size,
      height: height,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size * _squareRatio,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(size * 0.18),
              ),
              child: child,
            ),
          ),
          Positioned(
            top: height - size * _footerRatio,
            left: 0,
            right: 0,
            height: size * _footerRatio,
            child: Container(
              alignment: Alignment.center,
              color: const Color(0xFF0B1D40),
              child: FittedBox(
                child: Text(
                  footer,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          if (hasValue)
            Positioned(
              top: size * (_squareRatio - _medalOverlap),
              left: 0,
              right: 0,
              height: size * _medalRatio,
              child: Center(
                child: CircleAvatar(
                  radius: size * (_medalRatio / 2),
                  backgroundColor: base,
                  child: Text(value!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
