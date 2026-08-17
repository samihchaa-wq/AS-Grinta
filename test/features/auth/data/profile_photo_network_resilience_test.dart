import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('uploadProfilePhotoObjectWithRetry', () {
    test('returns after the first acknowledged upload', () async {
      var attempts = 0;

      await uploadProfilePhotoObjectWithRetry(
        upload: () async {
          attempts += 1;
        },
      );

      expect(attempts, 1);
    });

    test('retries the same upload once after a lost acknowledgement', () async {
      var attempts = 0;

      await uploadProfilePhotoObjectWithRetry(
        upload: () async {
          attempts += 1;
          if (attempts == 1) throw TimeoutException('ack lost');
        },
      );

      expect(attempts, 2);
    });

    test('marks two ambiguous upload failures as outcome unknown', () async {
      var attempts = 0;

      await expectLater(
        uploadProfilePhotoObjectWithRetry(
          upload: () async {
            attempts += 1;
            throw TimeoutException('network down');
          },
        ),
        throwsA(isA<ProfilePhotoUploadOutcomeUnknown>()),
      );
      expect(attempts, 2);
    });

    test('does not retry an explicit storage rejection', () async {
      var attempts = 0;
      const serverError = StorageException(
        'Upload refused',
        statusCode: '403',
      );

      await expectLater(
        uploadProfilePhotoObjectWithRetry(
          upload: () async {
            attempts += 1;
            throw serverError;
          },
        ),
        throwsA(same(serverError)),
      );
      expect(attempts, 1);
    });
  });

  group('confirmProfilePhotoReferenceWrite', () {
    test('does not read back or clean up after an acknowledged write',
        () async {
      var readBackCalls = 0;
      var cleanupCalls = 0;

      await confirmProfilePhotoReferenceWrite(
        submit: () async {},
        readBack: () async {
          readBackCalls += 1;
          return 'new.jpg';
        },
        cleanup: () async {
          cleanupCalls += 1;
        },
        expectedPath: 'new.jpg',
      );

      expect(readBackCalls, 0);
      expect(cleanupCalls, 0);
    });

    test('keeps the file when a lost acknowledgement is confirmed', () async {
      var cleanupCalls = 0;

      await confirmProfilePhotoReferenceWrite(
        submit: () async => throw TimeoutException('ack lost'),
        readBack: () async => 'new.jpg',
        cleanup: () async {
          cleanupCalls += 1;
        },
        expectedPath: 'new.jpg',
      );

      expect(cleanupCalls, 0);
    });

    test('cleans up when read-back proves the reference was not written',
        () async {
      var cleanupCalls = 0;

      await expectLater(
        confirmProfilePhotoReferenceWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => 'old.jpg',
          cleanup: () async {
            cleanupCalls += 1;
          },
          expectedPath: 'new.jpg',
        ),
        throwsA(isA<StateError>()),
      );
      expect(cleanupCalls, 1);
    });

    test('does not delete a possibly referenced file when read-back fails',
        () async {
      var cleanupCalls = 0;

      await expectLater(
        confirmProfilePhotoReferenceWrite(
          submit: () async => throw TimeoutException('ack lost'),
          readBack: () async => throw TimeoutException('read timeout'),
          cleanup: () async {
            cleanupCalls += 1;
          },
          expectedPath: 'new.jpg',
        ),
        throwsA(isA<ProfilePhotoWriteOutcomeUnknown>()),
      );
      expect(cleanupCalls, 0);
    });

    test('cleans up after an explicit database refusal', () async {
      var cleanupCalls = 0;
      const serverError = PostgrestException(
        message: 'Profile update refused',
        code: '42501',
      );

      await expectLater(
        confirmProfilePhotoReferenceWrite(
          submit: () async => throw serverError,
          readBack: () async => 'new.jpg',
          cleanup: () async {
            cleanupCalls += 1;
          },
          expectedPath: 'new.jpg',
        ),
        throwsA(same(serverError)),
      );
      expect(cleanupCalls, 1);
    });
  });
}
