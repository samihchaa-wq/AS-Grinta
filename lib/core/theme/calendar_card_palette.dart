import 'package:flutter/material.dart';

/// Couleurs sémantiques des cartes du calendrier en mode « Défilé ».
///
/// Les fonds restent sombres pour préserver le thème de l'app, mais les
/// familles de couleurs sont volontairement assez éloignées pour que le type
/// de rendez-vous soit identifiable au premier coup d'œil.
abstract final class CalendarCardPalette {
  static const Color finishedSurface = Color(0xFF101F16);
  static const Color finishedBorder = Color(0xFF2E6B45);

  static const Color upcomingSurface = Color(0xFF122C4C);
  static const Color upcomingBorder = Color(0xFF3D7DD8);

  static const Color internalSurface = Color(0xFF2B1748);
  static const Color internalBorder = Color(0xFF8B5CF6);

  static const Color eventSurface = Color(0xFF0E2138);
  static const Color eventBorder = Color(0xFF2A527E);

  static const Color cancelledSurface = Color(0xFF45171D);
  static const Color cancelledBorder = Color(0xFFD94B55);
}
