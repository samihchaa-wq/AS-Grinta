/// Journée de championnat.
///
/// Le numéro vient du calendrier de la ligue : le club ne joue pas forcément
/// toutes les journées d'une saison, donc il ne peut pas être déduit du rang
/// du match. L'application propose la journée suivante puis laisse
/// l'administrateur la corriger.
const int maxChampionshipRound = 60;

/// Journée proposée pour une nouvelle rencontre de championnat : une de plus
/// que la plus haute journée déjà enregistrée sur la saison.
int suggestedChampionshipRound(Iterable<int?> roundsOfSeason) {
  var highest = 0;
  for (final round in roundsOfSeason) {
    if (round != null && round > highest) highest = round;
  }
  final suggestion = highest + 1;
  return suggestion > maxChampionshipRound ? maxChampionshipRound : suggestion;
}

String? validateChampionshipRound(int? round) {
  if (round == null) return null;
  if (round < 1) return 'La journée doit être un nombre positif.';
  if (round > maxChampionshipRound) {
    return 'La journée ne peut pas dépasser $maxChampionshipRound.';
  }
  return null;
}

/// Autres rencontres de la saison qui portent déjà cette journée.
///
/// Deux rencontres peuvent légitimement partager un numéro quand la saison
/// enchaîne deux phases, donc c'est un avertissement et non une erreur.
bool championshipRoundIsAlreadyUsed({
  required int round,
  required Iterable<int?> roundsOfSeason,
}) {
  return roundsOfSeason.any((value) => value == round);
}
