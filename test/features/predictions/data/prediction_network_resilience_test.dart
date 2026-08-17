import 'dart:async';

import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('confirmPredictionWrite', () {
    test('does not read back after an acknowledged write', () async {
      var readBackCalls = 0;

      await confirmPredictionWrite(
        submit: () async {},
        readBackMatchesExpected: () async {
          readBackCalls += 1;
          return true;
        },
      );

      expect(readBackCalls, 0);
    });

    test('recovers a lost acknowledgement through read-back', () async {
      await confirmPredictionWrite(
        submit: () async => throw TimeoutException('ack lost'),
        readBackMatchesExpected: () async => true,
      );
    });

    test('marks a mismatching read-back as outcome unknown', () async {
      await expectLater(
        confirmPredictionWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBackMatchesExpected: () async => false,
        ),
        throwsA(isA<PredictionWriteOutcomeUnknown>()),
      );
    });

    test('marks an unavailable read-back as outcome unknown', () async {
      await expectLater(
        confirmPredictionWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBackMatchesExpected: () async =>
              throw TimeoutException('read timeout'),
        ),
        throwsA(isA<PredictionWriteOutcomeUnknown>()),
      );
    });

    test('keeps explicit server refusals as definite failures', () async {
      var readBackCalls = 0;
      const serverError = PostgrestException(
        message: 'Prediction window is closed',
        code: '22023',
      );

      await expectLater(
        confirmPredictionWrite(
          submit: () async => throw serverError,
          readBackMatchesExpected: () async {
            readBackCalls += 1;
            return true;
          },
        ),
        throwsA(same(serverError)),
      );
      expect(readBackCalls, 0);
    });

    test('keeps an unexpected RPC result as a definite failure', () async {
      var readBackCalls = 0;
      final stateError = StateError('Unexpected RPC result');

      await expectLater(
        confirmPredictionWrite(
          submit: () async => throw stateError,
          readBackMatchesExpected: () async {
            readBackCalls += 1;
            return true;
          },
        ),
        throwsA(same(stateError)),
      );
      expect(readBackCalls, 0);
    });
  });
}
