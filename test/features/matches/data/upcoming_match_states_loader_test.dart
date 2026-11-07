import 'dart:convert';
import 'dart:io';

import 'package:as_grinta/features/match_live/data/match_live_notification_repository.dart';
import 'package:as_grinta/features/matches/data/upcoming_match_states_loader.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Calendrier : les cartes de match lisent « ma dispo » et la cloche des buts
/// en une seule requête, et retombent sur les appels individuels tant que la
/// base ne sait pas regrouper.
void main() {
  late _FakeServer server;
  late SupabaseClient client;

  setUpAll(() async {
    server = await _FakeServer.start();
    client = SupabaseClient(
      server.url,
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDownAll(() => server.close());
  setUp(() => server.reset());

  const grouped = '/rest/v1/rpc/get_my_upcoming_match_states';
  const availability = '/rest/v1/rpc/get_my_match_availability';
  const bell = '/rest/v1/rpc/get_match_live_notification_subscription';

  test('les demandes simultanées partent en une seule requête', () async {
    final loader = UpcomingMatchStatesLoader(client);

    final results = await Future.wait([
      loader.load('m1'),
      loader.load('m1'),
      loader.load('m2'),
    ]);

    expect(server.hits(grouped), 1);
    expect(server.lastGroupedIds, unorderedEquals(['m1', 'm2']));
    expect(results[0]!.availabilityRead, isTrue);
    expect(results[2]!.liveNotificationsRead, isTrue);
  });

  test('aucune réponse n’est gardée : une relecture repart au serveur',
      () async {
    final loader = UpcomingMatchStatesLoader(client);

    await loader.load('m1');
    await loader.load('m1');

    expect(server.hits(grouped), 2);
  });

  test('les cartes du calendrier ne font qu’une requête pour deux états',
      () async {
    final loader = UpcomingMatchStatesLoader(client);
    final availabilityRepository =
        SupabaseMatchAvailabilityRepository(client, statesLoader: loader);
    final bellRepository =
        SupabaseMatchLiveNotificationRepository(client, statesLoader: loader);

    final results = await Future.wait<Object?>([
      availabilityRepository.fetchMyAvailability('m1'),
      bellRepository.fetchStatus('m1'),
      availabilityRepository.fetchMyAvailability('m2'),
      bellRepository.fetchStatus('m2'),
    ]);

    expect(server.hits(grouped), 1);
    expect(server.hits(availability), 0);
    expect(server.hits(bell), 0);
    expect(
      (results[1]! as MatchLiveNotificationStatus).eligible,
      isTrue,
    );
  });

  test('une part en erreur est redemandée par l’appel individuel', () async {
    server.failingAvailabilityFor = 'm2';
    final loader = UpcomingMatchStatesLoader(client);
    final repository =
        SupabaseMatchAvailabilityRepository(client, statesLoader: loader);

    await Future.wait([
      repository.fetchMyAvailability('m1'),
      repository.fetchMyAvailability('m2'),
    ]);

    expect(server.hits(grouped), 1);
    expect(server.hits(availability), 1);
  });

  test('sans fonction groupée en base, retour aux appels individuels',
      () async {
    server.groupedFunctionDeployed = false;
    final loader = UpcomingMatchStatesLoader(client);
    final repository =
        SupabaseMatchLiveNotificationRepository(client, statesLoader: loader);

    await repository.fetchStatus('m1');
    await repository.fetchStatus('m2');

    // Une seule tentative groupée : la session sait ensuite que la base ne
    // regroupe pas encore et n'essaie plus.
    expect(server.hits(grouped), 1);
    expect(server.hits(bell), 2);
  });
}

class _FakeServer {
  _FakeServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeServer> start() async =>
      _FakeServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _hits = <String, int>{};
  bool groupedFunctionDeployed = true;
  String? failingAvailabilityFor;
  List<String> lastGroupedIds = const [];

  String get url => 'http://127.0.0.1:${_server.port}';

  int hits(String path) => _hits[path] ?? 0;

  void reset() {
    _hits.clear();
    groupedFunctionDeployed = true;
    failingAvailabilityFor = null;
    lastGroupedIds = const [];
  }

  Future<void> close() => _server.close(force: true);

  static const _bellState = {
    'eligible': true,
    'subscribed': false,
    'opens_at': null,
  };

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    _hits[path] = hits(path) + 1;
    final raw = await utf8.decoder.bind(request).join();
    final params = raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;

    var status = 200;
    Object? body;
    switch (path) {
      case '/rest/v1/rpc/get_my_upcoming_match_states':
        if (!groupedFunctionDeployed) {
          status = 404;
          body = {
            'code': 'PGRST202',
            'message': 'Could not find the function '
                'public.get_my_upcoming_match_states(p_match_ids) '
                'in the schema cache',
          };
          break;
        }
        final ids = (params['p_match_ids'] as List).cast<String>();
        lastGroupedIds = ids;
        body = {
          for (final id in ids)
            id: {
              'availability_ok': id != failingAvailabilityFor,
              'availability': null,
              'live_notifications_ok': true,
              'live_notifications': _bellState,
            },
        };
      case '/rest/v1/rpc/get_my_match_availability':
        body = null;
      case '/rest/v1/rpc/get_match_live_notification_subscription':
        body = _bellState;
      default:
        status = 404;
    }

    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}
