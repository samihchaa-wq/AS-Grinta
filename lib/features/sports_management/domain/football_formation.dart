import 'package:flutter/material.dart';

class FootballFormationSlot {
  const FootballFormationSlot({
    required this.label,
    required this.position,
  });

  final String label;
  final Offset position;
}

class FootballFormation {
  const FootballFormation({
    required this.code,
    required this.label,
    required this.defenderCount,
    required this.slots,
  });

  final String code;
  final String label;
  final int defenderCount;
  final List<FootballFormationSlot> slots;
}

FootballFormation _buildFormation({
  required String code,
  required String label,
  required int defenders,
  required List<_FormationLine> lines,
}) {
  final slots = <FootballFormationSlot>[
    const FootballFormationSlot(label: 'GB', position: Offset(.5, .91)),
  ];
  for (final line in lines) {
    final count = line.labels.length;
    for (var index = 0; index < count; index += 1) {
      final x = count == 1 ? .5 : .12 + (.76 * index / (count - 1));
      slots.add(
        FootballFormationSlot(
          label: line.labels[index],
          position: Offset(x, line.y),
        ),
      );
    }
  }
  assert(slots.length == 11, '$code doit contenir 11 emplacements');
  return FootballFormation(
    code: code,
    label: label,
    defenderCount: defenders,
    slots: List.unmodifiable(slots),
  );
}

class _FormationLine {
  const _FormationLine(this.y, this.labels);

  final double y;
  final List<String> labels;
}

const _def3 = _FormationLine(.73, ['DCG', 'DC', 'DCD']);
const _def4 = _FormationLine(.74, ['DG', 'DCG', 'DCD', 'DD']);
const _def5 = _FormationLine(.75, ['Dg', 'DCG', 'DC', 'DCD', 'Dd']);

