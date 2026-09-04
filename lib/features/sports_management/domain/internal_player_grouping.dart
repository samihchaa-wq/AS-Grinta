import 'package:as_grinta/features/sports_management/domain/player_position_affinity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Catégories compactes utilisées pour répartir visuellement les joueurs
/// d'un match entre nous.
///
/// [other] n'est pas un fourre-tout par défaut : c'est la catégorie de tous
/// ceux qui n'ont pas de poste moyen, et d'eux seuls.
enum InternalPlayerGroup { defenders, midfielders, attackers, other }

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
/// Cinq familles n'ont pas de poste moyen et partagent donc la même
/// catégorie : les invités, qui n'appartiennent pas à l'effectif et n'ont par
/// définition aucun historique à ce titre ; les gardiens, dont les passages au
/// but ne disent rien d'un poste de champ ; ceux dont l'échantillon est trop
/// mince pour conclure ; les polyvalents, dont aucun poste ne ressort
/// vraiment ; et ceux qu'on ne parvient pas à rattacher à une ligne.
///
/// Le cas du polyvalent mérite d'être dit : ranger sous une ligne un joueur
/// dont le poste principal pèse moins de 30 % affiche une certitude que
/// l'historique n'a pas. Le seuil est celui de [PlayerPositionProfile
/// .isVersatile], le même que « Simuler la compo » utilise pour n'en faire
/// qu'une variable d'ajustement. Rien n'est figé : chaque match enregistré
/// dans l'application fait bouger la part du poste principal, et un joueur qui
/// se fixe finit par franchir le seuil de lui-même.
InternalPlayerGroup internalPlayerGroupFor({
  required bool isGuest,
  required bool isGoalkeeper,
  required PlayerPositionProfile? profile,
}) {
  if (isGuest ||
      isGoalkeeper ||
      profile == null ||
      profile.appearances < kMinimumInternalPositionAppearances ||
      profile.isVersatile) {
    return InternalPlayerGroup.other;
  }

  return switch (dominantOutfieldPositionBand(profile)) {
    PlayerPositionBand.defender => InternalPlayerGroup.defenders,
    PlayerPositionBand.midfielder => InternalPlayerGroup.midfielders,
    PlayerPositionBand.attacker => InternalPlayerGroup.attackers,
    null => InternalPlayerGroup.other,
  };
}
