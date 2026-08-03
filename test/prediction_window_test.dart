import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('six-day prediction window', () {
    final now = DateTime.utc(2026, 8, 1, 12);
    final kickoff = now.add(const Duration(days: 6));

    test('opens exactly six days before kickoff', () {
      final item = _item(kickoffAt: kickoff);

      expect(item.opensAt, now);
      expect(
        item.canEditAt(now.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(item.canEditAt(now), isTrue);
    });

    test('every match inside the window is editable independently', () {
      final first = _item(
        matchId: 'match-1',
        kickoffAt: now.add(const Duration(days: 1)),
      );
      final second = _item(
        matchId: 'match-2',
        kickoffAt: now.add(const Duration(days: 3)),
      );

      expect(first.canEditAt(now), isTrue);
      expect(second.canEditAt(now), isTrue);
    });

    test('a match more than six days away remains closed', () {
      final item = _item(
        kickoffAt: now.add(const Duration(days: 6, milliseconds: 1)),
      );

      expect(item.canEditAt(now), isFalse);
    });

    test('the controller saves any match whose window is open', () async {
      final item = _item(
        matchId: 'match-2',
        kickoffAt: DateTime.now().add(const Duration(days: 3)),
      );
      final repository = _FakePredictionsRepository(item);
      final controller = PredictionsController(repository);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.save(item.matchId);

      expect(repository.saveCalls, 1);
      expect(repository.savedMatchId, item.matchId);
    });
  });
}

MatchPredictionItem _item({
  String matchId = 'match',
  required DateTime kickoffAt,
}) {
  return MatchPredictionItem(
    matchId: matchId,
    opponentName: 'Opponent',
    kickoffAt: kickoffAt,
    status: 'a_venir',
    scoreGrinta: 0,
    scoreOpponent: 0,
    isFilled: false,
    oddsWin: 2,
    oddsDraw: 3,
    oddsLoss: 4,
    actualScoreGrinta: null,
    actualScoreOpponent: null,
  );
}

class _FakePredictionsRepository implements PredictionsRepository {
  _FakePredictionsRepository(this.item);

  final MatchPredictionItem item;
  int saveCalls = 0;
  String? savedMatchId;

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
  }) async {
    saveCalls += 1;
    savedMatchId = matchId;
  }
}
