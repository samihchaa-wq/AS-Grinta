import 'package:as_grinta/features/matches/domain/match_finalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchFinalizationRules', () {
    test('accepts consistent score, goals and substitutions', () {
      final validation = MatchFinalizationRules.validate(
        grintaScore: 2,
        opponentScore: 1,
        goals: [
          const MatchGoal(
            team: 'grinta',
            minute: 10,
            scorerId: 'p1',
            assisterId: 'p2',
          ),
          const MatchGoal(
            team: 'grinta',
            minute: 32,
            scorerId: 'p4',
            assisterId: 'p5',
          ),
          const MatchGoal(
            team: 'adversaire',
            minute: 45,
            scorerId: 'p3',
            assisterId: null,
          ),
        ],
        substitutions: [
          const MatchSubstitution(
            minute: 60,
            inPlayerId: 'p4',
            outPlayerId: 'p5',
          ),
        ],
      );

      expect(validation.isValid, isTrue);
      expect(validation.issues, isEmpty);
    });

    test('flags inconsistent score and goal count', () {
      final validation = MatchFinalizationRules.validate(
        grintaScore: 2,
        opponentScore: 1,
        goals: [
          const MatchGoal(
            team: 'grinta',
            minute: 10,
            scorerId: 'p1',
            assisterId: null,
          ),
        ],
        substitutions: const [],
      );

      expect(validation.isValid, isFalse);
      expect(
        validation.issues,
        contains('Le score ne correspond pas au nombre de buts enregistrés.'),
      );
    });

    test('computes points from odds using the requested formula', () {
      expect(
        MatchFinalizationRules.calculatePoints(
          odds: 2.0,
          predictedGrintaScore: 1,
          predictedOpponentScore: 0,
          actualGrintaScore: 1,
          actualOpponentScore: 0,
        ),
        30.0,
      );
      expect(
        MatchFinalizationRules.calculatePoints(
          odds: 2.0,
          predictedGrintaScore: 2,
          predictedOpponentScore: 0,
          actualGrintaScore: 1,
          actualOpponentScore: 0,
        ),
        20.0,
      );
      expect(
        MatchFinalizationRules.calculatePoints(
          odds: 2.0,
          predictedGrintaScore: 0,
          predictedOpponentScore: 1,
          actualGrintaScore: 1,
          actualOpponentScore: 0,
        ),
        0.0,
      );
    });
  });
}
