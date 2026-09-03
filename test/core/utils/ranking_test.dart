import 'package:as_grinta/core/utils/ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('competitionRanks', () {
    test('two tied leaders share the first place and the next is third', () {
      expect(
        competitionRanks([100, 100, 90], (points) => points),
        [1, 1, 3],
      );
    });

    test('keeps distinct values on consecutive ranks', () {
      expect(
        competitionRanks([12, 9, 4], (points) => points),
        [1, 2, 3],
      );
    });

    test('handles a tie that is not at the top', () {
      expect(
        competitionRanks([30, 20, 20, 20, 5], (points) => points),
        [1, 2, 2, 2, 5],
      );
    });

    test('handles a tie at the very bottom', () {
      expect(
        competitionRanks([30, 10, 10], (points) => points),
        [1, 2, 2],
      );
    });

    test('gives every entry the same rank when all are tied', () {
      expect(
        competitionRanks([7, 7, 7, 7], (points) => points),
        [1, 1, 1, 1],
      );
    });

    test('reads the ranking value through the accessor', () {
      const rows = [
        (name: 'Ada', points: 100),
        (name: 'Bo', points: 100),
        (name: 'Cy', points: 90),
      ];

      expect(competitionRanks(rows, (row) => row.points), [1, 1, 3]);
    });

    test('treats equal decimal values as tied', () {
      expect(
        competitionRanks([12.5, 12.5, 4.0], (points) => points),
        [1, 1, 3],
      );
    });

    test('returns nothing for an empty ranking', () {
      expect(competitionRanks(<int>[], (points) => points), isEmpty);
    });

    test('ranks a single entry first', () {
      expect(competitionRanks([42], (points) => points), [1]);
    });
  });
}
