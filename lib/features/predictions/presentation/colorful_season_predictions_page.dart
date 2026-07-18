import 'package:as_grinta/features/predictions/presentation/scorer_dashboard_page.dart';
import 'package:flutter/material.dart';

/// Pronostics joueurs. Le fond est harmonisé avec le reste de l'application
/// (bleu nuit du thème) : plus de fond noir spécifique ni de lignes colorées.
class ColorfulSeasonPredictionsPage extends StatelessWidget {
  const ColorfulSeasonPredictionsPage({
    super.key,
    this.embedded = false,
    this.showRanking = true,
  });

  final bool embedded;
  final bool showRanking;

  @override
  Widget build(BuildContext context) {
    return ScorerDashboardPage(embedded: embedded);
  }
}
