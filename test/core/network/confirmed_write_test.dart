import 'dart:async';

import 'package:as_grinta/core/network/confirmed_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Value {
  const _Value(this.version);

  final int version;
}

void main() {
  group('confirmWrite', () {
    test('returns the acknowledged write without reading back', () async {
      var readBackCalls = 0;

      final result = await confirmWrite<_Value>(
        submit: () async => const _Value(2),
        readBack: () async {
          readBackCalls += 1;
          return const _Value(2);
        },
        isExpected: (value) => value.version == 2,
      );

      expect(result.version, 2);
      expect(readBackCalls, 0);
    });

    test('recovers a lost acknowledgement through read-back', () async {
      var submitCalls = 0;

      final result = await confirmWrite<_Value>(
        submit: () async {
          submitCalls += 1;
          throw TimeoutException('ack lost');
        },
        readBack: () async => const _Value(2),
        isExpected: (value) => value.version > 1,
      );

      expect(result.version, 2);
      // La mutation ne doit jamais être rejouée : c'est ce qui créerait un
      // doublon ou une correction fantôme.
      expect(submitCalls, 1);
    });

    test('treats an unchanged server state as outcome unknown', () async {
      await expectLater(
        confirmWrite<_Value>(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => const _Value(1),
          isExpected: (value) => value.version > 1,
        ),
        throwsA(isA<WriteOutcomeUnknown>()),
      );
    });

    test('treats a missing server state as outcome unknown', () async {
      await expectLater(
        confirmWrite<_Value>(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => null,
          isExpected: (_) => true,
        ),
        throwsA(isA<WriteOutcomeUnknown>()),
      );
    });

    test('treats an unavailable read-back as outcome unknown', () async {
      await expectLater(
        confirmWrite<_Value>(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => throw TimeoutException('read timeout'),
          isExpected: (_) => true,
        ),
        throwsA(isA<WriteOutcomeUnknown>()),
      );
    });

    test('keeps an explicit server refusal as a definite failure', () async {
      var readBackCalls = 0;
      const refusal = PostgrestException(
        message: 'Le compte rendu est verrouillé',
        code: '22023',
      );

      await expectLater(
        confirmWrite<_Value>(
          submit: () async => throw refusal,
          readBack: () async {
            readBackCalls += 1;
            return const _Value(2);
          },
          isExpected: (_) => true,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(readBackCalls, 0);
    });

    test('keeps a refused session as a definite failure', () async {
      var readBackCalls = 0;

      await expectLater(
        confirmWrite<_Value>(
          submit: () async => throw const AuthException('session expired'),
          readBack: () async {
            readBackCalls += 1;
            return const _Value(2);
          },
          isExpected: (_) => true,
        ),
        throwsA(isA<AuthException>()),
      );
      expect(readBackCalls, 0);
    });

    test('keeps an unexpected RPC result as a definite failure', () async {
      var readBackCalls = 0;

      await expectLater(
        confirmWrite<_Value>(
          submit: () async => throw StateError('unexpected RPC payload'),
          readBack: () async {
            readBackCalls += 1;
            return const _Value(2);
          },
          isExpected: (_) => true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(readBackCalls, 0);
    });

    test('reads back when the write exceeds its timeout', () async {
      final result = await confirmWrite<_Value>(
        submit: () => Future<_Value>.delayed(
          const Duration(milliseconds: 200),
          () => const _Value(9),
        ),
        readBack: () async => const _Value(2),
        isExpected: (value) => value.version == 2,
        writeTimeout: const Duration(milliseconds: 20),
      );

      expect(result.version, 2);
    });
  });
}
