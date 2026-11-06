import 'dart:convert';
import 'dart:io';

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Les fonctions serveur `register-account` et `manage-user` expliquent leurs
/// refus dans le champ `error` de leur réponse. Ces tests passent par un vrai
/// client Supabase, branché sur un faux serveur local.
void main() {
  late HttpServer server;
  late SupabaseClient client;
  var status = 200;
  Object? body;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  Future<Object> failure(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (error) {
      return error;
    }
    fail('une erreur était attendue');
  }

  group('inscription', () {
    Future<Object?> register() => AuthRepository(client).registerAccount(
          firstName: 'Alex',
          lastName: 'Martin',
          password: 'GrandePhrase2026',
        );

    test('le message français du serveur est affiché', () async {
      status = 429;
      body = {'error': 'Trop de tentatives. Réessaie plus tard.'};

      final error = await failure(register);

      expect(error, isA<StateError>());
      expect(humanizeError(error), 'Trop de tentatives. Réessaie plus tard.');
      expect(
        (error as StateError).message,
        'Trop de tentatives. Réessaie plus tard.',
      );
    });

    test('un message technique en anglais laisse le message générique',
        () async {
      status = 405;
      body = {'error': 'Method not allowed'};

      final error = await failure(register);

      expect((error as StateError).message, 'La création du compte a échoué.');
    });
  });

  group('actions d’administration sur les comptes', () {
    test('réinitialisation : le message français du serveur est affiché',
        () async {
      status = 409;
      body = {'error': 'Réactive d’abord ce compte.'};

      final error = await failure(
        () => AdminRepository(client).resetAccountPassword('u1'),
      );

      expect(humanizeError(error), 'Réactive d’abord ce compte.');
    });

    test('suppression : le message français du serveur est affiché', () async {
      status = 403;
      body = {'error': 'Compte technique protégé.'};

      final error = await failure(
        () async => AdminRepository(client).deleteAccount('u1'),
      );

      expect(humanizeError(error), 'Compte technique protégé.');
    });

    test('suppression : un message technique laisse le message générique',
        () async {
      status = 400;
      body = {'error': 'Valid user id is required'};

      final error = await failure(
        () async => AdminRepository(client).deleteAccount('u1'),
      );

      expect(humanizeError(error), 'La suppression du compte a échoué.');
    });
  });

  test('reconnaît un message rédigé en français', () {
    expect(looksFrench('Ajoute au moins un chiffre.'), isTrue);
    expect(
      looksFrench('Utilise ton profil pour modifier ton mot de passe.'),
      isTrue,
    );
    expect(looksFrench('Prénom ou nom invalide.'), isTrue);
    expect(looksFrench('Valid user id is required'), isFalse);
    expect(looksFrench('The last active admin cannot be deleted'), isFalse);
  });
}
