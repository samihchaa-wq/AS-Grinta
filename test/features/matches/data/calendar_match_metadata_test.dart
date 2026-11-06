import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modern championship exposes its persistent J number', () {
    final match = MatchModel(
      id: 'match-1',
      seasonId: 'season-1',
      opponentId: 'opponent-1',
      kickoffAt: DateTime(2026, 9, 28, 20, 45),
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'a_venir',
      grintaScore: null,
      opponentScore: null,
      opponentName: 'Adversaire',
      matchType: 'championnat',
      championshipRound: 4,
    );

    expect(match.matchTypeLabel, 'Championnat · J4');
    expect(match.calendarTypeLabel, 'Championnat · J4');
  });

  test('friendly and internal labels stay distinct', () {
    final friendly = MatchModel(
      id: 'friendly',
      seasonId: 'season-1',
      opponentId: 'opponent-1',
      kickoffAt: DateTime(2026, 9, 21, 20, 45),
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'a_venir',
      grintaScore: null,
      opponentScore: null,
      matchType: 'amical',
    );
    final internal = MatchModel(
      id: 'internal',
      seasonId: 'season-1',
      opponentId: '',
      kickoffAt: DateTime(2026, 9, 14, 20, 45),
      isHome: true,
      plannedDurationMinutes: 90,
      status: 'a_venir',
      grintaScore: null,
      opponentScore: null,
      matchType: 'entre_nous',
    );

    expect(friendly.calendarTypeLabel, 'Amical');
    expect(internal.calendarTypeLabel, 'Match entre nous');
  });

  test(
    'historical metadata derives season and keeps unknown fields nullable',
    () {
      final historical = HistoricalMatchResult(
        id: 'history-1',
        date: DateTime(2025, 10, 6, 20, 30),
        hasTime: true,
        opponentName: 'Ancien adversaire',
        grintaScore: 3,
        opponentScore: 1,
        isHome: false,
        matchType: 'championnat',
        championshipRound: 7,
        address: '1 rue du Stade',
      );

      expect(historical.seasonName, '2025-2026');
      expect(historical.matchTypeLabel, 'Championnat · J7');
      expect(historical.calendarTypeLabel, 'Championnat · J7');
      expect(historical.hasTime, isTrue);
      expect(historical.address, '1 rue du Stade');
    },
  );
}
