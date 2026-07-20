import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchModel', () {
    test('exposes readable location and status labels', () {
      final match = MatchModel(
        id: '1',
        seasonId: 'season-1',
        opponentId: 'opp-1',
        kickoffAt: DateTime(2026, 7, 10, 20),
        isHome: true,
        plannedDurationMinutes: 90,
        status: 'termine',
        grintaScore: 2,
        opponentScore: 1,
      );

      expect(match.locationLabel, 'Domicile');
      expect(match.statusLabel, 'Terminé');
    });

    // L'affichage peut changer de fuseau, mais l'instant absolu doit rester le
    // même sur le Web, iOS et les tests CI.
    test('uses the absolute server kickoff instant', () {
      final match = MatchModel.fromJson({
        'id': '1',
        'season_id': 'season-1',
        'opponent_id': 'opp-1',
        'match_date': '2026-08-20',
        'match_time': '20:45:00',
        'kickoff_at': '2026-08-20T18:45:00Z',
        'location': 'domicile',
        'planned_duration_minutes': 90,
        'status': 'a_venir',
      });

      expect(match.kickoffAt.toUtc(), DateTime.utc(2026, 8, 20, 18, 45));
    });

    test('keeps the legacy local fields as a migration fallback', () {
      final match = MatchModel.fromJson({
        'id': '1',
        'season_id': 'season-1',
        'opponent_id': 'opp-1',
        'match_date': '2026-08-20',
        'match_time': '20:45:00',
        'location': 'exterieur',
        'planned_duration_minutes': 90,
        'status': 'a_venir',
      });

      expect(match.kickoffAt, DateTime(2026, 8, 20, 20, 45));
      expect(match.locationLabel, 'Extérieur');
    });
  });
}
