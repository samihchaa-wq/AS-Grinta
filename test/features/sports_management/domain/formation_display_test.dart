import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/formation_display.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coordonnées réelles de matchs archivés (en pourcentage du terrain), avec
/// le poste noté par l'ancien outil : G gardien, D défense, M milieu,
/// A attaque.
typedef _Archived = (double x, double y, String line);

const List<_Archived> _archived433 = [
  (50, 93.5, 'G'),
  (10, 68.5, 'D'),
  (31.5, 74.8, 'D'),
  (68.5, 74.8, 'D'),
  (90, 68.5, 'D'),
  (18.2, 36.5, 'M'),
  (50, 43.3, 'M'),
  (81.8, 36.5, 'M'),
  (21.5, 6.9, 'A'),
  (50, 5, 'A'),
  (78.5, 6.9, 'A'),
];

const List<_Archived> _archived4231 = [
  (50, 93.5, 'G'),
  (10, 68.5, 'D'),
  (33, 74.8, 'D'),
  (67, 74.8, 'D'),
  (90, 68.5, 'D'),
  (24.8, 49, 'M'),
  (75.2, 49, 'M'),
  (10.9, 21.7, 'M'),
  (50, 30.2, 'M'),
  (89.1, 21.7, 'M'),
  (50, 5, 'A'),
];

const List<_Archived> _archived352 = [
  (50, 93.8, 'G'),
  (10, 61.3, 'D'),
  (50, 65.4, 'D'),
  (90, 61.3, 'D'),
  (10, 24.6, 'M'),
  (27.9, 30.2, 'M'),
  (50, 36.5, 'M'),
  (72.1, 30.2, 'M'),
  (90, 24.6, 'M'),
  (34.2, 5, 'A'),
  (65.8, 5, 'A'),
];

MatchCompositionEntry _entry(int index, double x, double y, bool keeper) {
  return MatchCompositionEntry(
    participantId: 'p$index',
    seasonPlayerId: 's$index',
    displayName: 'Joueur $index',
    isGoalkeeper: keeper,
    zone: MatchCompositionZone.field,
    x: x,
    y: y,
    sortOrder: index,
    availabilityStatus: 'available',
    convocationStatus: 'convoked',
    selectionStatus: 'starter',
  );
}

List<MatchCompositionEntry> _field(List<_Archived> players) => [
      for (var index = 0; index < players.length; index += 1)
        _entry(
          index,
          players[index].$1 / 100,
          players[index].$2 / 100,
          players[index].$3 == 'G',
        ),
    ];

String _lineOf(String label) {
  if (label == 'GB') return 'G';
  if (label.startsWith('D')) return 'D';
  if (label.startsWith('BU') || label == 'AG' || label == 'AD') return 'A';
  return 'M';
}

void main() {
  void expectAligned(String code, List<_Archived> archived) {
    final field = _field(archived);
    final aligned = alignFieldToFormation(code, field);
    expect(identical(aligned, field), isFalse, reason: code);

    final formation = formationForCode(code);
    final slotsByPosition = {
      for (final slot in formation.slots) slot.position: slot.label,
    };
    final labels = <String>{};
    for (var index = 0; index < aligned.length; index += 1) {
      final label =
          slotsByPosition[Offset(aligned[index].x!, aligned[index].y!)];
      expect(label, isNotNull, reason: '$code joueur $index');
      labels.add(label!);
      final archivedLine = archived[index].$3;
      // Un milieu excentré de l'archive peut devenir ailier : seuls la
      // défense et le gardien sont figés.
      if (archivedLine == 'G' || archivedLine == 'D') {
        expect(_lineOf(label), archivedLine, reason: '$code joueur $index');
      } else {
        expect(_lineOf(label), isNot(anyOf('G', 'D')),
            reason: '$code joueur $index');
      }
    }
    expect(labels, hasLength(11), reason: code);
  }

  test('les matchs archivés prennent les emplacements actuels', () {
    expectAligned('4-3-3', _archived433);
    expectAligned('4-2-3-1', _archived4231);
    expectAligned('3-5-2', _archived352);
  });

  test('le 4-3-3 des archives garde ses trois attaquants devant', () {
    final aligned = alignFieldToFormation('4-3-3', _field(_archived433));
    final formation = formationForCode('4-3-3 défensif');
    String labelOf(int index) => formation.slots
        .firstWhere(
          (slot) =>
              slot.position == Offset(aligned[index].x!, aligned[index].y!),
        )
        .label;
    expect(labelOf(8), 'AG');
    expect(labelOf(9), 'BU');
    expect(labelOf(10), 'AD');
  });

  test('un dispositif inconnu garde son dessin d’origine', () {
    final field = _field(_archived433);
    expect(identical(alignFieldToFormation('4-3-1-2', field), field), isTrue);
    expect(identical(alignFieldToFormation(null, field), field), isTrue);
  });

  test('une équipe incomplète sur l’ancienne grille suit les postes', () {
    final formation = formationForCode('4-2-1-3');
    final field = [
      for (var index = 0; index < 7; index += 1)
        _entry(
          index,
          matchSheetSlotPositions[formation.slotLabels[index]]!.dx,
          matchSheetSlotPositions[formation.slotLabels[index]]!.dy,
          index == 0,
        ),
    ];
    final aligned = alignFieldToFormation('4-2-1-3', field);
    for (var index = 0; index < 7; index += 1) {
      expect(aligned[index].x, formation.slots[index].position.dx);
      expect(aligned[index].y, formation.slots[index].position.dy);
    }
  });

  test('un placement libre éloigné des postes n’est pas déplacé', () {
    final field = [
      _entry(0, .5, .85, true),
      _entry(1, .5, .5, false),
      _entry(2, .2, .95, false),
    ];
    expect(
        identical(alignFieldToFormation('4-4-2 à plat', field), field), isTrue);
  });

  test('les statistiques et la photo du joueur sont conservées', () {
    final field = [
      for (final entry in _field(_archived433))
        entry.copyWith(goals: 2, photoUrl: 'photo.png', isMotm: true),
    ];
    for (final entry in alignFieldToFormation('4-3-3', field)) {
      expect(entry.goals, 2);
      expect(entry.photoUrl, 'photo.png');
      expect(entry.isMotm, isTrue);
    }
  });
}
