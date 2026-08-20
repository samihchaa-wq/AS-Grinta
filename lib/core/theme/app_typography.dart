import 'package:flutter/material.dart';

/// Familles typographiques d'AS Grinta.
///
/// Trois rôles seulement, pour que la hiérarchie visuelle repose sur la forme
/// des caractères et non sur une surenchère de graisses :
///
/// * [ui] — toute l'interface (400 courant, 600 sous-titres, 800 titres,
///   900 titres d'écran) ;
/// * [numeric] — les chiffres qui doivent rester compacts et alignés : scores,
///   chronomètre, minutes de but, numéros de maillot, compteurs ;
/// * [mono] — les étiquettes courtes en majuscules (« 12 DISPO », « DOMICILE »),
///   toujours interlettrées.
abstract final class AppTypography {
  static const String ui = 'Barlow';
  static const String numeric = 'BarlowCondensed';
  static const String mono = 'IBMPlexMono';

  /// Style des étiquettes courtes en majuscules.
  static TextStyle label({
    required Color color,
    double fontSize = 10.5,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 1,
  }) =>
      TextStyle(
        fontFamily: mono,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: 1.1,
      );

  /// Style des valeurs chiffrées (scores, chronomètre, numéros).
  static TextStyle number({
    required Color color,
    required double fontSize,
    double height = 1,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: numeric,
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: height,
        letterSpacing: letterSpacing,
      );
}
