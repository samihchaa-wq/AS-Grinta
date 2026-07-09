import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchModel', () {
    test('exposes a readable location and status label', () {
      final match = MatchModel(
        id: '1',
        seasonId: 'season-1',
        opponentId: 'opp-1',
        kickoffAt: DateTime(2026, 7, 10, 20, 0),
        isHome: true,
        plannedDurationMinutes: 90,
        status: 'en_cours',
        grintaScore: 2,
        opponentScore: 1,
      );

      expect(match.locationLabel, 'Domicile');
      expect(match.statusLabel, 'En cours');
    });
  });
}
