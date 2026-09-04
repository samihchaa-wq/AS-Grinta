import 'package:as_grinta/features/sports_management/domain/player_position_affinity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Catégories compactes utilisées pour répartir visuellement les joueurs
/// d'un match entre nous.
enum InternalPlayerGroup { defenders, midfielders, attackers, guests, other }

/// En dessous de trois titularisations connues, le poste de référence serait
/// trop fragile pour classer le joueur automatiquement.
const int kMinimumInternalPositionAppearances = 3;

/// Classe un joueur avec exactement la même affinité de poste que
/// « Simuler la compo ».
///
/// Le profil historique, sa pondération et la géométrie des postes sont donc
/// partagés ; ce fichier ne conserve que la traduction vers les groupes
/// d'affichage propres aux matchs entre nous.
///
/// Un invité reste un invité, même quand c'est un joueur du club qui a tout un
/// passé au poste : il n'est pas de l'effectif du jour, et l'admin a besoin de
/// le voir comme tel pour composer. C'est la même convention que la feuille de
/// match, qui leur réserve déjà leur propre section.
InternalPlayerGroup internalPlayerGroupFor({
  required bool isGuest,
  required bool isGoalkeeper,
  required PlayerPositionProfile? profile,
}) {
  if (isGuest) return InternalPlayerGroup.guests;

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
