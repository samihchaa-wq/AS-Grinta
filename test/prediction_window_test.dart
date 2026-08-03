import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('J-6 noon prediction window', () {
    // 7 août 2026 à 20:30 Paris = 18:30 UTC.
    // J-6 à 12:00 Paris = 1er août à 10:00 UTC.
    final opensAt = DateTime.utc(2026, 8, 1, 10);
    final kickoff = DateTime.utc(2026, 8, 7, 18, 30);

    test('opens at noon on the sixth calendar day before kickoff', () {
      final item = _item(kickoffAt: kickoff);

      expect(item.opensAt, opensAt);
      expect(
        item.canEditAt(opensAt.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(item.canEditAt(opensAt), isTrue);
    });

    test('every match inside the window is editable independently', () {
      final first = _item(
        matchId: 'match-1',
        kickoffAt: DateTime.utc(2026, 8, 2, 7),
      );
      final second = _item(
        matchId: 'match-2',
        kickoffAt: DateTime.utc(2026, 8, 4, 19),
      );

      expect(first.canEditAt(opensAt), isTrue);
      expect(second.canEditAt(opensAt), isTrue);
    });

    test('a match whose J-6 noon has not arrived remains closed', () {
      final item = _item(kickoffAt: DateTime.utc(2026, 8, 8, 8));

      expect(item.canEditAt(opensAt), isFalse);
    });

    test('the controller saves any match whose window is open', () async {
      final item = _item(
        matchId: 'match-2',
        kickoffAt: DateTime.now().toUtc().add(const Duration(days: 3)),
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
