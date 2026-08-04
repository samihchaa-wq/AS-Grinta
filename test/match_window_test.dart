import 'package:as_grinta/core/utils/match_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fenêtre d’ouverture d’un match', () {
    // Vendredi 7 août 2026 à 20:30 à Paris = 18:30 UTC.
    // J-6 à midi à Paris = samedi 1er août à 10:00 UTC.
    final kickoff = DateTime.utc(2026, 8, 7, 18, 30);
    final opensAt = DateTime.utc(2026, 8, 1, 10);

    test('l’ouverture est fixée à midi Paris le jour J-6', () {
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
      // 09:00 Paris = 07:00 UTC ; 23:45 Paris = 21:45 UTC en août.
      expect(
        matchFeaturesOpenAt(DateTime.utc(2026, 8, 7, 7)),
        opensAt,
      );
      expect(
        matchFeaturesOpenAt(DateTime.utc(2026, 8, 7, 21, 45)),
        opensAt,
      );
    });

    test('le fuseau hiver Europe/Paris est pris en compte', () {
      // Samedi 10 janvier 2026 à 20:30 Paris = 19:30 UTC.
      // J-6 dimanche 4 janvier à 12:00 Paris = 11:00 UTC.
      expect(
        matchFeaturesOpenAt(DateTime.utc(2026, 1, 10, 19, 30)),
        DateTime.utc(2026, 1, 4, 11),
      );
    });

    test('le changement d’heure de mars est pris en compte', () {
      // Le 30 mars 2026 Paris est en UTC+2. J-6 tombe le 24 mars, encore UTC+1.
      expect(
        matchFeaturesOpenAt(DateTime.utc(2026, 3, 30, 18, 30)),
        DateTime.utc(2026, 3, 24, 11),
      );
    });

    test('un match proche ou déjà joué est ouvert', () {
      expect(
        isMatchTooFarAway(kickoff, now: DateTime.utc(2026, 8, 5, 10)),
        isFalse,
      );
      expect(
        isMatchTooFarAway(kickoff, now: DateTime.utc(2026, 8, 8, 10)),
        isFalse,
      );
    });

    test('sans coup d’envoi connu, la fiche reste complète', () {
      expect(isMatchTooFarAway(null, now: opensAt), isFalse);
    });
  });

  group('frontière Prono / Live', () {
    final kickoff = DateTime.utc(2026, 8, 7, 18, 30);
    final opensAt = DateTime.utc(2026, 8, 7, 18, 15);

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

    test('le prono ferme au même instant', () {
      expect(matchPredictionClosesAt(kickoff), opensAt);
      expect(
        isMatchPredictionClosed(
          kickoff,
          now: opensAt.subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
      expect(isMatchPredictionClosed(kickoff, now: opensAt), isTrue);
      expect(isMatchAdminEditLocked(kickoff, now: opensAt), isTrue);
    });

    test('sans coup d’envoi connu, le Live ne bloque pas la fiche', () {
      expect(isMatchLiveTooEarly(null, now: opensAt), isFalse);
      expect(isMatchPredictionClosed(null, now: opensAt), isTrue);
    });
  });

  group('phase d’affichage du match', () {
    final kickoff = DateTime.utc(2026, 8, 7, 18, 30);

    MatchDisplayPhase phaseAt(
      DateTime now, {
      String status = 'a_venir',
      String? liveState,
      int duration = 90,
    }) =>
        matchDisplayPhase(
          kickoffAt: kickoff,
          status: status,
          plannedDurationMinutes: duration,
          liveState: liveState,
          now: now,
        );

    test('enchaîne à venir, prochain, direct et à valider', () {
      expect(
        phaseAt(DateTime.utc(2026, 8, 1, 9, 59, 59)),
        MatchDisplayPhase.upcoming,
      );
      expect(
        phaseAt(DateTime.utc(2026, 8, 1, 10)),
        MatchDisplayPhase.next,
      );
      expect(
        phaseAt(DateTime.utc(2026, 8, 7, 18, 15)),
        MatchDisplayPhase.live,
      );
      expect(
        phaseAt(DateTime.utc(2026, 8, 7, 20, 15)),
        MatchDisplayPhase.awaitingValidation,
      );
    });

    test('une fin Live bascule à valider dès le coup d’envoi', () {
      expect(
        phaseAt(
          DateTime.utc(2026, 8, 7, 18, 20),
          liveState: 'finished',
        ),
        MatchDisplayPhase.live,
      );
      expect(
        phaseAt(
          DateTime.utc(2026, 8, 7, 18, 30),
          liveState: 'finished',
        ),
        MatchDisplayPhase.awaitingValidation,
      );
    });

    test('un Live actif reste en direct au-delà de la fin théorique', () {
      for (final state in ['running', 'paused', 'halftime']) {
        expect(
          phaseAt(
            DateTime.utc(2026, 8, 7, 21),
            liveState: state,
          ),
          MatchDisplayPhase.live,
          reason: 'state=$state',
        );
      }
    });

    test('la validation serveur l’emporte sur toute temporalité', () {
      expect(
        phaseAt(
          DateTime.utc(2026, 8, 7, 18),
          status: 'termine',
        ),
        MatchDisplayPhase.past,
      );
      expect(
        phaseAt(
          DateTime.utc(2026, 8, 7, 18),
          status: 'annule',
        ),
        MatchDisplayPhase.cancelled,
      );
    });
  });
}
