import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('first open prediction window', () {
    final now = DateTime.utc(2026, 8, 1, 12);
    final kickoff = now.add(const Duration(days: 1));

    test('the first open match remains editable', () {
      final item = _item(kickoffAt: kickoff, isFirstOpenMatch: true);

      expect(item.isWaitingForPreviousMatchAt(now), isFalse);
      expect(item.isClosedAt(now), isFalse);
      expect(item.canEditAt(now), isTrue);
    });

    test('a later time-open match waits for the previous match', () {
      final item = _item(kickoffAt: kickoff, isFirstOpenMatch: false);

      expect(item.isWaitingForPreviousMatchAt(now), isTrue);
      expect(item.isClosedAt(now), isTrue);
      expect(item.canEditAt(now), isFalse);
    });

    test('a manually closed match is not reported as waiting', () {
      final item = _item(
        kickoffAt: kickoff,
        isFirstOpenMatch: false,
        predictionsClosedAt: now.subtract(const Duration(seconds: 1)),
      );

      expect(item.isWaitingForPreviousMatchAt(now), isFalse);
      expect(item.isClosedAt(now), isTrue);
    });

    test('the controller never saves a later match', () async {
      final locked = _item(
        kickoffAt: DateTime.now().add(const Duration(days: 1)),
        isFirstOpenMatch: false,
      );
      final repository = _FakePredictionsRepository(locked);
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.save(locked.matchId);

      expect(repository.saveCalls, 0);
    });
  });
}

MatchPredictionItem _item({
  required DateTime kickoffAt,
  required bool isFirstOpenMatch,
  DateTime? predictionsClosedAt,
}) {
  return MatchPredictionItem(
    matchId: 'match-2',
    opponentName: 'Opponent',
    kickoffAt: kickoffAt,
    status: 'a_venir',
    scoreGrinta: 0,
    scoreOpponent: 0,
    isFilled: false,
    useX2: false,
    x2Available: 1,
    oddsWin: 2,
    oddsDraw: 3,
    oddsLoss: 4,
    actualScoreGrinta: null,
    actualScoreOpponent: null,
    predictionsClosedAt: predictionsClosedAt,
    isFirstOpenMatch: isFirstOpenMatch,
  );
}

class _FakePredictionsRepository implements PredictionsRepository {
  _FakePredictionsRepository(this.item);

  final MatchPredictionItem item;
  int saveCalls = 0;

  @override
  Future<List<MatchPredictionItem>> fetchMyMatchPredictions() async => [item];

  @override
  Future<MatchPredictionItem?> fetchMatchPrediction(String matchId) async =>
      matchId == item.matchId ? item : null;

  @override
  Future<void> savePrediction({
    required String matchId,
    required int scoreGrinta,
    required int scoreOpponent,
    required bool useX2,
  }) async {
    saveCalls += 1;
  }
}
