import 'package:as_grinta/features/sports_management/domain/composition_presentation_plan.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un joueur par poste du dispositif, nommé d'après son poste.
List<PresentationPerson> _team(String code) => [
      for (final slot in formationForCode(code).slots)
        PresentationPerson(
          id: slot.label,
          name: slot.label,
          position: slot.position,
          isGoalkeeper: slot.label == 'GB',
        ),
    ];

List<PresentationPerson> _people(int count, String prefix) => [
      for (var index = 0; index < count; index++)
        PresentationPerson(id: '$prefix$index', name: '$prefix$index'),
    ];

List<List<String>> _rows(PresentationLine line) => [
      for (final row in line.rows) [for (final person in row) person.name],
    ];

void main() {
  test('un 4-2-1-3 donne un écran par ligne, dans l’ordre du terrain', () {
    final plan = CompositionPresentationPlan.build(
      field: _team('4-2-1-3'),
      bench: _people(2, 'R'),
      coach: const PresentationPerson(id: 'coach', name: 'Philippe'),
    );

    expect(plan.lines.map((line) => line.kind), [
      PresentationLineKind.goalkeeper,
      PresentationLineKind.defenders,
      PresentationLineKind.midfielders,
      PresentationLineKind.attackers,
      PresentationLineKind.bench,
      PresentationLineKind.coach,
    ]);
    expect(plan.lines.map((line) => line.label), [
      'Gardien',
      'Défenseurs',
      'Milieux',
      'Attaquants',
      'Remplaçants',
      'Coach',
    ]);
    // Chaque écran range ses photos de gauche à droite comme sur le terrain :
    // chacune descend tout droit vers sa place, sans croiser les autres.
    expect(_rows(plan.lines[1]), [
      ['DG', 'DCG', 'DCD', 'DD'],
    ]);
    expect(_rows(plan.lines[2]), [
      ['MDG', 'MOC', 'MDD'],
    ]);
    expect(_rows(plan.lines[3]), [
      ['AG', 'BU', 'AD'],
    ]);
    expect(plan.hasPlayers, isTrue);
  });

  test('un 3-4-2-1 suit ses vraies lignes, pas des chiffres figés', () {
    final plan = CompositionPresentationPlan.build(field: _team('3-4-2-1'));

    expect(plan.lines.map((line) => line.label), [
      'Gardien',
      'Défenseurs',
      'Milieux',
      'Attaquant',
    ]);
    expect(_rows(plan.lines[1]), [
      ['DCG', 'DC', 'DCD'],
    ]);
    // Six milieux : les offensifs au-dessus, puis les quatre autres.
    expect(_rows(plan.lines[2]), [
      ['MOG', 'MOD'],
      ['MG', 'MCG', 'MCD', 'MD'],
    ]);
    expect(_rows(plan.lines[3]), [
      ['BU'],
    ]);
  });

  test('chronologie : accroche, un écran toutes les deux secondes', () {
    final full = CompositionPresentationPlan.build(
      field: _team('4-2-1-3'),
      bench: _people(2, 'R'),
      coach: const PresentationPerson(id: 'coach', name: 'Philippe'),
    );
    expect(full.lines.map((line) => line.start), [
      2.8,
      4.8,
      6.8,
      8.8,
      10.8,
      12.8,
    ]);
    expect(full.moveStart, closeTo(15.0, 1e-9));
    expect(full.flatAt, closeTo(16.6, 1e-9));
    expect(full.duration, closeTo(17.4, 1e-9));

    // Sans banc ni coach, pas d'écran vide : la vidéo est plus courte.
    final short = CompositionPresentationPlan.build(field: _team('4-2-1-3'));
    expect(short.lines, hasLength(4));
    expect(short.duration, closeTo(13.4, 1e-9));
  });

  test('banc : singulier pour un seul, rangées équilibrées au-delà de 4', () {
    final one = CompositionPresentationPlan.build(
      field: _team('4-2-1-3'),
      bench: _people(1, 'R'),
    );
    expect(one.lines.last.label, 'Remplaçant');

    final five = CompositionPresentationPlan.build(
      field: _team('4-2-1-3'),
      bench: _people(5, 'R'),
    );
    expect(_rows(five.lines.last), [
      ['R0', 'R1', 'R2'],
      ['R3', 'R4'],
    ]);
  });

  test('familles de poste : milieux offensifs avec les milieux', () {
    expect(familyForSlotLabel('GB'), PresentationLineKind.goalkeeper);
    expect(familyForSlotLabel('DCG'), PresentationLineKind.defenders);
    expect(familyForSlotLabel('MOC'), PresentationLineKind.midfielders);
    expect(familyForSlotLabel('AG'), PresentationLineKind.attackers);
    expect(familyForSlotLabel('BUD'), PresentationLineKind.attackers);
  });

  test('sans position, un joueur va avec les milieux, le gardien en cage', () {
    final plan = CompositionPresentationPlan.build(
      field: const [
        PresentationPerson(id: 'g', name: 'G', isGoalkeeper: true),
        PresentationPerson(id: 'x', name: 'X'),
      ],
    );
    expect(plan.lines.map((line) => line.kind), [
      PresentationLineKind.goalkeeper,
      PresentationLineKind.midfielders,
    ]);
  });
}
