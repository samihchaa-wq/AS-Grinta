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

/// Position normalisée de chaque poste, indexée par étiquette.
final Map<String, Offset> _slotPositions = {
  for (final slot in matchSheetSlots) slot.label: slot.position,
};

/// Un dispositif tactique : un nom court, sa ligne défensive (3, 4 ou 5) et
/// la liste ordonnée de ses 11 postes.
class FootballFormation {
  const FootballFormation({
    required this.code,
    required this.defenderLine,
    required this.slotLabels,
  });

  /// Nom court affiché dans le menu (ex. « 4-2-1-3 »).
  final String code;

  /// Nombre de défenseurs (3, 4 ou 5) — sert à regrouper le menu.
  final int defenderLine;

  /// Les 11 postes du dispositif, dans l'ordre GB → attaquants.
  final List<String> slotLabels;

  /// Les postes positionnés sur le terrain pour ce dispositif.
  List<FootballFormationSlot> get slots => [
        for (final label in slotLabels)
          FootballFormationSlot(
            label: label,
            position: _slotPositions[label] ?? const Offset(.5, .5),
          ),
      ];
}

/// Dispositif utilisé par défaut à la création d'une composition.
const String kDefaultFormationCode = '4-2-1-3';

/// Catalogue des dispositifs proposés dans le menu déroulant.
const List<FootballFormation> footballFormations = <FootballFormation>[
  // ---- 4 défenseurs ----
  FootballFormation(
    code: '4-4-2 à plat',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MG', 'MCG', 'MCD', 'MD',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '4-4-2 losange',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDC', 'MCG', 'MCD', 'MOC',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '4-2-3-1',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDG', 'MDD', 'MOG', 'MOC',
        'MOD', 'BU'],
  ),
  FootballFormation(
    code: '4-3-3 défensif',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDC', 'MCG', 'MCD', 'AG',
        'BU', 'AD'],
  ),
  FootballFormation(
    code: '4-3-3 offensif',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MCG', 'MOC', 'MCD', 'AG',
        'BU', 'AD'],
  ),
  FootballFormation(
    code: '4-3-3 faux neuf',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDC', 'MCG', 'MCD', 'AG',
        'MOC', 'AD'],
  ),
  FootballFormation(
    code: '4-2-1-3',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDG', 'MDD', 'MOC', 'AG',
        'BU', 'AD'],
  ),
  FootballFormation(
    code: '4-3-2-1 sapin',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MCG', 'MC', 'MCD', 'MOG',
        'MOD', 'BU'],
  ),
  FootballFormation(
    code: '4-2-2-2',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDG', 'MDD', 'MOG', 'MOD',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '4-4-1-1',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MG', 'MCG', 'MCD', 'MD',
        'MOC', 'BU'],
  ),
  FootballFormation(
    code: '4-1-4-1',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDC', 'MG', 'MCG', 'MCD',
        'MD', 'BU'],
  ),
  FootballFormation(
    code: '4-1-3-2',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDC', 'MG', 'MOC', 'MD',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '4-5-1',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MG', 'MCG', 'MC', 'MCD',
        'MD', 'BU'],
  ),
  FootballFormation(
    code: '4-2-4',
    defenderLine: 4,
    slotLabels: ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MCG', 'MCD', 'AG', 'BUG',
        'BUD', 'AD'],
  ),
  // ---- 3 défenseurs ----
  FootballFormation(
    code: '3-5-2',
    defenderLine: 3,
    slotLabels: ['GB', 'DCG', 'DC', 'DCD', 'MG', 'MCG', 'MC', 'MCD', 'MD',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '3-4-3',
    defenderLine: 3,
    slotLabels: ['GB', 'DCG', 'DC', 'DCD', 'MG', 'MCG', 'MCD', 'MD', 'AG',
        'BU', 'AD'],
  ),
  FootballFormation(
    code: '3-4-1-2',
    defenderLine: 3,
    slotLabels: ['GB', 'DCG', 'DC', 'DCD', 'MG', 'MCG', 'MCD', 'MD', 'MOC',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '3-4-2-1',
    defenderLine: 3,
    slotLabels: ['GB', 'DCG', 'DC', 'DCD', 'MG', 'MCG', 'MCD', 'MD', 'MOG',
        'MOD', 'BU'],
  ),
  FootballFormation(
    code: '3-1-4-2',
    defenderLine: 3,
    slotLabels: ['GB', 'DCG', 'DC', 'DCD', 'MDC', 'MG', 'MCG', 'MCD', 'MD',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '3-3-1-3',
    defenderLine: 3,
    slotLabels: ['GB', 'DCG', 'DC', 'DCD', 'MCG', 'MC', 'MCD', 'MOC', 'AG',
        'BU', 'AD'],
  ),
  // ---- 5 défenseurs ----
  FootballFormation(
    code: '5-3-2',
    defenderLine: 5,
    slotLabels: ['GB', 'DG', 'DCG', 'DC', 'DCD', 'DD', 'MCG', 'MC', 'MCD',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '5-2-3',
    defenderLine: 5,
    slotLabels: ['GB', 'DG', 'DCG', 'DC', 'DCD', 'DD', 'MCG', 'MCD', 'AG',
        'BU', 'AD'],
  ),
  FootballFormation(
    code: '5-4-1',
    defenderLine: 5,
    slotLabels: ['GB', 'DG', 'DCG', 'DC', 'DCD', 'DD', 'MG', 'MCG', 'MCD',
        'MD', 'BU'],
  ),
  FootballFormation(
    code: '5-2-1-2',
    defenderLine: 5,
    slotLabels: ['GB', 'DG', 'DCG', 'DC', 'DCD', 'DD', 'MCG', 'MCD', 'MOC',
        'BUG', 'BUD'],
  ),
  FootballFormation(
    code: '5-3-1-1',
    defenderLine: 5,
    slotLabels: ['GB', 'DG', 'DCG', 'DC', 'DCD', 'DD', 'MCG', 'MC', 'MCD',
        'MOC', 'BU'],
  ),
];

/// Retrouve un dispositif par son code, ou le dispositif par défaut.
FootballFormation formationForCode(String? code) {
  for (final formation in footballFormations) {
    if (formation.code == code) return formation;
  }
  return footballFormations.firstWhere(
    (formation) => formation.code == kDefaultFormationCode,
  );
}