final footballFormations = <FootballFormation>[
  _buildFormation(
    code: '3-1-4-2',
    label: '3-1-4-2',
    defenders: 3,
    lines: const [
      _def3,
      _FormationLine(.59, ['MDC']),
      _FormationLine(.41, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.17, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '3-4-1-2',
    label: '3-4-1-2',
    defenders: 3,
    lines: const [
      _def3,
      _FormationLine(.49, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.31, ['MOC']),
      _FormationLine(.15, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '3-4-2-1',
    label: '3-4-2-1',
    defenders: 3,
    lines: const [
      _def3,
      _FormationLine(.50, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.29, ['ATG', 'ATD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '3-5-2',
    label: '3-5-2',
    defenders: 3,
    lines: const [
      _def3,
      _FormationLine(.56, ['MDC', 'MDC']),
      _FormationLine(.38, ['MG', 'MOC', 'MD']),
      _FormationLine(.15, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '4-3-3',
    label: '4-3-3 · À plat',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.48, ['MCG', 'MC', 'MCD']),
      _FormationLine(.17, ['AG', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-3-3 (2)',
    label: '4-3-3 (2) · Holding',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.57, ['MDC']),
      _FormationLine(.40, ['MCG', 'MCD']),
      _FormationLine(.16, ['AG', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-3-3 (3)',
    label: '4-3-3 (3) · Deux MDC',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.56, ['MDC', 'MDC']),
      _FormationLine(.38, ['MC']),
      _FormationLine(.15, ['AG', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-3-3 (4)',
    label: '4-3-3 (4) · Offensif',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.51, ['MCG', 'MCD']),
      _FormationLine(.33, ['MOC']),
      _FormationLine(.14, ['AG', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-3-3 (5)',
    label: '4-3-3 (5) · Faux 9',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.49, ['MCG', 'MC', 'MCD']),
      _FormationLine(.17, ['AG', 'F9', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-1-2-1-2 (E)',
    label: '4-1-2-1-2 · Étroit',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.59, ['MDC']),
      _FormationLine(.43, ['MCG', 'MCD']),
      _FormationLine(.29, ['MOC']),
      _FormationLine(.13, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '4-1-2-1-2 (L)',
    label: '4-1-2-1-2 · Large',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.59, ['MDC']),
      _FormationLine(.43, ['MG', 'MD']),
      _FormationLine(.29, ['MOC']),
      _FormationLine(.13, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '4-1-4-1',
    label: '4-1-4-1',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.58, ['MDC']),
      _FormationLine(.38, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-2-1-3',
    label: '4-2-1-3',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.57, ['MDC', 'MDC']),
      _FormationLine(.37, ['MOC']),
      _FormationLine(.14, ['AG', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-2-2-2',
    label: '4-2-2-2',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.57, ['MDC', 'MDC']),
      _FormationLine(.34, ['MOCG', 'MOCD']),
      _FormationLine(.13, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '4-2-3-1 (E)',
    label: '4-2-3-1 · Étroit',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.57, ['MDC', 'MDC']),
      _FormationLine(.33, ['MOCG', 'MOC', 'MOCD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-2-3-1 (L)',
    label: '4-2-3-1 · Large',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.57, ['MDC', 'MDC']),
      _FormationLine(.33, ['MG', 'MOC', 'MD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-2-4',
    label: '4-2-4',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.49, ['MCG', 'MCD']),
      _FormationLine(.15, ['AG', 'BU', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '4-3-2-1',
    label: '4-3-2-1',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.50, ['MCG', 'MC', 'MCD']),
      _FormationLine(.30, ['ATG', 'ATD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-4-2',
    label: '4-4-2 · À plat',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.43, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.14, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '4-4-2 (H)',
    label: '4-4-2 · Holding',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.51, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.14, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '4-4-1-1',
    label: '4-4-1-1 · À plat',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.48, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.29, ['AT']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-4-1-1 (O)',
    label: '4-4-1-1 · Offensif',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.51, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.27, ['MOC']),
      _FormationLine(.12, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-5-1',
    label: '4-5-1 · À plat',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.45, ['MG', 'MCG', 'MC', 'MCD', 'MD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
  _buildFormation(
    code: '4-5-1 (O)',
    label: '4-5-1 · Offensif',
    defenders: 4,
    lines: const [
      _def4,
      _FormationLine(.52, ['MCG', 'MC', 'MCD']),
      _FormationLine(.31, ['MOG', 'MOD']),
      _FormationLine(.12, ['BU']),
    ],
  ),
  _buildFormation(
    code: '5-1-2-2',
    label: '5-1-2-2',
    defenders: 5,
    lines: const [
      _def5,
      _FormationLine(.57, ['MDC']),
      _FormationLine(.39, ['MCG', 'MCD']),
      _FormationLine(.14, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '5-2-1-2',
    label: '5-2-1-2',
    defenders: 5,
    lines: const [
      _def5,
      _FormationLine(.51, ['MCG', 'MCD']),
      _FormationLine(.31, ['MOC']),
      _FormationLine(.13, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '5-2-3',
    label: '5-2-3',
    defenders: 5,
    lines: const [
      _def5,
      _FormationLine(.48, ['MCG', 'MCD']),
      _FormationLine(.14, ['AG', 'BU', 'AD']),
    ],
  ),
  _buildFormation(
    code: '5-3-2',
    label: '5-3-2',
    defenders: 5,
    lines: const [
      _def5,
      _FormationLine(.46, ['MCG', 'MC', 'MCD']),
      _FormationLine(.14, ['BU', 'BU']),
    ],
  ),
  _buildFormation(
    code: '5-4-1',
    label: '5-4-1 · À plat',
    defenders: 5,
    lines: const [
      _def5,
      _FormationLine(.43, ['MG', 'MCG', 'MCD', 'MD']),
      _FormationLine(.13, ['BU']),
    ],
  ),
];

FootballFormation footballFormationByCode(String? code) {
  return footballFormations.firstWhere(
    (formation) => formation.code == code,
    orElse: () => footballFormations.firstWhere(
      (formation) => formation.code == '4-3-3',
    ),
  );
}

List<FootballFormation> footballFormationsForDefenders(int defenders) =>
    footballFormations
        .where((formation) => formation.defenderCount == defenders)
        .toList(growable: false);
