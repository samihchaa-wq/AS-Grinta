import 'package:as_grinta/features/predictions/presentation/season_prediction_entry_page.dart';
import 'package:flutter/material.dart';

export 'package:as_grinta/features/predictions/presentation/season_prediction_entry_page.dart';

/// Relais de compatibilité pour les anciens points d’entrée.
///
/// La saisie est désormais isolée dans [SeasonPredictionEntryPage] et la vue
/// verrouillée utilise les cartes-jauges de Prono joueurs.
class SeasonPredictionsPage extends StatelessWidget {
  const SeasonPredictionsPage({super.key});

  @override
  Widget build(BuildContext context) => const SeasonPredictionEntryPage();
}
