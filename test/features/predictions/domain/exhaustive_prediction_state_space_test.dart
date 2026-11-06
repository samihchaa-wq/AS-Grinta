import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/domain/prediction_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('exhaustive prediction state space', () {
    test('scoring matches the independent oracle for 9 604 combinations', () {
      var cases = 0;
      const oddsValues = <double?>[null, 1.01, 2.5, 100];

      for (var predictedHome = 0; predictedHome <= 6; predictedHome += 1) {
        for (var predictedAway = 0; predictedAway <= 6; predictedAway += 1) {
          for (var actualHome = 0; actualHome <= 6; actualHome += 1) {
            for (var actualAway = 0; actualAway <= 6; actualAway += 1) {
              for (final odds in oddsValues) {
                cases += 1;
                final observed = PredictionScoring.points(
                  predictedHome: predictedHome,
                  predictedAway: predictedAway,
                  actualHome: actualHome,
                  actualAway: actualAway,
                  baseOdds: odds,
                );
                final expected = _expectedPoints(
                  predictedHome: predictedHome,
                  predictedAway: predictedAway,
                  actualHome: actualHome,
                  actualAway: actualAway,
                  baseOdds: odds,
                );
                final context = 'prediction=$predictedHome-$predictedAway '
                    'result=$actualHome-$actualAway odds=$odds';
                if (expected == null) {
                  expect(observed, isNull, reason: context);
                } else {
                  expect(
                    observed,
                    closeTo(expected, 0.0000001),
                    reason: context,
                  );
                }
              }
            }
          }
        }
      }

      expect(cases, 9604);
      // ignore: avoid_print
      print('STATE_SPACE prediction_scoring cases=$cases status=passed');
    });

    test('all match statuses and every prediction-window boundary', () {
      final kickoff = DateTime(2026, 8, 7, 20, 30);
      final open = matchFeaturesOpenAt(kickoff);
      final close = matchPredictionClosesAt(kickoff);
      final instants = <String, DateTime>{
        'before_open': open.subtract(const Duration(milliseconds: 1)),
        'at_open': open,
        'middle': open.add(const Duration(days: 2)),
        'before_close': close.subtract(const Duration(milliseconds: 1)),
        'at_close': close,
        'after_close': close.add(const Duration(milliseconds: 1)),
      };
      const statuses = <String>[
        'a_venir',
        'en_cours',
        'termine',
        'archive',
        'unknown',
      ];
      var cases = 0;

      for (final status in statuses) {
        for (final instantEntry in instants.entries) {
          final closedAtValues = <String, DateTime?>{
            'server_null': null,
            'server_before': instantEntry.value.subtract(
              const Duration(milliseconds: 1),
            ),
            'server_at': instantEntry.value,
            'server_after': instantEntry.value.add(
              const Duration(milliseconds: 1),
            ),
          };
          for (final closedEntry in closedAtValues.entries) {
            cases += 1;
            final item = _item(
              kickoffAt: kickoff,
              status: status,
              predictionsClosedAt: closedEntry.value,
            );
            final expected = status == 'a_venir' &&
                !instantEntry.value.isBefore(open) &&
                instantEntry.value.isBefore(close) &&
                (closedEntry.value == null ||
                    instantEntry.value.isBefore(closedEntry.value!));
            expect(
              item.canEditAt(instantEntry.value),
              expected,
              reason: 'status=$status instant=${instantEntry.key} '
                  'server=${closedEntry.key}',
            );
          }
        }
      }

      expect(cases, 120);
      // ignore: avoid_print
      print('STATE_SPACE prediction_window cases=$cases status=passed');
    });
  });
}

double? _expectedPoints({
  required int predictedHome,
  required int predictedAway,
  required int actualHome,
  required int actualAway,
  required double? baseOdds,
}) {
  if (baseOdds == null) return null;
  final predictedResult = _result(predictedHome, predictedAway);
  final actualResult = _result(actualHome, actualAway);
  if (predictedResult != actualResult) return 0;
  if (predictedHome == actualHome && predictedAway == actualAway) {
    return baseOdds * 2;
  }
  if (predictedHome - predictedAway == actualHome - actualAway ||
      predictedHome == actualHome ||
      predictedAway == actualAway) {
    return baseOdds * 1.5;
  }
  return baseOdds;
}

int _result(int home, int away) => home == away ? 0 : (home > away ? 1 : -1);

MatchPredictionItem _item({
  String matchId = 'match',
  DateTime? kickoffAt,
  String status = 'a_venir',
  int scoreGrinta = 0,
  int scoreOpponent = 0,
  bool isFilled = false,
  DateTime? predictionsClosedAt,
}) {
  return MatchPredictionItem(
    matchId: matchId,
    opponentName: 'Opponent',
    kickoffAt: kickoffAt ?? DateTime.now().add(const Duration(days: 3)),
    status: status,
    scoreGrinta: scoreGrinta,
    scoreOpponent: scoreOpponent,
    isFilled: isFilled,
    oddsWin: 2,
    oddsDraw: 3,
    oddsLoss: 4,
    actualScoreGrinta: null,
    actualScoreOpponent: null,
    predictionsClosedAt: predictionsClosedAt,
  );
}
