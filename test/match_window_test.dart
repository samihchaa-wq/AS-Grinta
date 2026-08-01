import 'package:as_grinta/core/utils/match_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fenêtre d’ouverture d’un match', () {
    final now = DateTime(2026, 8, 1, 12);

    test('un match à plus de six jours reste fermé', () {
      expect(
        isMatchTooFarAway(now.add(const Duration(days: 7)), now: now),
        isTrue,
      );
      expect(
        isMatchTooFarAway(
          now.add(const Duration(days: 6, minutes: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('un match à six jours pile est ouvert', () {
      expect(
        isMatchTooFarAway(now.add(const Duration(days: 6)), now: now),
        isFalse,
      );
    });

    test('un match proche ou déjà joué est ouvert', () {
      expect(
        isMatchTooFarAway(now.add(const Duration(days: 2)), now: now),
        isFalse,
      );
      expect(
        isMatchTooFarAway(now.subtract(const Duration(days: 1)), now: now),
        isFalse,
      );
    });

    test('sans coup d’envoi connu, la fiche reste complète', () {
      expect(isMatchTooFarAway(null, now: now), isFalse);
    });
  });
}
