import 'dart:convert';
import 'dart:io';

import 'package:as_grinta/features/matches/data/match_edit_schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// La modification d'un match part avec la version chargée à l'ouverture du
/// formulaire : le serveur refuse l'écriture si le match a changé depuis,
/// au lieu d'écraser le travail d'un autre administrateur.
void main() {
  group('envoi au serveur', () {
    late HttpServer server;
    late List<Map<String, dynamic>> bodies;
    late supabase.SupabaseClient client;

    setUp(() async {
      bodies = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        bodies.add({
          'path': request.uri.path,
          ...Map<String, dynamic>.from(jsonDecode(body) as Map),
        });
        request.response
          ..headers.contentType = ContentType.json
          ..write('true');
        await request.response.close();
      });
      client = supabase.SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const supabase.AuthClientOptions(autoRefreshToken: false),
      );
    });

    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });

    test('la version attendue part en UTC avec la modification', () async {
      await MatchEditScheduleRepository(client).updateInternalMatch(
        id: 'm1',
        seasonId: 's1',
        kickoffAt: DateTime(2026, 10, 4, 21),
        expectedUpdatedAt: DateTime.utc(2026, 9, 20, 18, 30, 12).toLocal(),
      );
      await MatchEditScheduleRepository(client).updateMatch(
        id: 'm2',
        seasonId: 's1',
        opponentId: 'o1',
        kickoffAt: DateTime(2026, 10, 11, 21),
        isHome: true,
        status: 'a_venir',
        oddsWin: 2,
        oddsDraw: 3,
        oddsLoss: 4,
        expectedUpdatedAt: DateTime.utc(2026, 9, 21, 8),
      );

      expect(bodies.map((body) => body['path']), [
        '/rest/v1/rpc/update_internal_match_v3',
        '/rest/v1/rpc/admin_update_match_complete_v3',
      ]);
      expect(bodies[0]['p_expected_updated_at'], '2026-09-20T18:30:12.000Z');
      expect(bodies[1]['p_expected_updated_at'], '2026-09-21T08:00:00.000Z');
    });

    test('sans version connue, rien n’est envoyé', () async {
      await expectLater(
        MatchEditScheduleRepository(client).updateInternalMatch(
          id: 'm1',
          seasonId: 's1',
          kickoffAt: DateTime(2026, 10, 4, 21),
          expectedUpdatedAt: null,
        ),
        throwsA(isA<StateError>()),
      );
      expect(bodies, isEmpty);
    });
  });
}
