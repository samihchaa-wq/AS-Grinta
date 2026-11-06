import 'dart:convert';
import 'dart:io';

import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Administration > Utilisateurs affiche le nom affiché (surnom compris) :
/// la liste est rangée selon ce nom, sans tenir compte des accents ni de la
/// casse.
void main() {
  test('la liste des utilisateurs suit le nom affiché, surnom compris',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      final body = request.uri.path.endsWith('/rpc/staff_list_profiles')
          ? [
              _profile('1', 'Karim', 'Benali', ''),
              _profile('2', 'Anthony', 'Martin', 'Zizou'),
              _profile('3', 'Maxime', 'Durand', ''),
              _profile('4', 'élodie', 'Faure', ''),
              _profile('5', 'Bruno', 'Leroy', 'le mur'),
            ]
          : <Object>[];
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);

    final dashboard = await AdminRepository(client).fetchDashboard();

    expect(
      dashboard.profiles.map((profile) => profile.displayName),
      ['Élodie', 'Karim', 'Le Mur', 'Maxime', 'Zizou'],
    );
  });

  test('la clé de tri ignore les accents et la casse', () {
    expect(personNameSortKey('Élodie'), 'elodie');
    expect(personNameSortKey('  Zoé '), 'zoe');
    expect(personNameSortKey('Œil'), 'oeil');
  });
}

Map<String, Object?> _profile(
  String id,
  String firstName,
  String lastName,
  String surnom,
) =>
    {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'surnom': surnom,
      'username': firstName.toLowerCase(),
      'password_set': true,
      'role': 'pronostiqueur',
      'status': 'active',
    };
