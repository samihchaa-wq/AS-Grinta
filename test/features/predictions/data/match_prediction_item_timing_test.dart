import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchPredictionItem timing', () {
    final kickoff = DateTime.utc(2026, 7, 14, 20);

    test('closes exactly fifteen minutes before kickoff', () {
      final item = _item(kickoffAt: kickoff);

      expect(item.closesAt, DateTime.utc(2026, 7, 14, 19, 45));
      expect(
        item.isClosedAt(DateTime.utc(2026, 7, 14, 19, 44, 59, 999)),
        isFalse,
      );
      expect(item.isClosedAt(item.closesAt), isTrue);
    });

    test('respects an explicit earlier closure timestamp', () {
      final explicitClosure = DateTime.utc(2026, 7, 14, 19, 30);
      final item = _item(
        kickoffAt: kickoff,
        predictionsClosedAt: explicitClosure,
      );

      expect(
        item.isClosedAt(explicitClosure.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(item.isClosedAt(explicitClosure), isTrue);
    });

    test('non-upcoming matches are always closed', () {
      final item = _item(kickoffAt: kickoff, status: 'termine');

      expect(item.isClosedAt(DateTime.utc(2026, 7, 1)), isTrue);
    });
  });
}

MatchPredictionItem _item({
  required DateTime kickoffAt,
  String status = 'a_venir',
  int scoreGrinta = 0,
  int scoreOpponent = 0,
  bool isFilled = false,
  DateTime? predictionsClosedAt,
}) {
  return MatchPredictionItem(
    matchId: 'match',
    opponentName: 'Opponent',
    kickoffAt: kickoffAt,
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
