import 'package:as_grinta/features/matches/data/historical_match_detail_repository.dart';
import 'package:as_grinta/features/matches/presentation/historical_match_detail_page.dart';
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
}
