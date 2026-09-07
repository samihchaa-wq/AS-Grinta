import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter/material.dart';

/// Dispositif unique d'une équipe de match « entre nous ».
///
/// Le nombre de joueurs détermine entièrement le dispositif : l'admin ne
/// choisit plus entre plusieurs variantes. Les coordonnées sont dessinées
/// individuellement pour chaque format afin d'éviter l'effet de grille
/// générique et de conserver de vraies distances tactiques entre les lignes.
class InternalTeamFormation {
  const InternalTeamFormation({
    required this.code,
    required this.slots,
  });

  final String code;
  final List<FootballFormationSlot> slots;

  int get playerCount => slots.length;

  bool containsSlot(String? label) =>
      label != null && slots.any((slot) => slot.label == label);
}

const FootballFormationSlot _gb = FootballFormationSlot(
  label: 'GB',
  position: Offset(.50, .85),
);

const Map<int, InternalTeamFormation> internalDefaultFormations = {
  1: InternalTeamFormation(
    code: 'GB',
    slots: [_gb],
  ),
  2: InternalTeamFormation(
    code: '1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'MC', position: Offset(.50, .38)),
    ],
  ),
  3: InternalTeamFormation(
    code: '1-1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DC', position: Offset(.50, .64)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .23)),
    ],
  ),
  4: InternalTeamFormation(
    code: '2-1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DCG', position: Offset(.34, .65)),
      FootballFormationSlot(label: 'DCD', position: Offset(.66, .65)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .23)),
    ],
  ),
  5: InternalTeamFormation(
    code: '1-2-1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DC', position: Offset(.50, .67)),
      FootballFormationSlot(label: 'MCG', position: Offset(.34, .44)),
      FootballFormationSlot(label: 'MCD', position: Offset(.66, .44)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .22)),
    ],
  ),
  6: InternalTeamFormation(
    code: '2-2-1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DCG', position: Offset(.34, .66)),
      FootballFormationSlot(label: 'DCD', position: Offset(.66, .66)),
      FootballFormationSlot(label: 'MCG', position: Offset(.34, .44)),
      FootballFormationSlot(label: 'MCD', position: Offset(.66, .44)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .22)),
    ],
  ),
  7: InternalTeamFormation(
    code: '2-3-1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DCG', position: Offset(.34, .67)),
      FootballFormationSlot(label: 'DCD', position: Offset(.66, .67)),
      FootballFormationSlot(label: 'MCG', position: Offset(.24, .44)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .42)),
      FootballFormationSlot(label: 'MCD', position: Offset(.76, .44)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .21)),
    ],
  ),
  8: InternalTeamFormation(
    code: '3-3-1',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DCG', position: Offset(.24, .66)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .69)),
      FootballFormationSlot(label: 'DCD', position: Offset(.76, .66)),
      FootballFormationSlot(label: 'MCG', position: Offset(.24, .43)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .42)),
      FootballFormationSlot(label: 'MCD', position: Offset(.76, .43)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .21)),
    ],
  ),
  9: InternalTeamFormation(
    code: '3-3-2',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DCG', position: Offset(.24, .66)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .69)),
      FootballFormationSlot(label: 'DCD', position: Offset(.76, .66)),
      FootballFormationSlot(label: 'MCG', position: Offset(.24, .43)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .42)),
      FootballFormationSlot(label: 'MCD', position: Offset(.76, .43)),
      FootballFormationSlot(label: 'BUG', position: Offset(.38, .20)),
      FootballFormationSlot(label: 'BUD', position: Offset(.62, .20)),
    ],
  ),
  10: InternalTeamFormation(
    code: '3-4-2',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DCG', position: Offset(.24, .66)),
      FootballFormationSlot(label: 'DC', position: Offset(.50, .69)),
      FootballFormationSlot(label: 'DCD', position: Offset(.76, .66)),
      FootballFormationSlot(label: 'MG', position: Offset(.15, .43)),
      FootballFormationSlot(label: 'MCG', position: Offset(.38, .45)),
      FootballFormationSlot(label: 'MCD', position: Offset(.62, .45)),
      FootballFormationSlot(label: 'MD', position: Offset(.85, .43)),
      FootballFormationSlot(label: 'BUG', position: Offset(.38, .20)),
      FootballFormationSlot(label: 'BUD', position: Offset(.62, .20)),
    ],
  ),
  11: InternalTeamFormation(
    code: '4-3-3',
    slots: [
      _gb,
      FootballFormationSlot(label: 'DG', position: Offset(.12, .64)),
      FootballFormationSlot(label: 'DCG', position: Offset(.36, .69)),
      FootballFormationSlot(label: 'DCD', position: Offset(.64, .69)),
      FootballFormationSlot(label: 'DD', position: Offset(.88, .64)),
      FootballFormationSlot(label: 'MCG', position: Offset(.30, .43)),
      FootballFormationSlot(label: 'MC', position: Offset(.50, .46)),
      FootballFormationSlot(label: 'MCD', position: Offset(.70, .43)),
      FootballFormationSlot(label: 'AG', position: Offset(.18, .20)),
      FootballFormationSlot(label: 'BU', position: Offset(.50, .16)),
      FootballFormationSlot(label: 'AD', position: Offset(.82, .20)),
    ],
  ),
};

InternalTeamFormation? internalDefaultFormationForPlayerCount(int playerCount) {
  if (playerCount <= 0) return null;
  final onFieldCount = playerCount > 11 ? 11 : playerCount;
  return internalDefaultFormations[onFieldCount];
}

/// Compatibilité avec les appels existants : il n'existe désormais qu'une
/// seule option, déterminée par le nombre de joueurs.
List<InternalTeamFormation> internalFormationsForPlayerCount(int playerCount) {
  final formation = internalDefaultFormationForPlayerCount(playerCount);
  return formation == null ? const [] : [formation];
}

InternalTeamFormation? internalFormationByCode({
  required int playerCount,
  required String? code,
}) {
  final formation = internalDefaultFormationForPlayerCount(playerCount);
  if (formation == null || formation.code != code) return null;
  return formation;
}
