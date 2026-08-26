import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/historical_match_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HistoricalMatchResult historical({String? address}) => HistoricalMatchResult(
        id: 'history-1',
        date: DateTime(2025, 10, 6, 20, 30),
        hasTime: true,
        opponentName: 'Ancien adversaire',
        grintaScore: 3,
        opponentScore: 1,
        isHome: false,
        matchType: 'championnat',
        championshipRound: 7,
        address: address,
      );

  Widget app(HistoricalMatchResult match) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: HistoricalMatchCard(match: match),
          ),
        ),
      );

  testWidgets('historical card shows a clickable address when known',
      (tester) async {
    const address =
        'Stade Michel Saraiba - 8 bis Rue Claudius Rougenet - 31500 - Toulouse';
    await tester.pumpWidget(app(historical(address: address)));

    expect(find.text('Championnat · J7'), findsOneWidget);
    expect(find.text(address), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);

    await tester.tap(find.text(address));
    await tester.pumpAndSettle();

    expect(find.text('Adresse du match'), findsOneWidget);
    expect(find.text('Choisir le GPS'), findsOneWidget);
  });

  testWidgets('historical card omits the address row when unknown',
      (tester) async {
    await tester.pumpWidget(app(historical()));

    expect(find.text('Championnat · J7'), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsNothing);
  });
}
