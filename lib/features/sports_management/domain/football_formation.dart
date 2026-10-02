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
final Map<String, Offset> matchSheetSlotPositions = {
  for (final slot in matchSheetSlots) slot.label: slot.position,
};

/// Le poste de la feuille de match le plus proche d'une position.
///
/// Le terrain accepte des placements libres : ramener une position à son
/// poste le plus proche est ce qui permet de lire un historique de
/// compositions comme une suite de postes occupés.
///
/// Chaque dispositif dessine ses postes à sa façon (un milieu offensif de
/// 4-2-3-1 est plus excentré que celui d'un 4-2-2-2) : la recherche porte donc
/// sur la grille de référence et sur les emplacements de tous les
/// dispositifs. Un joueur posé sur un emplacement retrouve ainsi toujours le
/// nom de ce poste, même quand cet emplacement est plus près d'un autre poste
/// de la grille de référence.
String nearestMatchSheetSlotLabel(Offset position) {
  var closest = matchSheetSlots.first;
  var best = double.infinity;
  for (final slot in _knownSlotPositions) {
    final distance = (slot.position - position).distanceSquared;
    if (distance < best) {
      best = distance;
      closest = slot;
    }
  }
  return closest.label;
}

/// Grille de référence suivie des emplacements propres à chaque dispositif.
final List<FootballFormationSlot> _knownSlotPositions = [
  ...matchSheetSlots,
  for (final formation in footballFormations) ...formation.slots,
];

/// Un dispositif tactique : un nom court, sa ligne défensive (3, 4 ou 5) et
/// ses 11 postes, chacun à l'emplacement qu'il occupe dans CE dispositif.
///
/// Les emplacements sont dessinés dispositif par dispositif et non repris
/// d'une grille commune : une grille unique obligeait par exemple les trois
/// milieux d'un 3-5-2 à se chevaucher, ou empilait les milieux offensifs
/// d'un 4-2-2-2 juste sous les attaquants. Ils respectent trois règles,
/// vérifiées par les tests :
/// - deux joueurs d'un même dispositif ne se chevauchent pas sur un écran de
///   téléphone ;
/// - personne n'est collé au bord du terrain ;
/// - chaque poste reste à moins de 0,11 de son ancienne place, pour que les
///   compositions déjà enregistrées s'affichent toujours au bon endroit.
class FootballFormation {
  const FootballFormation({
    required this.code,
    required this.defenderLine,
    required this.slots,
  });

  /// Nom court affiché dans le menu (ex. « 4-2-1-3 »).
  final String code;

  /// Nombre de défenseurs (3, 4 ou 5) — sert à regrouper le menu.
  final int defenderLine;

  /// Les 11 postes du dispositif, dans l'ordre GB → attaquants.
  final List<FootballFormationSlot> slots;

  /// Les étiquettes des postes, dans le même ordre que [slots].
  List<String> get slotLabels => [for (final slot in slots) slot.label];
}

/// Dispositif utilisé par défaut à la création d'une composition.
const String kDefaultFormationCode = '4-2-1-3';

