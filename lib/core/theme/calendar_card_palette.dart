import 'package:flutter/material.dart';

/// Couleurs sémantiques des cartes du calendrier en mode « Défilé ».
///
/// Les fonds restent sombres pour préserver le thème de l'app, mais les
/// familles de couleurs sont volontairement assez éloignées pour que le type
/// de rendez-vous soit identifiable au premier coup d'œil.
abstract final class CalendarCardPalette {
  /// Repli pour un ancien match dont le type n'est pas encore connu.
  static const Color finishedSurface = Color(0xFF20242C);
  static const Color finishedBorder = Color(0xFF626A78);

  /// Championnat : conserve le bleu déjà utilisé par les matchs classiques.
  static const Color championshipSurface = Color(0xFF0B2E59);
  static const Color championshipBorder = Color(0xFF2F80ED);

  /// Alias historique : les écrans non encore spécialisés continuent à
  /// utiliser le bleu championnat sans changer de rendu.
  static const Color upcomingSurface = championshipSurface;
  static const Color upcomingBorder = championshipBorder;

  /// Amical : famille verte distincte du championnat et des événements.
  static const Color friendlySurface = Color(0xFF103629);
  static const Color friendlyBorder = Color(0xFF35B879);

  static const Color internalSurface = Color(0xFF2B1748);
  static const Color internalBorder = Color(0xFF8B5CF6);

  static const Color eventSurface = Color(0xFF403006);
  static const Color eventBorder = Color(0xFFD9A91A);

  static const Color cancelledSurface = Color(0xFF45171D);
  static const Color cancelledBorder = Color(0xFFD94B55);

  /// Couleur d'un match d'après son identité sportive, indépendamment du fait
  /// qu'il soit à venir ou terminé. Les archives sans type confirmé restent
  /// volontairement grises plutôt que d'inventer « Championnat ».
  static Color matchSurface(
    String? matchType, {
    bool unknownAsFinished = false,
  }) {
    return switch (matchType) {
      'entre_nous' => internalSurface,
      'amical' => friendlySurface,
      'championnat' => championshipSurface,
      _ => unknownAsFinished ? finishedSurface : championshipSurface,
    };
  }

  static Color matchBorder(
    String? matchType, {
    bool unknownAsFinished = false,
  }) {
    return switch (matchType) {
      'entre_nous' => internalBorder,
      'amical' => friendlyBorder,
      'championnat' => championshipBorder,
      _ => unknownAsFinished ? finishedBorder : championshipBorder,
    };
  }
}
