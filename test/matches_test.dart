import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchModel', () {
    test('exposes readable competition, location and status labels', () {
      final match = MatchModel(
        id: '1',
        seasonId: 'season-1',
        opponentId: 'opp-1',
        kickoffAt: DateTime(2026, 7, 10, 20),
        isHome: true,
        competition: 'Championnat',
        plannedDurationMinutes: 90,
        status: 'termine',
        grintaScore: 2,
        opponentScore: 1,
      );

      expect(match.competition, 'Championnat');
      expect(match.locationLabel, 'Domicile');
      expect(match.statusLabel, 'Terminé');
    });
  });
}