/// Catalogue des dispositifs proposés dans le menu déroulant.
///
/// Repères verticaux (l'attaque vers le haut) : gardien à 0,89, défense
/// entre 0,63 et 0,73, sentinelle à 0,55, milieux autour de 0,40-0,48,
/// meneurs autour de 0,30, ailiers à 0,23 et pointes à 0,13-0,14.
const List<FootballFormation> footballFormations = <FootballFormation>[
  // ---- 4 défenseurs ----
  FootballFormation(
    code: '4-4-2 à plat',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .42)),
      FootballFormationSlot(label: 'MCG', position: Offset(.38, .44)),
      FootballFormationSlot(label: 'MCD', position: Offset(.62, .44)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .42)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '4-4-2 losange',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDC', position: Offset(.50, .55)),
      FootballFormationSlot(label: 'MCG', position: Offset(.28, .43)),
      FootballFormationSlot(label: 'MCD', position: Offset(.72, .43)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .31)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '4-2-3-1',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDG', position: Offset(.36, .55)),
      FootballFormationSlot(label: 'MDD', position: Offset(.64, .55)),
      FootballFormationSlot(label: 'MOG', position: Offset(.25, .31)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .32)),
      FootballFormationSlot(label: 'MOD', position: Offset(.75, .31)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
    ],
  ),
  FootballFormation(
    code: '4-3-3 défensif',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDC', position: Offset(.50, .55)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .40)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .40)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  FootballFormation(
    code: '4-3-3 offensif',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .46)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .33)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .46)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  FootballFormation(
    code: '4-3-3 faux neuf',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDC', position: Offset(.50, .55)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .40)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .40)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .22)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  FootballFormation(
    code: '4-2-1-3',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDG', position: Offset(.36, .55)),
      FootballFormationSlot(label: 'MDD', position: Offset(.64, .55)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .36)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  FootballFormation(
    code: '4-3-2-1 sapin',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MCG', position: Offset(.28, .45)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .47)),
      FootballFormationSlot(label: 'MCD', position: Offset(.72, .45)),
      FootballFormationSlot(label: 'MOG', position: Offset(.32, .29)),
      FootballFormationSlot(label: 'MOD', position: Offset(.68, .29)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .13)),
    ],
  ),
  FootballFormation(
    code: '4-2-2-2',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDG', position: Offset(.36, .55)),
      FootballFormationSlot(label: 'MDD', position: Offset(.64, .55)),
      FootballFormationSlot(label: 'MOG', position: Offset(.26, .31)),
      FootballFormationSlot(label: 'MOD', position: Offset(.74, .31)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '4-4-1-1',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .43)),
      FootballFormationSlot(label: 'MCG', position: Offset(.37, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.63, .46)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .43)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .30)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .13)),
    ],
  ),
  FootballFormation(
    code: '4-1-4-1',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDC', position: Offset(.50, .55)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .37)),
      FootballFormationSlot(label: 'MCG', position: Offset(.36, .39)),
      FootballFormationSlot(label: 'MCD', position: Offset(.64, .39)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .37)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
    ],
  ),
  FootballFormation(
    code: '4-1-3-2',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MDC', position: Offset(.50, .55)),
      FootballFormationSlot(label: 'MG', position: Offset(.14, .38)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .35)),
      FootballFormationSlot(label: 'MD', position: Offset(.86, .38)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '4-5-1',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MG', position: Offset(.10, .40)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .44)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .44)),
      FootballFormationSlot(label: 'MD', position: Offset(.90, .40)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
    ],
  ),
  FootballFormation(
    code: '4-2-4',
    defenderLine: 4,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.12, .67)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .72)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .72)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .67)),
      FootballFormationSlot(label: 'MCG', position: Offset(.38, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.62, .46)),
      FootballFormationSlot(label: 'AG', position: Offset(.14, .24)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.86, .24)),
    ],
  ),
  // ---- 3 défenseurs ----
  FootballFormation(
    code: '3-5-2',
    defenderLine: 3,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DCG', position: Offset(.26, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.74, .71)),
      FootballFormationSlot(label: 'MG', position: Offset(.10, .40)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .44)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .47)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .44)),
      FootballFormationSlot(label: 'MD', position: Offset(.90, .40)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '3-4-3',
    defenderLine: 3,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DCG', position: Offset(.26, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.74, .71)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .42)),
      FootballFormationSlot(label: 'MCG', position: Offset(.38, .44)),
      FootballFormationSlot(label: 'MCD', position: Offset(.62, .44)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .42)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  FootballFormation(
    code: '3-4-1-2',
    defenderLine: 3,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DCG', position: Offset(.26, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.74, .71)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .44)),
      FootballFormationSlot(label: 'MCG', position: Offset(.32, .47)),
      FootballFormationSlot(label: 'MCD', position: Offset(.68, .47)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .44)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .31)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '3-4-2-1',
    defenderLine: 3,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DCG', position: Offset(.26, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.74, .71)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .44)),
      FootballFormationSlot(label: 'MCG', position: Offset(.38, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.62, .46)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .44)),
      FootballFormationSlot(label: 'MOG', position: Offset(.30, .28)),
      FootballFormationSlot(label: 'MOD', position: Offset(.70, .28)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .13)),
    ],
  ),
  FootballFormation(
    code: '3-1-4-2',
    defenderLine: 3,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DCG', position: Offset(.26, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.74, .71)),
      FootballFormationSlot(label: 'MDC', position: Offset(.50, .55)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .38)),
      FootballFormationSlot(label: 'MCG', position: Offset(.36, .39)),
      FootballFormationSlot(label: 'MCD', position: Offset(.64, .39)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .38)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '3-3-1-3',
    defenderLine: 3,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DCG', position: Offset(.26, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.74, .71)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .45)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .48)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .45)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .31)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  // ---- 5 défenseurs ----
  FootballFormation(
    code: '5-3-2',
    defenderLine: 5,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.10, .63)),
      FootballFormationSlot(label: 'DCG', position: Offset(.30, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.70, .71)),
      FootballFormationSlot(label: 'DD', position: Offset(.90, .63)),
      FootballFormationSlot(label: 'MCG', position: Offset(.28, .43)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.72, .43)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '5-2-3',
    defenderLine: 5,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.10, .63)),
      FootballFormationSlot(label: 'DCG', position: Offset(.30, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.70, .71)),
      FootballFormationSlot(label: 'DD', position: Offset(.90, .63)),
      FootballFormationSlot(label: 'MCG', position: Offset(.36, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.64, .46)),
      FootballFormationSlot(label: 'AG', position: Offset(.15, .23)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
      FootballFormationSlot(label: 'AD', position: Offset(.85, .23)),
    ],
  ),
  FootballFormation(
    code: '5-4-1',
    defenderLine: 5,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.10, .63)),
      FootballFormationSlot(label: 'DCG', position: Offset(.30, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.70, .71)),
      FootballFormationSlot(label: 'DD', position: Offset(.90, .63)),
      FootballFormationSlot(label: 'MG', position: Offset(.12, .40)),
      FootballFormationSlot(label: 'MCG', position: Offset(.37, .44)),
      FootballFormationSlot(label: 'MCD', position: Offset(.63, .44)),
      FootballFormationSlot(label: 'MD', position: Offset(.88, .40)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
    ],
  ),
  FootballFormation(
    code: '5-2-1-2',
    defenderLine: 5,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.10, .63)),
      FootballFormationSlot(label: 'DCG', position: Offset(.30, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.70, .71)),
      FootballFormationSlot(label: 'DD', position: Offset(.90, .63)),
      FootballFormationSlot(label: 'MCG', position: Offset(.34, .48)),
      FootballFormationSlot(label: 'MCD', position: Offset(.66, .48)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .31)),
      FootballFormationSlot(label: 'BUG', position: Offset(.37, .14)),
      FootballFormationSlot(label: 'BUD', position: Offset(.63, .14)),
    ],
  ),
  FootballFormation(
    code: '5-3-1-1',
    defenderLine: 5,
    slots: [
      FootballFormationSlot(label: 'GB', position: Offset(.50, .89)),
      FootballFormationSlot(label: 'DG', position: Offset(.10, .63)),
      FootballFormationSlot(label: 'DCG', position: Offset(.30, .71)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .73)),
      FootballFormationSlot(label: 'DCD', position: Offset(.70, .71)),
      FootballFormationSlot(label: 'DD', position: Offset(.90, .63)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .45)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .48)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .45)),
      FootballFormationSlot(label: 'MOC', position: Offset(.50, .31)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .14)),
    ],
  ),
];

