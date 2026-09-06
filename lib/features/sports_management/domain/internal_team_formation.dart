import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter/material.dart';

/// Dispositif d'un match « entre nous ».
///
/// Le gardien est implicite : le code décrit uniquement les lignes de joueurs
/// de champ. Ainsi « 2-3-1 » correspond à 7 joueurs au total (1 GB + 6 joueurs
/// de champ). Chaque dispositif expose exactement autant d'emplacements que le
/// nombre de joueurs qu'il accepte ; il n'existe donc aucun banc dans la
/// composition finale.
class InternalTeamFormation {
  const InternalTeamFormation({
    required this.code,
    required this.outfieldLines,
  });

  final String code;
  final List<int> outfieldLines;

  int get playerCount =>
      1 + outfieldLines.fold<int>(0, (total, count) => total + count);

  List<FootballFormationSlot> get slots {
    final result = <FootballFormationSlot>[
      const FootballFormationSlot(label: 'GB', position: Offset(.50, .86)),
    ];
    if (outfieldLines.isEmpty) return result;

    for (var lineIndex = 0; lineIndex < outfieldLines.length; lineIndex += 1) {
      final count = outfieldLines[lineIndex];
      final y = _lineY(lineIndex, outfieldLines.length);
      final role = _lineRole(lineIndex, outfieldLines.length);
      final labels = _labelsFor(role, count);
      for (var index = 0; index < count; index += 1) {
        result.add(
          FootballFormationSlot(
            label: labels[index],
            position: Offset(_lineX(index, count), y),
          ),
        );
      }
    }
    return result;
  }

  bool containsSlot(String? label) =>
      label != null && slots.any((slot) => slot.label == label);
}

enum _InternalLineRole { defense, midfield, attack }

_InternalLineRole _lineRole(int index, int lineCount) {
  if (lineCount == 1) return _InternalLineRole.midfield;
  if (index == 0) return _InternalLineRole.defense;
  if (index == lineCount - 1) return _InternalLineRole.attack;
  return _InternalLineRole.midfield;
}

double _lineY(int index, int lineCount) {
  if (lineCount == 1) return .40;
  const defenseY = .68;
  const attackY = .14;
  final step = (defenseY - attackY) / (lineCount - 1);
  return defenseY - step * index;
}

double _lineX(int index, int count) {
  if (count <= 1) return .50;
  const left = .14;
  const right = .86;
  return left + (right - left) * index / (count - 1);
}

List<String> _labelsFor(_InternalLineRole role, int count) {
  final labels = switch (role) {
    _InternalLineRole.defense => switch (count) {
        1 => const ['DC'],
        2 => const ['DCG', 'DCD'],
        3 => const ['DCG', 'DC', 'DCD'],
        4 => const ['DG', 'DCG', 'DCD', 'DD'],
        5 => const ['DG', 'DCG', 'DC', 'DCD', 'DD'],
        _ => List.generate(count, (index) => 'D${index + 1}'),
      },
    _InternalLineRole.midfield => switch (count) {
        1 => const ['MC'],
        2 => const ['MCG', 'MCD'],
        3 => const ['MCG', 'MC', 'MCD'],
        4 => const ['MG', 'MCG', 'MCD', 'MD'],
        5 => const ['MG', 'MCG', 'MC', 'MCD', 'MD'],
        _ => List.generate(count, (index) => 'M${index + 1}'),
      },
    _InternalLineRole.attack => switch (count) {
        1 => const ['BU'],
        2 => const ['BUG', 'BUD'],
        3 => const ['AG', 'BU', 'AD'],
        4 => const ['AG', 'BUG', 'BUD', 'AD'],
        5 => const ['AG', 'AIG', 'BU', 'AID', 'AD'],
        _ => List.generate(count, (index) => 'A${index + 1}'),
      },
  };
  return labels;
}

/// Catalogue adapté au nombre exact de joueurs d'une équipe.
///
/// Les compositions à un ou deux joueurs n'ont naturellement qu'un seul
/// dispositif crédible. À partir de trois joueurs, plusieurs variantes sont
/// proposées pour que l'administrateur reste toujours décisionnaire.
const Map<int, List<InternalTeamFormation>> internalTeamFormationsByPlayerCount = {
  1: [InternalTeamFormation(code: 'GB', outfieldLines: [])],
  2: [InternalTeamFormation(code: '1', outfieldLines: [1])],
  3: [
    InternalTeamFormation(code: '1-1', outfieldLines: [1, 1]),
    InternalTeamFormation(code: '2', outfieldLines: [2]),
  ],
  4: [
    InternalTeamFormation(code: '2-1', outfieldLines: [2, 1]),
    InternalTeamFormation(code: '1-2', outfieldLines: [1, 2]),
  ],
  5: [
    InternalTeamFormation(code: '2-1-1', outfieldLines: [2, 1, 1]),
    InternalTeamFormation(code: '1-2-1', outfieldLines: [1, 2, 1]),
    InternalTeamFormation(code: '2-2', outfieldLines: [2, 2]),
  ],
  6: [
    InternalTeamFormation(code: '2-2-1', outfieldLines: [2, 2, 1]),
    InternalTeamFormation(code: '2-1-2', outfieldLines: [2, 1, 2]),
    InternalTeamFormation(code: '1-3-1', outfieldLines: [1, 3, 1]),
  ],
  7: [
    InternalTeamFormation(code: '2-3-1', outfieldLines: [2, 3, 1]),
    InternalTeamFormation(code: '3-2-1', outfieldLines: [3, 2, 1]),
    InternalTeamFormation(code: '2-2-2', outfieldLines: [2, 2, 2]),
  ],
  8: [
    InternalTeamFormation(code: '3-3-1', outfieldLines: [3, 3, 1]),
    InternalTeamFormation(code: '2-3-2', outfieldLines: [2, 3, 2]),
    InternalTeamFormation(code: '3-2-2', outfieldLines: [3, 2, 2]),
  ],
  9: [
    InternalTeamFormation(code: '3-3-2', outfieldLines: [3, 3, 2]),
    InternalTeamFormation(code: '3-2-3', outfieldLines: [3, 2, 3]),
    InternalTeamFormation(code: '2-3-3', outfieldLines: [2, 3, 3]),
  ],
  10: [
    InternalTeamFormation(code: '3-4-2', outfieldLines: [3, 4, 2]),
    InternalTeamFormation(code: '4-3-2', outfieldLines: [4, 3, 2]),
    InternalTeamFormation(code: '4-2-3', outfieldLines: [4, 2, 3]),
    InternalTeamFormation(code: '3-3-3', outfieldLines: [3, 3, 3]),
  ],
  11: [
    InternalTeamFormation(code: '4-4-2', outfieldLines: [4, 4, 2]),
    InternalTeamFormation(code: '4-3-3', outfieldLines: [4, 3, 3]),
    InternalTeamFormation(code: '4-2-3-1', outfieldLines: [4, 2, 3, 1]),
    InternalTeamFormation(code: '3-5-2', outfieldLines: [3, 5, 2]),
    InternalTeamFormation(code: '3-4-3', outfieldLines: [3, 4, 3]),
    InternalTeamFormation(code: '5-3-2', outfieldLines: [5, 3, 2]),
  ],
};

List<InternalTeamFormation> internalFormationsForPlayerCount(int playerCount) =>
    internalTeamFormationsByPlayerCount[playerCount] ?? const [];

InternalTeamFormation? internalFormationByCode({
  required int playerCount,
  required String? code,
}) {
  if (code == null) return null;
  for (final formation in internalFormationsForPlayerCount(playerCount)) {
    if (formation.code == code) return formation;
  }
  return null;
}
