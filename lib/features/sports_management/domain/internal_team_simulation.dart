import 'dart:math';

import 'package:as_grinta/features/sports_management/domain/composition_simulation.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/internal_team_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Résultat d'une simulation sur un seul terrain de match « entre nous ».
class InternalTeamSimulation {
  const InternalTeamSimulation({
    required this.slotByParticipantId,
    required this.goalkeeperParticipantId,
    required this.usedRandomGoalkeeper,
  });

  final Map<String, String> slotByParticipantId;
  final String goalkeeperParticipantId;

  /// Vrai seulement quand l'équipe ne contenait aucun gardien déclaré.
  final bool usedRandomGoalkeeper;
}

/// Place tous les joueurs d'une équipe sur le dispositif choisi.
///
/// Contrairement à la simulation d'un match classique, aucun joueur ne peut
/// rester sur le banc : le nombre de joueurs et le nombre d'emplacements sont
/// strictement identiques.
///
/// Le hasard n'intervient que lorsque personne n'est gardien déclaré. [random]
/// est injecté pour rendre cette règle testable ; l'UI utilise [Random.secure]
/// afin que deux simulations successives ne retombent pas volontairement sur
/// le même joueur.
InternalTeamSimulation simulateInternalTeam({
  required InternalTeamFormation formation,
  required List<InternalCompositionEntry> players,
  required Map<String, PlayerPositionProfile> profiles,
  required Random random,
}) {
  if (players.isEmpty) {
    throw ArgumentError.value(players, 'players', 'L’équipe est vide.');
  }
  if (players.length > 11) {
    throw ArgumentError.value(
      players.length,
      'players',
      'Une équipe ne peut pas dépasser 11 joueurs.',
    );
  }
  if (formation.playerCount != players.length) {
    throw ArgumentError(
      'Le dispositif ${formation.code} attend ${formation.playerCount} joueurs, '
      'pas ${players.length}.',
    );
  }

  final declaredKeepers = players.where((player) => player.isGoalkeeper).toList()
    ..sort((a, b) => a.participantId.compareTo(b.participantId));
  final usedRandomGoalkeeper = declaredKeepers.isEmpty;
  final goalkeeper = declaredKeepers.isNotEmpty
      ? declaredKeepers.first
      : players[random.nextInt(players.length)];

  final candidates = [
    for (final player in players)
      SimulationCandidate(
        participantId: player.participantId,
        displayName: player.displayName,
        benchCount: 0,
        profile: profiles[player.participantId],
        // Pour un match entre nous, un invité est un joueur à part entière : il
        // doit lui aussi être placé sur le terrain.
        isGuest: false,
        // Un seul gardien est réservé aux buts. Un éventuel second gardien
        // déclaré peut ainsi occuper un poste de champ au lieu de finir au banc.
        isGoalkeeper: player.participantId == goalkeeper.participantId,
      ),
  ];

  final result = simulateComposition(
    slots: formation.slots,
    candidates: candidates,
  );
  if (result.bench.isNotEmpty || result.emptySlots.isNotEmpty) {
    throw StateError(
      'La simulation interne doit placer chaque joueur et remplir chaque poste.',
    );
  }

  return InternalTeamSimulation(
    goalkeeperParticipantId: goalkeeper.participantId,
    usedRandomGoalkeeper: usedRandomGoalkeeper,
    slotByParticipantId: {
      for (final placement in result.placements)
        placement.candidate.participantId: placement.slot.label,
    },
  );
}
