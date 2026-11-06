import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rapport de contraste WCAG entre deux couleurs opaques.
double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Seuil WCAG AA pour du texte courant.
const double _minimumContrast = 4.5;

const Map<String, Color> _availabilityColors = {
  'Convoqués': AppTheme.availabilityIn,
  'Liste d’attente': AppTheme.availabilityWaiting,
  'Absents': AppTheme.availabilityOut,
  'Sans réponse': AppTheme.availabilityUnknown,
};

void main() {
  test('les titres de colonnes de l’effectif restent lisibles', () {
    final surface = AppTheme.dark.colorScheme.surfaceContainer;
    _availabilityColors.forEach((label, color) {
      // Fond réel de la colonne : la couleur du groupe posée en très léger
      // voile sur la surface de la carte, comme dans l’écran Effectif.
      final background = Color.alphaBlend(
        color.withValues(alpha: .13),
        surface,
      );
      expect(
        _contrast(color, background),
        greaterThanOrEqualTo(_minimumContrast),
        reason: 'Titre « $label » illisible sur le fond de sa colonne.',
      );
    });
  });

  test('les groupes de disponibilité de la fiche match restent lisibles', () {
    _availabilityColors.forEach((label, color) {
      final background = Color.alphaBlend(
        color.withValues(alpha: .07),
        AppTheme.surface,
      );
      expect(
        _contrast(color, background),
        greaterThanOrEqualTo(_minimumContrast),
        reason: 'Titre « $label » illisible sur le fond de son groupe.',
      );
    });
  });
}
