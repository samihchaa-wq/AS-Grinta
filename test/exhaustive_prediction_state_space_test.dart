import 'dart:async';

import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/domain/prediction_scoring.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
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
                final context =
                    'prediction=$predictedHome-$predictedAway '
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
      final close = kickoff.subtract(const Duration(minutes: 5));
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
            final expected =
                status == 'a_venir' &&
                !instantEntry.value.isBefore(open) &&
                instantEntry.value.isBefore(close) &&
                (closedEntry.value == null ||
                    instantEntry.value.isBefore(closedEntry.value!));
            expect(
              item.canEditAt(instantEntry.value),
              expected,
              reason:
                  'status=$status instant=${instantEntry.key} '
                  'server=${closedEntry.key}',
            );
          }
        }
      }

      expect(cases, 120);
      // ignore: avoid_print
      print('STATE_SPACE prediction_window cases=$cases status=passed');
    });

    test('score editing exhausts boundary values and deltas', () async {
      const initialValues = [0, 1, 98, 99];
      const deltas = [-100, -1, 0, 1, 100];
      var cases = 0;

      for (final initial in initialValues) {
        for (final delta in deltas) {
          for (final grinta in [true, false]) {
            cases += 1;
            final repository = _ScenarioPredictionsRepository(
              items: [_item(scoreGrinta: initial, scoreOpponent: initial)],
            );
            final controller = PredictionsController(repository);
            await controller.load();
            controller.changeScore(
              matchId: 'match',
              grinta: grinta,
              delta: delta,
            );
            final observed = controller.state.items.single;
            final expected = (initial + delta).clamp(0, 99);
            expect(
              grinta ? observed.scoreGrinta : observed.scoreOpponent,
              expected,
              reason: 'initial=$initial delta=$delta grinta=$grinta',
            );
            expect(
              grinta ? observed.scoreOpponent : observed.scoreGrinta,
              initial,
              reason: 'the other team score must remain unchanged',
            );
            controller.dispose();
          }
        }
      }

      expect(cases, 40);
      // ignore: avoid_print
      print('STATE_SPACE prediction_score_edit cases=$cases status=passed');
    });

    test('a slow save is non-reentrant and produces one mutation', () async {
      final gate = Completer<void>();
      final repository = _ScenarioPredictionsRepository(
        items: [_item(scoreGrinta: 3, scoreOpponent: 2)],
        saveGate: gate,
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final first = controller.save('match');
      await Future<void>.delayed(Duration.zero);
      final second = controller.save('match');
      await Future<void>.delayed(Duration.zero);

      expect(repository.saveCalls, 1);
      expect(controller.state.savingMatchId, 'match');
      gate.complete();
      await Future.wait([first, second]);

      expect(repository.saveCalls, 1);
      expect(controller.state.savingMatchId, isNull);
      expect(controller.state.items.single.isFilled, isTrue);
      // ignore: avoid_print
      print('STATE_SPACE prediction_double_submit cases=1 status=passed');
    });

    test(
      'save failure preserves the complete form and permits retry',
      () async {
        final repository = _ScenarioPredictionsRepository(
          items: [_item(scoreGrinta: 4, scoreOpponent: 3)],
          saveError: StateError('network unavailable'),
        );
        final controller = PredictionsController(repository);
        addTearDown(controller.dispose);
        await controller.load();

        await controller.save('match');
        final afterFailure = controller.state.items.single;
        expect(afterFailure.scoreGrinta, 4);
        expect(afterFailure.scoreOpponent, 3);
        expect(afterFailure.isFilled, isFalse);
        expect(controller.state.error, isNotNull);
        expect(controller.state.savingMatchId, isNull);

        repository.saveError = null;
        await controller.save('match');
        expect(repository.saveCalls, 2);
        expect(controller.state.items.single.isFilled, isTrue);
        expect(controller.state.error, isNull);
        // ignore: avoid_print
        print('STATE_SPACE prediction_retry cases=2 status=passed');
      },
    );

    test('failed refresh keeps existing edited values', () async {
      final repository = _ScenarioPredictionsRepository(
        items: [_item(scoreGrinta: 1, scoreOpponent: 1)],
      );
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      controller.changeScore(matchId: 'match', grinta: true, delta: 2);

      repository.fetchError = StateError('offline');
      await controller.load();

      final item = controller.state.items.single;
      expect(item.scoreGrinta, 3);
      expect(item.scoreOpponent, 1);
      expect(controller.state.error, isNotNull);
      // ignore: avoid_print
      print('STATE_SPACE prediction_failed_refresh cases=1 status=passed');
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

class _ScenarioPredictionsRepository implements PredictionsRepository {
  _ScenarioPredictionsRepository({
    required this.items,
    this.saveGate,
    this.saveError,
  });

  List<MatchPredictionItem> items;
  Completer<void>? saveGate;
  Object? fetchError;
  Object? saveError;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async {
    fetchCalls += 1;
    final error = fetchError;
    if (error != null) throw error;
    return items;
  }

  @override
  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async {
    for (final item in items) {
      if (item.matchId == matchId) return item;
    }
    return null;
  }

  @override
  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
  }) async {
    saveCalls += 1;
    final error = saveError;
    if (error != null) throw error;
    final gate = saveGate;
    if (gate == null) return;
    await gate.future;
  }
}
