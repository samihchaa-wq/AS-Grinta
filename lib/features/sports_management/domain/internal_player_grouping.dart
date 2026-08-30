import 'package:as_grinta/features/sports_management/domain/player_position_affinity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Catégories compactes utilisées pour répartir visuellement les joueurs
/// d'un match entre nous.
enum InternalPlayerGroup { defenders, midfielders, attackers, other }

/// En dessous de trois titularisations connues, le poste de référence serait
/// trop fragile pour classer le joueur automatiquement.
const int kMinimumInternalPositionAppearances = 3;

/// Classe un joueur avec exactement la même affinité de poste que
/// « Simuler la compo ».
///
/// Le profil historique, sa pondération et la géométrie des postes sont donc
/// partagés ; ce fichier ne conserve que la traduction vers les quatre groupes
/// d'affichage propres aux matchs entre nous.
InternalPlayerGroup internalPlayerGroupFor({
  required bool isGoalkeeper,
  required PlayerPositionProfile? profile,
}) {
  if (isGoalkeeper ||
      profile == null ||
      profile.appearances < kMinimumInternalPositionAppearances) {
    return InternalPlayerGroup.other;
  }

  return switch (dominantOutfieldPositionBand(profile)) {
    PlayerPositionBand.defender => InternalPlayerGroup.defenders,
    PlayerPositionBand.midfielder => InternalPlayerGroup.midfielders,
    PlayerPositionBand.attacker => InternalPlayerGroup.attackers,
    null => InternalPlayerGroup.other,
  };
}
