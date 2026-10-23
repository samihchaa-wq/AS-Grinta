import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_affinity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Affinité minimale pour qu'un poste reste crédible.
///
/// En dessous, le joueur n'est plus placé « à côté de son poste » mais hors
/// de ses habitudes : la simulation ne s'y résout que pour ne pas laisser un
/// poste vide, et le signale.
const double kPlausiblePositionFit = .05;

/// Pourquoi la simulation a placé un joueur à ce poste.
enum SimulatedPlacementReason {
  /// Gardien déclaré de l'effectif, placé dans les buts.
  goalkeeper,

  /// C'est le poste où le joueur a le plus joué.
  mainPosition,

  /// Un poste qu'il a déjà réellement tenu, sans que ce soit son principal.
  usualPosition,

  /// Un poste voisin de ceux qu'il occupe habituellement.
  nearbyPosition,

  /// Hors de ses habitudes : le poste serait sinon resté vide.
  outOfPosition,

  /// Aucun poste connu (recrue jamais alignée, invité) : à confirmer.
  unknownPosition,
}

/// Un joueur convoqué, prêt à être placé par la simulation.
class SimulationCandidate {
  const SimulationCandidate({
    required this.participantId,
    required this.displayName,
    required this.benchCount,
    this.profile,
    this.isGuest = false,
    this.isGoalkeeper = false,
    this.benchedLastMatch = false,
  });

  final String participantId;
  final String displayName;

  /// Nombre de matchs terminés où le joueur était remplaçant.
  final int benchCount;

  /// Ses postes de référence, archive et matchs joués depuis réunis. Nul pour
  /// un invité ou un joueur qui n'a encore jamais été aligné.
  final PlayerPositionProfile? profile;

  final bool isGuest;
  final bool isGoalkeeper;

  /// Vrai s'il a commencé le dernier match de la saison sur le banc : c'est
  /// à son tour de commencer.
  final bool benchedLastMatch;
}

/// Un joueur posé sur un poste du dispositif.
class SimulatedPlacement {
  const SimulatedPlacement({
    required this.slot,
    required this.candidate,
    required this.reason,
  });

  final FootballFormationSlot slot;
  final SimulationCandidate candidate;
  final SimulatedPlacementReason reason;
}

/// Résultat d'une simulation : un onze, un banc, et ce qui n'a pas pu être
/// rempli.
class SimulatedComposition {
  const SimulatedComposition({
    required this.placements,
    required this.bench,
    required this.emptySlots,
  });

  /// Les joueurs placés sur le terrain, dans l'ordre des postes du dispositif.
  final List<SimulatedPlacement> placements;

  /// Les remplaçants, le prochain à devoir monter en tête.
  final List<SimulationCandidate> bench;

  /// Les postes du dispositif restés sans joueur.
  final List<FootballFormationSlot> emptySlots;

  /// Les remplaçants du dernier match titularisés cette fois.
  List<SimulatedPlacement> get promotedFromBench => placements
      .where((placement) => placement.candidate.benchedLastMatch)
      .toList(growable: false);

  /// Les remplaçants du dernier match qui le restent : aucun poste crédible
  /// ne leur était libre.
  List<SimulationCandidate> get keptOnBench => bench
      .where((candidate) => candidate.benchedLastMatch && !candidate.isGuest)
      .toList(growable: false);

  /// Les postes que la simulation n'a pu remplir qu'avec un joueur hors de
  /// ses habitudes.
  List<SimulatedPlacement> get stretchedPlacements => _withReason(
        SimulatedPlacementReason.outOfPosition,
      );

  /// Les joueurs placés sans aucun poste connu.
  List<SimulatedPlacement> get unknownPlacements => _withReason(
        SimulatedPlacementReason.unknownPosition,
      );

  List<SimulatedPlacement> _withReason(SimulatedPlacementReason reason) =>
      placements
          .where((placement) => placement.reason == reason)
          .toList(growable: false);
}

