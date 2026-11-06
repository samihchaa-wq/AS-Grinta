import 'package:as_grinta/features/matches/presentation/widgets/championship_round_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required int? round,
  required List<int?> roundsOfSeason,
  bool enabled = true,
  VoidCallback? onTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChampionshipRoundTile(
        round: round,
        roundsOfSeason: roundsOfSeason,
        enabled: enabled,
        onTap: onTap ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('affiche la journée retenue', (tester) async {
    await tester.pumpWidget(_host(round: 12, roundsOfSeason: const [10, 11]));

    expect(find.text('Journée de championnat J12'), findsOneWidget);
  });

  testWidgets('annonce le numéro automatique quand rien n’est choisi',
      (tester) async {
    await tester.pumpWidget(_host(round: null, roundsOfSeason: const []));

    expect(
      find.text('Journée de championnat · Numéro automatique'),
      findsOneWidget,
    );
  });

  testWidgets('prévient quand la journée est déjà utilisée', (tester) async {
    await tester.pumpWidget(_host(round: 3, roundsOfSeason: const [1, 2, 3]));

    expect(
      find.text('Journée de championnat J3 · déjà utilisée cette saison'),
      findsOneWidget,
    );
  });

  testWidgets('ouvre le choix au tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(round: 4, roundsOfSeason: const [], onTap: () => taps += 1),
    );

    await tester.tap(find.byType(ListTile));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('reste inerte pendant un enregistrement', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        round: 4,
        roundsOfSeason: const [],
        enabled: false,
        onTap: () => taps += 1,
      ),
    );

    await tester.tap(find.byType(ListTile));
    await tester.pump();

    expect(taps, 0);
  });
}
