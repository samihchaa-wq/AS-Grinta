import 'package:as_grinta/core/utils/match_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fenêtre d’ouverture d’un match', () {
    final kickoff = DateTime(2026, 8, 7, 20, 30);
    final opensAt = DateTime(2026, 8, 1, 12);

    test('l’ouverture est fixée à midi le jour J-6', () {
      expect(matchFeaturesOpenAt(kickoff), opensAt);
      expect(
        isMatchTooFarAway(
          kickoff,
          now: opensAt.subtract(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
      expect(isMatchTooFarAway(kickoff, now: opensAt), isFalse);
    });

    test('l’heure du coup d’envoi ne décale pas le midi de J-6', () {
      expect(
        matchFeaturesOpenAt(DateTime(2026, 8, 7, 9)),
        DateTime(2026, 8, 1, 12),
      );
      expect(
        matchFeaturesOpenAt(DateTime(2026, 8, 7, 23, 45)),
        DateTime(2026, 8, 1, 12),
      );
    });

    test('un match proche ou déjà joué est ouvert', () {
      expect(
        isMatchTooFarAway(kickoff, now: DateTime(2026, 8, 5, 12)),
        isFalse,
      );
      expect(
        isMatchTooFarAway(kickoff, now: DateTime(2026, 8, 8, 12)),
        isFalse,
      );
    });

    test('sans coup d’envoi connu, la fiche reste complète', () {
      expect(isMatchTooFarAway(null, now: opensAt), isFalse);
    });
  });

  group('fenêtre du Live', () {
    final kickoff = DateTime(2026, 8, 7, 20, 30);
    final opensAt = DateTime(2026, 8, 7, 20, 15);

    test('le Live ouvre exactement quinze minutes avant', () {
      expect(matchLiveOpensAt(kickoff), opensAt);
      expect(
        isMatchLiveTooEarly(
          kickoff,
          now: opensAt.subtract(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
      expect(isMatchLiveTooEarly(kickoff, now: opensAt), isFalse);
    });

    test('sans coup d’envoi connu, le Live ne bloque pas la fiche', () {
      expect(isMatchLiveTooEarly(null, now: opensAt), isFalse);
    });
  });
}