/// Compose une équipe à partir des postes de référence des joueurs.
///
/// Le dispositif n'est jamais remis en cause : la simulation remplit les
/// postes de [slots]. Elle ne procède pas poste par poste — c'est ce qui
/// envoyait un défenseur au milieu pendant qu'un vrai milieu restait sur le
/// banc — mais cherche, parmi toutes les équipes possibles, celle qui
/// respecte au mieux ces règles, chacune primant sur les suivantes :
///
/// 1. aucun poste vide tant qu'un convoqué peut l'occuper ; un invité ne
///    sert qu'à compléter, jamais à prendre la place d'un joueur de
///    l'effectif ;
/// 2. personne hors de ses habitudes sans nécessité ;
/// 3. les remplaçants du dernier match commencent celui-ci ;
/// 4. chacun au plus près de ses postes habituels, pour l'équipe entière ;
/// 5. à égalité parfaite, le joueur le plus souvent resté sur le banc.
///
/// Les buts ne reviennent qu'à un gardien déclaré, et un gardien ne joue
/// jamais dans le champ.
///
/// Le résultat est déterministe : les mêmes convoqués redonnent toujours la
/// même équipe, quel que soit l'ordre dans lequel on les fournit.
SimulatedComposition simulateComposition({
  required List<FootballFormationSlot> slots,
  required List<SimulationCandidate> candidates,
}) {
  // La recherche exhaustive double à chaque poste : onze postes restent
  // instantanés, bien au-delà de seize elle deviendrait perceptible.
  assert(slots.length <= 16, 'Trop de postes pour une recherche exhaustive.');
  final players = [...candidates]..sort(_byName);
  final playerCount = players.length;
  final slotCount = slots.length;
  final masks = 1 << slotCount;

  final gains = [
    for (final player in players)
      [for (final slot in slots) _gain(player, slot)],
  ];

  // Programmation dynamique exacte sur les postes déjà pris : chaque joueur,
  // dans l'ordre, va sur le banc ou sur un poste libre. Onze postes, soit
  // 2 048 combinaisons par joueur — instantané.
  final best = List<_Score>.filled((playerCount + 1) * masks, _Score.none);
  final choice = List<int>.filled(playerCount * masks, -1);
  for (var player = playerCount - 1; player >= 0; player -= 1) {
    final next = (player + 1) * masks;
    for (var used = 0; used < masks; used += 1) {
      var bestScore = best[next + used];
      var bestSlot = -1;
      for (var slot = 0; slot < slotCount; slot += 1) {
        if (used & (1 << slot) != 0) continue;
        final gain = gains[player][slot];
        if (gain == null) continue;
        final score = gain + best[next + (used | 1 << slot)];
        if (score.compareTo(bestScore) > 0) {
          bestScore = score;
          bestSlot = slot;
        }
      }
      best[player * masks + used] = bestScore;
      choice[player * masks + used] = bestSlot;
    }
  }

  final slotOfPlayer = <int, int>{};
  var used = 0;
  for (var player = 0; player < playerCount; player += 1) {
    final slot = choice[player * masks + used];
    if (slot < 0) continue;
    slotOfPlayer[slot] = player;
    used |= 1 << slot;
  }

  final placed = <String>{};
  final placements = <SimulatedPlacement>[];
  for (var slot = 0; slot < slotCount; slot += 1) {
    final player = slotOfPlayer[slot];
    if (player == null) continue;
    final candidate = players[player];
    placed.add(candidate.participantId);
    placements.add(
      SimulatedPlacement(
        slot: slots[slot],
        candidate: candidate,
        reason: _reasonFor(candidate, slots[slot]),
      ),
    );
  }

  return SimulatedComposition(
    placements: placements,
    bench: players
        .where((candidate) => !placed.contains(candidate.participantId))
        .toList()
      ..sort(_benchOrder),
    emptySlots: [
      for (var slot = 0; slot < slotCount; slot += 1)
        if (!slotOfPlayer.containsKey(slot)) slots[slot],
    ],
  );
}

bool _isGoalkeeperSlot(FootballFormationSlot slot) => slot.label == 'GB';

/// Ce que rapporte un joueur à ce poste, ou null si le placement est exclu.
_Score? _gain(SimulationCandidate candidate, FootballFormationSlot slot) {
  // Les buts ne reviennent qu'à un gardien déclaré. Faute de gardien
  // convoqué, le poste reste vide et l'alerte existante prend le relais :
  // désigner d'office un joueur de champ serait un choix d'entraîneur. Et un
  // gardien qui n'a pas les buts va sur le banc plutôt que de dépanner.
  final inGoal = _isGoalkeeperSlot(slot);
  if (inGoal != candidate.isGoalkeeper) return null;
  final fit = inGoal ? 1.0 : _fit(candidate, slot);
  return _Score(
    squadPlayers: candidate.isGuest ? 0 : 1,
    guests: candidate.isGuest ? 1 : 0,
    outOfPosition:
        !inGoal && _hasHistory(candidate) && fit < kPlausiblePositionFit
            ? 1
            : 0,
    backFromBench: candidate.benchedLastMatch && !candidate.isGuest ? 1 : 0,
    fit: fit,
    waited: candidate.benchCount,
  );
}

