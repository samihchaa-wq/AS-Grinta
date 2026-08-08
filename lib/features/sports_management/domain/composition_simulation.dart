import 'dart:math' as math;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Portée de l'affinité entre deux postes, en unités de terrain.
///
/// Deux postes voisins d'une même ligne (DCD et DC, MOG et AG) sont distants
/// d'environ .18 : à cette distance un joueur garde un peu plus du tiers de
/// son affinité. Un poste d'une autre ligne tombe sous les 10 %, un poste de
/// l'autre bout du terrain à zéro.
const double _affinityRange = .18;

/// Affinité minimale pour qu'un glissement reste crédible.
///
/// En dessous, le joueur n'est plus placé « à côté de son poste » mais
/// n'importe où : il ne sera retenu qu'en tout dernier recours, pour éviter
/// de laisser un poste vide.
const double _plausibleAffinity = .05;

/// Pourquoi la simulation a placé un joueur à ce poste.
enum SimulatedPlacementReason {
  /// Gardien déclaré de l'effectif, placé dans les buts.
  goalkeeper,

  /// C'est le poste où le joueur a le plus joué.
  mainPosition,

  /// C'est son second poste.
  secondaryPosition,

  /// Joueur sans poste dominant, utilisé en variable d'ajustement.
  versatileAdjustment,

  /// Poste voisin de ceux qu'il occupe habituellement.
  nearbyPosition,

  /// Aucun candidat crédible : le poste aurait sinon été laissé vide.
  lastResort,
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

  /// Les joueurs placés sur le terrain.
  final List<SimulatedPlacement> placements;

  /// Les remplaçants, le prochain à devoir monter en tête.
  final List<SimulationCandidate> bench;

  /// Les postes du dispositif restés sans joueur.
  final List<FootballFormationSlot> emptySlots;

  /// Les postes que la simulation n'a pu remplir qu'en dernier recours.
  List<SimulatedPlacement> get stretchedPlacements => placements
      .where(
        (placement) => placement.reason == SimulatedPlacementReason.lastResort,
      )
      .toList(growable: false);
}