/// Codes historiques encore présents dans les compositions enregistrées.
///
/// Les alias ne modifient jamais les coordonnées sauvegardées : ils servent
/// uniquement à retrouver le dispositif équivalent dans le catalogue actuel.
const Map<String, String> _legacyFormationAliases = <String, String>{
  '4-4-2': '4-4-2 à plat',
};

/// Retourne le dispositif correspondant à [code] sans fallback silencieux.
///
/// À utiliser lors de la lecture d'une composition existante : un ancien code
/// connu est traduit via [_legacyFormationAliases], tandis qu'un code inconnu
/// reste inconnu au lieu d'être pris pour le dispositif par défaut.
FootballFormation? formationForCodeOrNull(String? code) {
  final raw = code?.trim();
  if (raw == null || raw.isEmpty) return null;
  final canonical = _legacyFormationAliases[raw] ?? raw;
  for (final formation in footballFormations) {
    if (formation.code == canonical) return formation;
  }
  return null;
}

/// Retrouve un dispositif par son code, ou le dispositif par défaut.
///
/// Ce fallback reste utile pour une nouvelle composition sans dispositif.
/// Pour une composition déjà enregistrée, préférer [formationForCodeOrNull]
/// afin de ne jamais confondre un code historique inconnu avec le défaut.
FootballFormation formationForCode(String? code) {
  return formationForCodeOrNull(code) ??
      footballFormations.firstWhere(
        (formation) => formation.code == kDefaultFormationCode,
      );
}
