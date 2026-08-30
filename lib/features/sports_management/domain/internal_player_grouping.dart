import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Catégories compactes utilisées pour répartir visuellement les joueurs
/// d'un match entre nous.
enum InternalPlayerGroup { defenders, midfielders, attackers, other }

/// En dessous de trois titularisations connues, le poste moyen serait trop
/// fragile pour classer le joueur automatiquement.
const int kMinimumInternalPositionAppearances = 3;

/// Classe un joueur à partir du même profil de positions que la simulation de
/// composition. Le calcul prend la moyenne pondérée de ses positions sur le
/// terrain plutôt que son seul poste le plus fréquent.
InternalPlayerGroup internalPlayerGroupFor({
  required bool isGoalkeeper,
  required PlayerPositionProfile? profile,
}) {
  if (isGoalkeeper ||
      profile == null ||
      profile.appearances < kMinimumInternalPositionAppearances) {
    return InternalPlayerGroup.other;
  }

  var weightedY = 0.0;
  var totalWeight = 0.0;
  for (final sample in profile.samples) {
    if (sample.slotLabel == 'GB') continue;
    final position = matchSheetSlotPositions[sample.slotLabel];
    if (position == null || sample.weight <= 0) continue;
    weightedY += position.dy * sample.weight;
    totalWeight += sample.weight;
  }
  if (totalWeight <= 0) return InternalPlayerGroup.other;

  final averageY = weightedY / totalWeight;

  // Les seuils sont placés dans les espaces entre les lignes de la feuille de
  // match : défenseurs (~.65+) / milieux (~.25-.53) / attaquants (~.22-).
  if (averageY >= .59) return InternalPlayerGroup.defenders;
  if (averageY <= .235) return InternalPlayerGroup.attackers;
  return InternalPlayerGroup.midfielders;
}