/// Compose une équipe à partir des postes de référence des joueurs.
///
/// Le dispositif n'est jamais remis en cause : la simulation se contente de
/// remplir les postes de [slots]. Les joueurs sont d'abord placés sur leur
/// poste principal, puis sur leur second poste ; les polyvalents comblent
/// ensuite les trous, et les derniers postes vides sont attribués au poste
/// voisin le plus crédible. À poste équivalent, le joueur le plus souvent
/// resté sur le banc est titularisé, pour que l'effectif tourne.
///
/// Le résultat est déterministe : les mêmes convoqués redonnent toujours la
/// même équipe.
SimulatedComposition simulateComposition({
  required List<FootballFormationSlot> slots,
  required List<SimulationCandidate> candidates,
}) {
  final placements = <String, SimulatedPlacement>{};
  final placed = <String>{};

  final goalkeeperSlots = slots.where(_isGoalkeeperSlot).toList();
  final outfieldSlots =
      slots.where((slot) => !_isGoalkeeperSlot(slot)).toList();

  // Les buts ne reviennent qu'à un gardien déclaré. Faute de gardien
  // convoqué, le poste reste vide et l'alerte existante prend le relais :
  // désigner d'office un joueur de champ serait un choix d'entraîneur.
  final goalkeepers = candidates
      .where((candidate) => candidate.isGoalkeeper && !candidate.isGuest)
      .toList()
    ..sort(_byRotationThenName);
  for (final slot in goalkeeperSlots) {
    final keeper = goalkeepers.firstWhere(
      (candidate) => !placed.contains(candidate.participantId),
      orElse: () => _noCandidate,
    );
    if (identical(keeper, _noCandidate)) break;
    placed.add(keeper.participantId);
    placements[slot.label] = SimulatedPlacement(
      slot: slot,
      candidate: keeper,
      reason: SimulatedPlacementReason.goalkeeper,
    );
  }

  // Un gardien reste un gardien : s'il n'a pas les buts, il va sur le banc
  // plutôt que de dépanner à un poste de champ.
  final outfield = candidates
      .where(
        (candidate) =>
            !candidate.isGoalkeeper &&
            !candidate.isGuest &&
            !placed.contains(candidate.participantId),
      )
      .toList();

  bool free(SimulationCandidate candidate) =>
      !placed.contains(candidate.participantId);
  bool open(FootballFormationSlot slot) => !placements.containsKey(slot.label);

  void assign(
    Iterable<_Pairing> pairings,
    SimulatedPlacementReason reason,
  ) {
    for (final pairing in pairings.toList()..sort(_byPairingRank)) {
      if (!open(pairing.slot) || !free(pairing.candidate)) continue;
      placed.add(pairing.candidate.participantId);
      placements[pairing.slot.label] = SimulatedPlacement(
        slot: pairing.slot,
        candidate: pairing.candidate,
        reason: reason,
      );
    }
  }

  Iterable<_Pairing> pairingsWhere(
    bool Function(SimulationCandidate candidate, FootballFormationSlot slot)
        matches,
  ) sync* {
    for (final slot in outfieldSlots) {
      for (final candidate in outfield) {
        if (matches(candidate, slot)) {
          yield _Pairing(
            slot: slot,
            candidate: candidate,
            affinity: _affinity(candidate, slot),
          );
        }
      }
    }
  }

  // 1. Poste principal, pour les joueurs qui en ont un.
  assign(
    pairingsWhere((candidate, slot) {
      final profile = candidate.profile;
      return profile != null &&
          !profile.isVersatile &&
          profile.mainSlotLabel == slot.label;
    }),
    SimulatedPlacementReason.mainPosition,
  );

  // 2. Second poste.
  assign(
    pairingsWhere((candidate, slot) {
      final profile = candidate.profile;
      return profile != null &&
          !profile.isVersatile &&
          profile.secondarySlotLabel == slot.label;
    }),
    SimulatedPlacementReason.secondaryPosition,
  );

  // 3. Un joueur au poste marqué dont le poste exact n'existe pas dans ce
  // dispositif glisse au poste voisin : il reste prioritaire sur les
  // polyvalents, qui ne sont là que pour combler.
  assign(
    pairingsWhere((candidate, slot) {
      final profile = candidate.profile;
      return profile != null &&
          !profile.isVersatile &&
          _affinity(candidate, slot) >= _plausibleAffinity;
    }),
    SimulatedPlacementReason.nearbyPosition,
  );

  // 4. Les couteaux suisses comblent les postes encore vides, là où ils sont
  // le plus à l'aise.
  assign(
    pairingsWhere((candidate, slot) {
      final profile = candidate.profile;
      return profile != null &&
          profile.isVersatile &&
          _affinity(candidate, slot) >= _plausibleAffinity;
    }),
    SimulatedPlacementReason.versatileAdjustment,
  );

  // 5. Dernier recours : mieux vaut un poste occupé par un joueur hors de ses
  // habitudes qu'un trou dans le dispositif. Les invités n'en sont jamais :
  // ils restent sur le banc en toutes circonstances.
  assign(
    pairingsWhere((candidate, slot) => true),
    SimulatedPlacementReason.lastResort,
  );

  final bench = candidates.where(free).toList()..sort(_byRotationThenName);

  return SimulatedComposition(
    placements: [
      for (final slot in slots)
        if (placements[slot.label] case final placement?) placement,
    ],
    bench: bench,
    emptySlots: slots.where(open).toList(growable: false),
  );
}

bool _isGoalkeeperSlot(FootballFormationSlot slot) => slot.label == 'GB';

/// Proximité d'un joueur avec un poste, d'après les postes qu'il occupe.
///
/// Les buts sont ignorés : un joueur de champ qui a dépanné au but ne doit pas
/// en devenir plus proche des postes du bas du terrain.
double _affinity(SimulationCandidate candidate, FootballFormationSlot slot) {
  final profile = candidate.profile;
  if (profile == null) return 0;
  var total = 0.0;
  for (final sample in profile.samples) {
    if (sample.slotLabel == 'GB') continue;
    final origin = matchSheetSlotPositions[sample.slotLabel];
    if (origin == null) continue;
    final distance = (origin - slot.position).distance / _affinityRange;
    total += profile.shareOf(sample.slotLabel) * math.exp(-distance * distance);
  }
  return total;
}

/// Le joueur le plus souvent resté sur le banc passe devant.
int _byRotationThenName(SimulationCandidate a, SimulationCandidate b) {
  final byBench = b.benchCount.compareTo(a.benchCount);
  if (byBench != 0) return byBench;
  return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}

int _byPairingRank(_Pairing a, _Pairing b) {
  final byBench = b.candidate.benchCount.compareTo(a.candidate.benchCount);
  if (byBench != 0) return byBench;
  final byAffinity = b.affinity.compareTo(a.affinity);
  if (byAffinity != 0) return byAffinity;
  final byName = a.candidate.displayName.toLowerCase().compareTo(
        b.candidate.displayName.toLowerCase(),
      );
  return byName != 0 ? byName : a.slot.label.compareTo(b.slot.label);
}

class _Pairing {
  const _Pairing({
    required this.slot,
    required this.candidate,
    required this.affinity,
  });

  final FootballFormationSlot slot;
  final SimulationCandidate candidate;
  final double affinity;
}

const SimulationCandidate _noCandidate = SimulationCandidate(
  participantId: '',
  displayName: '',
  benchCount: 0,
);
