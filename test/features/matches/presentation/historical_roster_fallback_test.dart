import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/matches/presentation/historical_match_detail_page.dart';
import 'package:as_grinta/features/matches/presentation/widgets/completed_match_composition_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Philippe n’apparaît jamais dans l’effectif historique de secours', () {
    const detail = HistoricalMatchDetail(
      formation: null,
      fieldPlayers: [],
      benchPlayers: [],
      presentNames: ['Alban', 'Philippe', 'Philippe C.', 'Milan'],
      scorers: [HistoricalScorer(name: 'Philippe', goals: 1)],
      motmNames: [],
    );

    final players = historicalFallbackPlayers(detail);

    expect(players.map((player) => player.name).toList(), ['Alban', 'Milan']);
  });

  test('l’Homme du match est repéré dans l’effectif de secours', () {
    const detail = HistoricalMatchDetail(
      formation: null,
      fieldPlayers: [],
      benchPlayers: [],
      presentNames: ['Alban', 'Pipo'],
      scorers: [HistoricalScorer(name: 'Pipo', goals: 2)],
      motmNames: ['Pipo'],
    );

    final players = historicalFallbackPlayers(detail);

    expect(
      {for (final player in players) player.name: player.isMotm},
      {'Alban': false, 'Pipo': true},
    );
  });

  testWidgets('la couronne suit le prénom, avant le ballon aligné à droite', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompletedPlayersList(
            players: [
              CompletedPlayerSummary(name: 'Pipo', goals: 2, isMotm: true),
              CompletedPlayerSummary(name: 'Alban', goals: 1),
            ],
          ),
        ),
      ),
    );

    expect(find.text('👑'), findsOneWidget);
    final name = tester.getRect(find.text('Pipo'));
    final crown = tester.getRect(find.text('👑'));
    final ball = tester.getRect(find.text('⚽ ×2'));
    // Juste à droite du prénom, sur la même ligne.
    expect(crown.left - name.right, lessThan(12));
    expect((crown.center.dy - name.center.dy).abs(), lessThan(4));
    // Le ballon reste tout à droite, séparé de la couronne.
    expect(ball.left, greaterThan(crown.right + 100));
  });
}
