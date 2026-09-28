import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry _entry({
  required String name,
  required MatchCompositionZone zone,
  required int sortOrder,
  double? x,
  double? y,
}) {
  return MatchCompositionEntry(
    participantId: 'participant-$sortOrder',
    seasonPlayerId: 'season-$sortOrder',
    displayName: name,
    isGoalkeeper: sortOrder == 0,
    zone: zone,
    sortOrder: sortOrder,
    availabilityStatus: 'available',
    convocationStatus: 'convoked',
    selectionStatus: zone == MatchCompositionZone.field ? 'starter' : 'bench',
    x: x,
    y: y,
  );
}

List<MatchCompositionEntry> _field() => [
      _entry(
        name: 'Gardien',
        zone: MatchCompositionZone.field,
        sortOrder: 0,
        x: .5,
        y: .9,
      ),
      _entry(
        name: 'Défenseur',
        zone: MatchCompositionZone.field,
        sortOrder: 1,
        x: .25,
        y: .65,
      ),
      _entry(
        name: 'Milieu',
        zone: MatchCompositionZone.field,
        sortOrder: 2,
        x: .5,
        y: .45,
      ),
      _entry(
        name: 'Attaquant',
        zone: MatchCompositionZone.field,
        sortOrder: 3,
        x: .5,
        y: .18,
      ),
    ];

List<MatchCompositionEntry> _bench(int count) => List.generate(
      count,
      (index) => _entry(
        name: 'R${index + 1}',
        zone: MatchCompositionZone.bench,
        sortOrder: 20 + index,
      ),
    );

Widget _harness(int benchCount) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 360,
          child: CompositionPitchWithBench(
            field: _field(),
            bench: _bench(benchCount),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('le banc utilise 1, 2 puis 3 colonnes', () {
    expect(compositionBenchColumnCount(0), 0);
    expect(compositionBenchColumnCount(1), 1);
    expect(compositionBenchColumnCount(6), 1);
    expect(compositionBenchColumnCount(7), 2);
    expect(compositionBenchColumnCount(12), 2);
    expect(compositionBenchColumnCount(13), 3);
    expect(compositionBenchColumnCount(15), 3);
  });

  testWidgets(
    'peu de remplaçants gardent un grand terrain, 15 restent lisibles',
    (tester) async {
      await tester.pumpWidget(_harness(3));
      await tester.pump();
      final widthWithThree =
          tester.getSize(find.byType(CompositionPitch)).width;
      expect(widthWithThree, greaterThan(295));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_harness(15));
      await tester.pump();
      final widthWithFifteen =
          tester.getSize(find.byType(CompositionPitch)).width;

      expect(widthWithFifteen, lessThan(widthWithThree));
      expect(widthWithFifteen, greaterThan(220));
      for (var index = 1; index <= 15; index++) {
        expect(find.text('R$index'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
