import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/match_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MatchModel finishedMatch({required String matchType, String? address}) =>
      MatchModel(
        id: 'match',
        seasonId: 'season',
        opponentId: matchType == 'entre_nous' ? '' : 'opponent',
        kickoffAt: DateTime.utc(2026, 8, 10, 17),
        isHome: true,
        plannedDurationMinutes: 90,
        status: 'termine',
        grintaScore: null,
        opponentScore: null,
        matchType: matchType,
        address: address,
      );

  Future<void> pumpCard(WidgetTester tester, MatchModel match) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: MatchHistoryCard(match: match)),
        ),
      ),
    );
  }

  testWidgets(
    'un Match entre nous terminé garde son libellé et ne se clique pas',
    (tester) async {
      await pumpCard(tester, finishedMatch(matchType: 'entre_nous'));

      expect(find.text('Match entre nous'), findsOneWidget);
      expect(find.text('Adversaire'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    },
  );

  testWidgets(
    'un match classique terminé conserve sa navigation',
    (tester) async {
      await pumpCard(tester, finishedMatch(matchType: 'championnat'));

      expect(find.byType(InkWell), findsOneWidget);
    },
  );

  testWidgets('un match terminé affiche son adresse', (tester) async {
    const address =
        'Complexe Sportif de Toulouse INP - 223 Rue des Arts - 31670 - Labège';
    await pumpCard(
      tester,
      finishedMatch(matchType: 'championnat', address: address),
    );

    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    expect(find.text(address), findsOneWidget);
  });
}
