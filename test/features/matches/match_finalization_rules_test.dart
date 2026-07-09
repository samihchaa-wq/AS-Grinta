import 'package:as_grinta/features/matches/domain/match_finalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchFinalizationRules.validate', () {
    test('accepts a score matching recorded goals', () {
      final result = MatchFinalizationRules.validate(
        grintaScore: 2,
        opponentScore: 1,
        goals: const [
          MatchGoal(
            team: 'grinta',
            minute: 10,
            scorerId: 'player-1',
            assisterId: null,
          ),
          MatchGoal(
            team: 'grinta',
            minute: 55,
            scorerId: 'player-2',
            assisterId: 'player-1',
          ),
          MatchGoal(
            team: 'adversaire',
            minute: 70,
            scorerId: null,
            assisterId: null,
          ),
        ],
        substitutions: const [
          MatchSubstitution(
            minute: 60,
            inPlayerId: 'player-3',
            outPlayerId: 'player-4',
          ),
        ],
      );

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('rejects a score inconsistent with recorded goals', () {
      final result = MatchFinalizationRules.validate(
        grintaScore: 2,
        opponentScore: 0,
        goals: const [
          MatchGoal(
            team: 'grinta',
            minute: 10,
            scorerId: 'player-1',
            assisterId: null,
          ),
        ],
        substitutions: const [],
      );

      expect(result.isValid, isFalse);
      expect(
        result.issues,
        contains('Le score ne correspond pas au nombre de buts enregistrés.'),
      );
    });
  });

  group('MatchFinalizationRules.calculatePoints', () {
    test('uses odds times 15 for an exact score', () {
      final points = MatchFinalizationRules.calculatePoints(
        odds: 2.0,
        predictedGrintaScore: 2,
        predictedOpponentScore: 1,
        actualGrintaScore: 2,
        actualOpponentScore: 1,
      );

      expect(points, 30);
    });

    test('uses odds times 10 for the correct result only', () {
      final points = MatchFinalizationRules.calculatePoints(
        odds: 2.0,
        predictedGrintaScore: 3,
        predictedOpponentScore: 1,
        actualGrintaScore: 2,
        actualOpponentScore: 1,
      );

      expect(points, 20);
    });

    test('returns zero for the wrong result', () {
      final points = MatchFinalizationRules.calculatePoints(
        odds: 2.0,
        predictedGrintaScore: 0,
        predictedOpponentScore: 1,
        actualGrintaScore: 2,
        actualOpponentScore: 1,
      );

      expect(points, 0);
    });
  });
}
