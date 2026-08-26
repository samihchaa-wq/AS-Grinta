import 'package:as_grinta/core/widgets/match_scorers_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows no scorer when AS Grinta scored zero', (tester) async {
    await tester.pumpWidget(
      host(const MatchScorersCard(teamGoals: 0, scorers: [])),
    );

    expect(find.text('Buteurs'), findsOneWidget);
    expect(find.text('Aucun buteur'), findsOneWidget);
  });

  testWidgets('does not invent scorers when archive detail is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MatchScorersCard(teamGoals: 2, scorers: [])),
    );

    expect(find.text('Buteurs non renseignés'), findsOneWidget);
  });

  testWidgets('shows scorer names and multiple goals', (tester) async {
    await tester.pumpWidget(
      host(
        const MatchScorersCard(
          teamGoals: 3,
          scorers: [
            MatchScorerEntry(name: 'Flo', goals: 2),
            MatchScorerEntry(name: 'Sam', goals: 1),
          ],
        ),
      ),
    );

    expect(find.text('Flo'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
  });
}
