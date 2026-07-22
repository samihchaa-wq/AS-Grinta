import 'package:flutter/material.dart';

/// Un poste de la feuille de match : une étiquette courte et sa position
/// normalisée sur le terrain (x et y entre 0 et 1, l'attaque vers le haut).
class FootballFormationSlot {
  const FootballFormationSlot({
    required this.label,
    required this.position,
  });

  final String label;
  final Offset position;
}

/// Feuille de match libre : tous les postes disponibles sur le terrain.
///
/// Il n'y a plus de dispositif imposé — l'admin glisse les convoqués sur le
/// poste de son choix parmi cette grille. On n'en remplit qu'une partie
/// (les titulaires), les emplacements vides restent visibles.
const List<FootballFormationSlot> matchSheetSlots = <FootballFormationSlot>[
  // Gardien
  FootballFormationSlot(label: 'GB', position: Offset(.50, .85)),

  // Défenseurs
  FootballFormationSlot(label: 'DG', position: Offset(.10, .65)),
  FootballFormationSlot(label: 'DCG', position: Offset(.32, .70)),
  FootballFormationSlot(label: 'DC', position: Offset(.50, .72)),
  FootballFormationSlot(label: 'DCD', position: Offset(.68, .70)),
  FootballFormationSlot(label: 'DD', position: Offset(.90, .65)),

  // Milieux défensifs
  FootballFormationSlot(label: 'MDG', position: Offset(.30, .50)),
  FootballFormationSlot(label: 'MDC', position: Offset(.50, .53)),
  FootballFormationSlot(label: 'MDD', position: Offset(.70, .50)),

  // Milieux centraux & côtés
  FootballFormationSlot(label: 'MG', position: Offset(.10, .38)),
  FootballFormationSlot(label: 'MCG', position: Offset(.34, .38)),
  FootballFormationSlot(label: 'MC', position: Offset(.50, .40)),
  FootballFormationSlot(label: 'MCD', position: Offset(.66, .38)),
  FootballFormationSlot(label: 'MD', position: Offset(.90, .38)),

  // Milieux offensifs & ailiers
  FootballFormationSlot(label: 'AG', position: Offset(.12, .22)),
  FootballFormationSlot(label: 'MOG', position: Offset(.32, .25)),
  FootballFormationSlot(label: 'MOC', position: Offset(.50, .27)),
  FootballFormationSlot(label: 'MOD', position: Offset(.68, .25)),
  FootballFormationSlot(label: 'AD', position: Offset(.88, .22)),

  // Buteurs
  FootballFormationSlot(label: 'BUG', position: Offset(.35, .10)),
  FootballFormationSlot(label: 'BU', position: Offset(.50, .08)),
  FootballFormationSlot(label: 'BUD', position: Offset(.65, .10)),
];
