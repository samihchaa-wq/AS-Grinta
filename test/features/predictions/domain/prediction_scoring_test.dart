import 'package:as_grinta/features/predictions/domain/prediction_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PredictionScoring', () {
    test('score exact = cote x2', () {
      expect(
        PredictionScoring.points(
          predictedHome: 2,
          predictedAway: 1,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        4,
      );
    });

    test('bon vainqueur + bon écart = cote x1,5', () {
      expect(
        PredictionScoring.points(
          predictedHome: 3,
          predictedAway: 2,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        3,
      );
    });

    test('bon vainqueur + score exact d’une équipe = cote x1,5', () {
      expect(
        PredictionScoring.points(
          predictedHome: 2,
          predictedAway: 0,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        3,
      );
    });

    test('bon vainqueur seul = cote x1', () {
      expect(
        PredictionScoring.points(
          predictedHome: 3,
          predictedAway: 0,
          actualHome: 2,
          actualAway: 1,
          baseOdds: 2,
        ),
        2,
      );
    });

    test('nul prédit et nul réel sans score exact = cote x1,5', () {
      expect(
        PredictionScoring.points(
          predictedHome: 1,
          predictedAway: 1,
          actualHome: 2,
          actualAway: 2,
          baseOdds: 3,
        ),
        4.5,
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
