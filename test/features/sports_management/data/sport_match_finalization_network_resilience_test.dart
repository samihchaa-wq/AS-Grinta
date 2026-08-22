import 'dart:async';

import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('confirmSportMatchFinalizationWrite', () {
    test('returns the acknowledged server response without read-back', () async {
      final expected = _finalization();
      final saved = _finalization(isValidated: true, version: 1);
      var readBackCalls = 0;

      final result = await confirmSportMatchFinalizationWrite(
        submit: () async => saved,
        readBack: () async {
          readBackCalls += 1;
          return saved;
        },
        expected: expected,
      );

      expect(result.version, 1);
      expect(readBackCalls, 0);
    });

    test('confirms a lost acknowledgement from the published result', () async {
      final expected = _finalization();
      final published = _finalization(isValidated: true, version: 1);

      final result = await confirmSportMatchFinalizationWrite(
        submit: () async => throw TimeoutException('ack lost'),
        readBack: () async => published,
        expected: expected,
      );

      expect(result.version, 1);
      expect(result.isValidated, isTrue);
    });

    test('marks a different published score as outcome unknown', () async {
      final expected = _finalization();
      final published = _finalization(
        isValidated: true,
        version: 1,
        scoreAdverse: 2,
      );

      await expectLater(
        confirmSportMatchFinalizationWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => published,
          expected: expected,
        ),
        throwsA(isA<SportMatchFinalizationWriteOutcomeUnknown>()),
      );
    });

    test('marks different participant statistics as outcome unknown', () async {
      final expected = _finalization();
      final published = _finalization(
        isValidated: true,
        version: 1,
        participants: [_participant(goals: 1), _participant(id: 'p2')],
      );

      await expectLater(
        confirmSportMatchFinalizationWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => published,
          expected: expected,
        ),
        throwsA(isA<SportMatchFinalizationWriteOutcomeUnknown>()),
      );
    });

    test('marks an unavailable read-back as outcome unknown', () async {
      final expected = _finalization();

      await expectLater(
        confirmSportMatchFinalizationWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => throw TimeoutException('read timeout'),
          expected: expected,
        ),
        throwsA(isA<SportMatchFinalizationWriteOutcomeUnknown>()),
      );
    });

    test('keeps an explicit PostgREST refusal as a definite failure', () async {
      final expected = _finalization();
      var readBackCalls = 0;
      const serverError = PostgrestException(
        message: 'Finalization refused',
        code: '42501',
      );

      await expectLater(
        confirmSportMatchFinalizationWrite(
          submit: () async => throw serverError,
          readBack: () async {
            readBackCalls += 1;
            return _finalization(isValidated: true, version: 1);
          },
          expected: expected,
        ),
        throwsA(same(serverError)),
      );
      expect(readBackCalls, 0);
    });

    test('keeps an invalid acknowledged payload as a definite failure', () async {
      final expected = _finalization();
      var readBackCalls = 0;
      const contractError = FormatException('invalid response');

      await expectLater(
        confirmSportMatchFinalizationWrite(
          submit: () async => throw contractError,
          readBack: () async {
            readBackCalls += 1;
            return _finalization(isValidated: true, version: 1);
          },
          expected: expected,
        ),
        throwsA(same(contractError)),
      );
      expect(readBackCalls, 0);
    });
  });
}

SportMatchFinalization _finalization({
  bool isValidated = false,
  int version = 0,
  int scoreAsGrinta = 2,
  int scoreAdverse = 1,
  List<SportFinalParticipant>? participants,
}) {
  return SportMatchFinalization(
    matchId: 'match-1',
    opponentName: 'Adversaire',
    isHome: true,
    kickoffAt: DateTime(2026, 8, 17, 10),
    matchStatus: isValidated ? 'termine' : 'a_venir',
    isValidated: isValidated,
    version: version,
    scoreAsGrinta: scoreAsGrinta,
    scoreAdverse: scoreAdverse,
    compositionVersion: 3,
    presenceState: isValidated ? 'validated' : 'pending',
    voteState: isValidated ? 'open' : 'unavailable',
    participants: participants ?? [_participant(), _participant(id: 'p2')],
  );
}

SportFinalParticipant _participant({String id = 'p1', int goals = 0}) {
  return SportFinalParticipant(
    participantId: id,
    seasonPlayerId: 'season-$id',
    displayName: 'Joueur $id',
    isGuest: false,
    isGoalkeeper: false,
    plannedZone: 'field',
    present: true,
    selectionStatus: SportFinalSelectionStatus.starter,
    goals: goals,
    cleanSheet: false,
  );
}
