import 'package:as_grinta/features/predictions/domain/prediction_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PredictionScoring', () {
    test('score exact = cote x20', () {
      expect(
        PredictionScoring.points(
          predictedHome: 2,
          predictedAway: 1,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        40,
      );
    });

    test('bon vainqueur + bon écart = cote x15', () {
      expect(
        PredictionScoring.points(
          predictedHome: 3,
          predictedAway: 2,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        30,
      );
    });

    test('bon vainqueur + score exact d’une équipe = cote x15', () {
      expect(
        PredictionScoring.points(
          predictedHome: 2,
          predictedAway: 0,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        30,
      );
    });

    test('bon vainqueur seul = cote x10', () {
      expect(
        PredictionScoring.points(
          predictedHome: 3,
          predictedAway: 0,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        20,
      );
    });

    test('nul prédit et nul réel sans score exact = cote x15 (écart nul)', () {
      expect(
        PredictionScoring.points(
          predictedHome: 1,
          predictedAway: 1,
          actualHome: 2,
          actualAway: 2,
          baseOdds: 3,
        ),
        45,
      );
    });

    test('mauvais résultat = 0', () {
      expect(
        PredictionScoring.points(
          predictedHome: 0,
          predictedAway: 1,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        0,
      );
    });

    test('sans cote = null', () {
      expect(
        PredictionScoring.points(
          predictedHome: 1,
          predictedAway: 1,
          actualHome: 1,
          actualAway: 1,
          baseOdds: null,
        ),
        isNull,
      );
    });
  });
}
