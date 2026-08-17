import 'dart:async';

import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

MatchAvailability _availability(
  MatchAvailabilityStatus status, {
  String? privateComment,
}) {
  return MatchAvailability(
    matchId: 'match-1',
    participantId: 'participant-1',
    seasonPlayerId: 'player-1',
    isEligible: true,
    status: status,
    privateComment: privateComment,
    updatedAt: DateTime.utc(2026, 8, 17, 10),
    availabilityState: 'open',
    opensAt: DateTime.utc(2026, 8, 17, 8),
    kickoffAt: DateTime.utc(2026, 8, 20, 18),
    canRespond: true,
    compositionState: 'draft',
  );
}

void main() {
  group('confirmMatchAvailabilityWrite', () {
    test('returns the refreshed value after an acknowledged write', () async {
      final expected = _availability(MatchAvailabilityStatus.available);

      final result = await confirmMatchAvailabilityWrite(
        submit: () async => {'changed': true},
        readBack: () async => expected,
        expectedStatus: MatchAvailabilityStatus.available,
        expectedPrivateComment: null,
      );

      expect(result, same(expected));
    });

    test('recovers a lost acknowledgement through read-back', () async {
      final expected = _availability(MatchAvailabilityStatus.absent);

      final result = await confirmMatchAvailabilityWrite(
        submit: () async => throw TimeoutException('ack lost'),
        readBack: () async => expected,
        expectedStatus: MatchAvailabilityStatus.absent,
        expectedPrivateComment: null,
      );

      expect(result, same(expected));
    });

    test('marks a non-confirmed network write as outcome unknown', () async {
      final current = _availability(MatchAvailabilityStatus.available);

      await expectLater(
        confirmMatchAvailabilityWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => current,
          expectedStatus: MatchAvailabilityStatus.absent,
          expectedPrivateComment: null,
        ),
        throwsA(isA<MatchAvailabilityWriteOutcomeUnknown>()),
      );
    });

    test('keeps explicit server refusals as definite failures', () async {
      var readBackCalls = 0;
      const serverError = PostgrestException(
        message: 'Availability window is closed',
        code: '22023',
      );

      await expectLater(
        confirmMatchAvailabilityWrite(
          submit: () async => throw serverError,
          readBack: () async {
            readBackCalls += 1;
            return _availability(MatchAvailabilityStatus.absent);
          },
          expectedStatus: MatchAvailabilityStatus.absent,
          expectedPrivateComment: null,
        ),
        throwsA(same(serverError)),
      );
      expect(readBackCalls, 0);
    });

    test('distinguishes saved-but-refresh-failed from unknown outcome', () async {
      await expectLater(
        confirmMatchAvailabilityWrite(
          submit: () async => {'changed': true},
          readBack: () async => throw TimeoutException('read timeout'),
          expectedStatus: MatchAvailabilityStatus.available,
          expectedPrivateComment: null,
        ),
        throwsA(isA<MatchAvailabilityWriteConfirmedButRefreshFailed>()),
      );
    });

    test('checks the private comment when confirming an absent response', () async {
      final expected = _availability(
        MatchAvailabilityStatus.absent,
        privateComment: 'Blessé',
      );

      final result = await confirmMatchAvailabilityWrite(
        submit: () async => throw TimeoutException('ack lost'),
        readBack: () async => expected,
        expectedStatus: MatchAvailabilityStatus.absent,
        expectedPrivateComment: 'Blessé',
      );

      expect(result.privateComment, 'Blessé');
    });
  });
}