/// Proximité d'un joueur avec un poste, d'après les postes qu'il occupe.
///
/// Le poste est pris à sa place de référence sur la feuille de match, et non
/// à l'endroit où ce dispositif le dessine : un milieu offensif reste un
/// milieu offensif, que le 4-2-1-3 le pose un peu plus bas ou non. Le calcul
/// vit dans [playerPositionAffinity] afin que la simulation et les
/// regroupements des matchs entre nous ne puissent pas diverger.
double _fit(SimulationCandidate candidate, FootballFormationSlot slot) {
  if (!_hasHistory(candidate)) return 0;
  return playerPositionAffinity(
    candidate.profile,
    matchSheetSlotPositions[slot.label] ?? slot.position,
  );
}

bool _hasHistory(SimulationCandidate candidate) =>
    candidate.profile?.samples.isNotEmpty ?? false;

SimulatedPlacementReason _reasonFor(
  SimulationCandidate candidate,
  FootballFormationSlot slot,
) {
  if (_isGoalkeeperSlot(slot)) return SimulatedPlacementReason.goalkeeper;
  final profile = candidate.profile;
  if (profile == null || profile.samples.isEmpty) {
    return SimulatedPlacementReason.unknownPosition;
  }
  // Même seuil que le calcul de l'équipe : un poste tenu une fois en passant
  // ne suffit pas à le rendre habituel.
  if (_fit(candidate, slot) < kPlausiblePositionFit) {
    return SimulatedPlacementReason.outOfPosition;
  }
  if (profile.mainSlotLabel == slot.label) {
    return SimulatedPlacementReason.mainPosition;
  }
  return profile.shareOf(slot.label) > 0
      ? SimulatedPlacementReason.usualPosition
      : SimulatedPlacementReason.nearbyPosition;
}

int _byName(SimulationCandidate a, SimulationCandidate b) {
  final byName = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
  return byName != 0 ? byName : a.participantId.compareTo(b.participantId);
}

/// Le remplaçant qui attend depuis le plus longtemps passe devant.
int _benchOrder(SimulationCandidate a, SimulationCandidate b) {
  if (a.benchedLastMatch != b.benchedLastMatch) {
    return a.benchedLastMatch ? -1 : 1;
  }
  final byBench = b.benchCount.compareTo(a.benchCount);
  return byBench != 0 ? byBench : _byName(a, b);
}

/// La valeur d'une équipe, critère par critère, du plus important au moins
/// important.
class _Score {
  const _Score({
    required this.squadPlayers,
    required this.guests,
    required this.outOfPosition,
    required this.backFromBench,
    required this.fit,
    required this.waited,
  });

  static const _Score none = _Score(
    squadPlayers: 0,
    guests: 0,
    outOfPosition: 0,
    backFromBench: 0,
    fit: 0,
    waited: 0,
  );

  /// Joueurs de l'effectif titularisés.
  final int squadPlayers;

  /// Invités titularisés pour compléter.
  final int guests;

  /// Titulaires placés hors de leurs habitudes.
  final int outOfPosition;

  /// Remplaçants du dernier match titularisés.
  final int backFromBench;

  /// Somme des affinités de chacun avec son poste.
  final double fit;

  /// Somme des compteurs banc des titulaires.
  final int waited;

  _Score operator +(_Score other) => _Score(
        squadPlayers: squadPlayers + other.squadPlayers,
        guests: guests + other.guests,
        outOfPosition: outOfPosition + other.outOfPosition,
        backFromBench: backFromBench + other.backFromBench,
        fit: fit + other.fit,
        waited: waited + other.waited,
      );

  /// Positif quand cette équipe est meilleure que [other].
  int compareTo(_Score other) {
    if (squadPlayers != other.squadPlayers) {
      return squadPlayers.compareTo(other.squadPlayers);
    }
    if (guests != other.guests) return guests.compareTo(other.guests);
    if (outOfPosition != other.outOfPosition) {
      return other.outOfPosition.compareTo(outOfPosition);
    }
    if (backFromBench != other.backFromBench) {
      return backFromBench.compareTo(other.backFromBench);
    }
    // Les sommes d'affinités ne tombent pas juste au dernier chiffre près :
    // deux répartitions équivalentes doivent être départagées par le banc,
    // pas par une erreur d'arrondi.
    if ((fit - other.fit).abs() > 1e-9) return fit.compareTo(other.fit);
    return waited.compareTo(other.waited);
  }
}
