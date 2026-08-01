/// Fenêtre d'ouverture d'un match.
///
/// Un match ne « s'ouvre » que six jours avant son coup d'envoi : c'est déjà
/// la règle des pronostics (`MatchPredictionItem.opensAt`). Tant qu'il est
/// plus lointain, sa fiche ne montre que l'onglet Info — l'effectif, la
/// composition, le Tableau Blanc et le prono n'ont pas encore de sens.
const Duration kMatchOpensBeforeKickoff = Duration(days: 6);

/// `true` quand le coup d'envoi est encore à plus de six jours.
///
/// Un coup d'envoi inconnu est considéré comme ouvert : mieux vaut afficher
/// la fiche complète que de la vider sur une donnée manquante.
bool isMatchTooFarAway(DateTime? kickoffAt, {DateTime? now}) {
  if (kickoffAt == null) return false;
  final reference = now ?? DateTime.now();
  return reference.isBefore(kickoffAt.subtract(kMatchOpensBeforeKickoff));
}
