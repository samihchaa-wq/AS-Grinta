import 'dart:async';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/logging/error_category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('formats a useful record without including the error message', () {
    const secret = 'user@example.com password=super-secret';

    final record = AppLogger.formatRecord(
      operation: 'auth sign-in',
      error: StateError(secret),
      incidentReference: 'ASG-20260727-120000-001',
    );

    expect(record, contains('operation=auth_sign-in'));
    expect(record, contains('error_type=state'));
    expect(record, contains('incident=ASG-20260727-120000-001'));
    expect(record, contains('version='));
    expect(record, isNot(contains(secret)));
    expect(record, isNot(contains('user@example.com')));
    expect(record, isNot(contains('super-secret')));
  });

  test('creates a short support reference without personal data', () {
    final reference = AppLogger.createIncidentReference(
      at: DateTime.utc(2026, 7, 27, 12, 34, 56),
    );

    expect(reference, matches(RegExp(r'^ASG-20260727-123456-\d{3}$')));
  });

  group('catégorie d’incident', () {
    test('garde le code structuré des erreurs Supabase', () {
      expect(
        describeErrorForIncident(
          const PostgrestException(message: 'denied', code: '42501'),
        ),
        'postgrest:42501',
      );
      expect(
        describeErrorForIncident(
          const PostgrestException(message: 'absent', code: 'PGRST116'),
        ),
        'postgrest:PGRST116',
      );
      expect(
        describeErrorForIncident(
            const StorageException('nope', statusCode: '404')),
        'storage:404',
      );
      expect(
        describeErrorForIncident(
          const AuthException('bad grant', code: 'invalid_credentials'),
        ),
        'auth:invalid_credentials',
      );
    });

    test('nomme les familles Dart courantes plutôt qu’un nom de classe', () {
      expect(describeErrorForIncident(StateError('x')), 'state');
      expect(describeErrorForIncident(const FormatException('x')), 'format');
      expect(describeErrorForIncident(ArgumentError('x')), 'argument');
      expect(describeErrorForIncident(TimeoutException('x')), 'timeout');
      expect(describeErrorForIncident(null), 'null');
    });

    test('reconnaît la coupure réseau de chaque navigateur', () {
      for (final failure in [
        // Chrome, Firefox et Safari formulent différemment, mais le Web les
        // enveloppe toujours dans une ClientException.
        Exception('ClientException: Failed to fetch, uri=https://x.test'),
        Exception('ClientException: Load failed, uri=https://x.test'),
        Exception(
          'ClientException: NetworkError when attempting to fetch resource.',
        ),
        Exception('SocketException: Failed host lookup: «x.test»'),
        AuthRetryableFetchException(message: 'offline'),
      ]) {
        expect(
          describeErrorForIncident(failure),
          'network',
          reason: 'non reconnu : $failure',
        );
        expect(isNetworkFailure(failure), isTrue);
      }
    });

    test('un refus du serveur n’est pas confondu avec une coupure réseau', () {
      const denied =
          PostgrestException(message: 'permission denied', code: '42501');
      expect(isNetworkFailure(denied), isFalse);
      expect(describeErrorForIncident(denied), 'postgrest:42501');
    });

    test('une erreur applicative banale ne devient pas un problème de réseau',
        () {
      // Un serveur qui répond, même pour refuser, n'est pas un réseau coupé —
      // et une formulation malheureuse ne doit pas suffire à le faire croire.
      for (final benign in [
        StateError('load failed'),
        StateError('connection closed by the user'),
        const FormatException('network error in payload'),
        ArgumentError('failed to fetch the selected player'),
        const PostgrestException(
          message: 'network is unreachable',
          code: '42501',
        ),
      ]) {
        expect(
          isNetworkFailure(benign),
          isFalse,
          reason: 'faux positif réseau sur : $benign',
        );
      }
    });

    test('ne laisse jamais fuiter le message dans la catégorie', () {
      const secret = 'user@example.com jeton=abc123';
      final categories = [
        describeErrorForIncident(StateError(secret)),
        describeErrorForIncident(const PostgrestException(message: secret)),
        describeErrorForIncident(Exception(secret)),
      ];

      for (final category in categories) {
        expect(category, isNot(contains('@')));
        expect(category, isNot(contains('abc123')));
        expect(category, matches(RegExp(r'^[A-Za-z0-9_]+(:[A-Za-z0-9_]+)?$')));
      }
    });
  });
}
