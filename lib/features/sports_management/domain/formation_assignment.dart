import 'dart:ui' show Offset;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Coût d'un gardien placé ailleurs que dans les cages.
///
/// Bien plus grand que n'importe quel déplacement sur le terrain (au plus 2
/// en distance au carré) : un gardien retourne toujours au but quand le poste
/// est libre, mais reste sur le terrain plutôt que d'être envoyé sur le banc.
const double _goalkeeperOutfieldCost = 100;

/// Coût d'un joueur laissé sans poste parce que le dispositif est plein.
const double _unplacedCost = 1000;

/// Un gardien n'est laissé sans poste qu'en tout dernier recours.
const double _unplacedGoalkeeperCost = 2000;

/// Répartit les joueurs [field] sur les postes [slots] d'un dispositif.
///
/// Chaque joueur rejoint le poste le plus proche de celui qu'il occupe : on
/// cherche la répartition qui déplace le moins l'équipe dans son ensemble
/// (somme des distances au carré, ce qui évite de sacrifier un joueur pour en
/// arranger deux). Passer d'un 4-4-2 à un 4-3-3 garde donc la défense en
/// défense et envoie les attaquants devant, au lieu de distribuer les postes
/// dans l'ordre de la liste. Le gardien va toujours au but.
///
/// Le résultat associe l'identifiant de chaque joueur placé à son poste. Un
/// joueur absent du résultat n'a pas trouvé de poste : cela n'arrive que
/// lorsqu'il y a plus de joueurs que de postes.
Map<String, FootballFormationSlot> assignFieldPlayersToSlots(
  List<MatchCompositionEntry> field,
  List<FootballFormationSlot> slots,
) {
  final players = field.length;
  final slotCount = slots.length;
  if (players == 0 || slotCount == 0) return const {};

  double cost(int player, int slot) {
    final entry = field[player];
    final target = slots[slot];
    final position = Offset(entry.x ?? .5, entry.y ?? .5);
    final distance = (position - target.position).distanceSquared;
    if (entry.isGoalkeeper && target.label != 'GB') {
      return distance + _goalkeeperOutfieldCost;
    }
    return distance;
  }

  double unplaced(int player) =>
      field[player].isGoalkeeper ? _unplacedGoalkeeperCost : _unplacedCost;

  // Programmation dynamique exacte sur les postes déjà pris : au plus 11
  // postes, soit 2 048 combinaisons par joueur — instantané.
  final masks = 1 << slotCount;
  final best = List<double>.filled((players + 1) * masks, 0);
  final choice = List<int>.filled(players * masks, -1);
  for (var player = players - 1; player >= 0; player -= 1) {
    for (var used = 0; used < masks; used += 1) {
      var bestCost = unplaced(player) + best[(player + 1) * masks + used];
      var bestSlot = -1;
      for (var slot = 0; slot < slotCount; slot += 1) {
        if (used & (1 << slot) != 0) continue;
        final candidate = cost(player, slot) +
            best[(player + 1) * masks + (used | 1 << slot)];
        if (candidate < bestCost) {
          bestCost = candidate;
          bestSlot = slot;
        }
      }
      best[player * masks + used] = bestCost;
      choice[player * masks + used] = bestSlot;
    }
  }

  final result = <String, FootballFormationSlot>{};
  var used = 0;
  for (var player = 0; player < players; player += 1) {
    final slot = choice[player * masks + used];
    if (slot < 0) continue;
    result[field[player].participantId] = slots[slot];
    used |= 1 << slot;
  }
  return result;
}
