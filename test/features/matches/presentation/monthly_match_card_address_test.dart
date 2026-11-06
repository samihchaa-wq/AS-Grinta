import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/calendar_matches_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MatchModel upcomingMatch({required String matchType, String? address}) =>
      MatchModel(
        id: 'match',
        seasonId: 'season',
        opponentId: matchType == 'entre_nous' ? '' : 'opponent',
        kickoffAt: DateTime.now().add(const Duration(days: 20)),
        isHome: true,
        plannedDurationMinutes: 90,
        status: 'a_venir',
        grintaScore: null,
        opponentScore: null,
        opponentName: matchType == 'entre_nous' ? null : 'FC Booster',
        matchType: matchType,
        address: address,
      );

  Future<void> pumpCard(WidgetTester tester, MatchModel match) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MonthlyMatchCard(match: match, adminActions: null),
          ),
        ),
      ),
    );
  }

  testWidgets('un match à venir affiche son adresse dans la vue Par mois', (
    tester,
  ) async {
    const address = 'INP - 223 Rue des Arts - 31670 - Labège';
    await pumpCard(
      tester,
      upcomingMatch(matchType: 'amical', address: address),
    );

    expect(find.byIcon(Icons.place_outlined), findsNothing);
    expect(find.text(address), findsOneWidget);
  });

  testWidgets('un match entre nous à venir affiche aussi son adresse', (
    tester,
  ) async {
    const address = 'INP - 223 Rue des Arts - 31670 - Labège';
    await pumpCard(
      tester,
      upcomingMatch(matchType: 'entre_nous', address: address),
    );

    expect(find.text('Match entre nous'), findsOneWidget);
    expect(find.text(address), findsOneWidget);
  });

  testWidgets('sans adresse renseignée, aucune ligne de lieu n’est ajoutée', (
    tester,
  ) async {
    await pumpCard(tester, upcomingMatch(matchType: 'amical'));

    expect(find.byIcon(Icons.place_outlined), findsNothing);
  });
}
