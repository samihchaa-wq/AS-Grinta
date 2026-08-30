import 'dart:math' as math;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter/material.dart';

/// Portée de l'affinité entre deux postes, en unités de terrain.
///
/// C'est la même géométrie que celle utilisée par « Simuler la compo » : deux
/// postes voisins d'une même ligne gardent une affinité significative, tandis
/// qu'un poste situé sur une autre ligne chute rapidement.
const double kPlayerPositionAffinityRange = .18;

/// Affinité d'un profil historique avec une position du terrain.
///
/// Les passages au but sont ignorés pour les joueurs de champ. Cette fonction
/// est la source de vérité commune à la simulation de composition et aux
/// regroupements Défenseurs / Milieux / Attaquants des matchs entre nous.
double playerPositionAffinity(
  PlayerPositionProfile? profile,
  Offset target,
) {
  if (profile == null) return 0;
  var total = 0.0;
  for (final sample in profile.samples) {
    if (sample.slotLabel == 'GB') continue;
    final origin = matchSheetSlotPositions[sample.slotLabel];
    if (origin == null) continue;
    final distance = (origin - target).distance / kPlayerPositionAffinityRange;
    total += profile.shareOf(sample.slotLabel) * math.exp(-distance * distance);
  }
  return total;
}

/// Grande ligne du terrain utilisée pour l'affichage compact des joueurs.
enum PlayerPositionBand { defender, midfielder, attacker }

/// Ligne correspondant à un poste canonique de la feuille de match.
PlayerPositionBand? playerPositionBandForSlot(String slotLabel) {
  return switch (slotLabel) {
    'DG' || 'DCG' || 'DC' || 'DCD' || 'DD' =>
      PlayerPositionBand.defender,
    'MDG' ||
    'MDC' ||
    'MDD' ||
    'MG' ||
    'MCG' ||
    'MC' ||
    'MCD' ||
    'MD' ||
    'MOG' ||
    'MOC' ||
    'MOD' =>
      PlayerPositionBand.midfielder,
    'AG' || 'AD' || 'BUG' || 'BU' || 'BUD' =>
      PlayerPositionBand.attacker,
    _ => null,
  };
}

/// Poste canonique de champ qui correspond le mieux au profil historique.
///
/// On évalue chaque poste avec exactement [playerPositionAffinity], donc un
/// joueur polyvalent est rangé selon la même notion de proximité que celle qui
/// sert à « Simuler la compo », au lieu d'entretenir des seuils parallèles.
String? bestOutfieldSlotLabel(PlayerPositionProfile profile) {
  String? bestLabel;
  var bestAffinity = 0.0;
  for (final slot in matchSheetSlots) {
    if (slot.label == 'GB') continue;
    final affinity = playerPositionAffinity(profile, slot.position);
    if (affinity > bestAffinity) {
      bestAffinity = affinity;
      bestLabel = slot.label;
    }
  }
  return bestLabel;
}

/// Grande ligne correspondant au meilleur poste du profil.
PlayerPositionBand? dominantOutfieldPositionBand(
  PlayerPositionProfile profile,
) {
  final slotLabel = bestOutfieldSlotLabel(profile);
  return slotLabel == null ? null : playerPositionBandForSlot(slotLabel);
}
