import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Chargement des données du calendrier : un même contenu demandé plusieurs
/// fois en même temps ne part qu'une fois au serveur, une relecture immédiate
/// sert la copie déjà reçue, et l'ouverture affiche d'abord la dernière copie
/// enregistrée sur l'appareil avant la réponse du serveur.
void main() {
  late _FakeServer server;

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    server = await _FakeServer.start();
    await supabase.Supabase.initialize(
      url: server.url,
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
    await _signInAs('user-1');
  });

  tearDownAll(() => server.close());

  setUp(() async {
    server.reset();
    (await SharedPreferences.getInstance()).clear();
  });

  supabase.SupabaseClient client() => supabase.Supabase.instance.client;

  group('événements du club', () {
    test('deux lectures simultanées ne font qu’une requête', () async {
      final repository = ClubEventsRepository(client());

      final results = await Future.wait([
        repository.fetchEvents(),
        repository.fetchEvents(),
      ]);

      expect(server.hits('/rest/v1/club_events'), 1);
      expect(results[0].single.title, 'Repas du club');
      expect(identical(results[0], results[1]), isTrue);
    });

    test('une relecture immédiate sert la copie reçue, sauf rafraîchissement',
        () async {
      final repository = ClubEventsRepository(client());

      await repository.fetchEvents();
      await repository.fetchEvents();
      expect(server.hits('/rest/v1/club_events'), 1);

      await repository.fetchEvents(forceRefresh: true);
      expect(server.hits('/rest/v1/club_events'), 2);
    });

    test('à l’ouverture, la copie de l’appareil s’affiche avant le serveur',
        () async {
      // Une première visite enregistre les événements sur l'appareil.
      await ClubEventsRepository(client()).fetchEvents();

      server.eventTitle = 'Tournoi de printemps';
      final gate = server.holdNextResponse();
      final emissions = <String>[];
      final done = ClubEventsRepository(client())
          .watchEventsLocalFirst()
          .listen((events) => emissions.add(events.single.title))
          .asFuture<void>();

      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions, ['Repas du club']);

      gate.complete();
      await done;
      expect(emissions, ['Repas du club', 'Tournoi de printemps']);
    });
  });

  group('historique des matchs', () {
    const path = '/rest/v1/rpc/get_all_historical_match_results';

    test('deux lectures simultanées ne font qu’une requête', () async {
      final repository = CalendarHistoryRepository(client());

      await Future.wait([repository.fetchAll(), repository.fetchAll()]);

      expect(server.hits(path), 1);
    });

    test('une relecture immédiate sert la copie reçue, sauf rafraîchissement',
        () async {
      final repository = CalendarHistoryRepository(client());

      await repository.fetchAll();
      await repository.fetchAll();
      expect(server.hits(path), 1);

      await repository.fetchAll(forceRefresh: true);
      expect(server.hits(path), 2);
    });

    test('à l’ouverture, la copie de l’appareil s’affiche avant le serveur',
        () async {
      await CalendarHistoryRepository(client()).fetchAll();

      server.historicalOpponent = 'FC Nouveau';
      final gate = server.holdNextResponse();
      final emissions = <String>[];
      final done = CalendarHistoryRepository(client())
          .watchAllLocalFirst()
          .listen((matches) => emissions.add(matches.single.opponentName))
          .asFuture<void>();

      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions, ['FC Ancien']);

      gate.complete();
      await done;
      expect(emissions, ['FC Ancien', 'FC Nouveau']);
    });
  });

  test('l’écran reçoit la copie de l’appareil puis celle du serveur', () async {
    // Une première visite enregistre événements et historique sur l'appareil.
    await ClubEventsRepository(client()).fetchEvents();
    await CalendarHistoryRepository(client()).fetchAll();
    server.eventTitle = 'Tournoi de printemps';
    server.historicalOpponent = 'FC Nouveau';

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final events = <String>[];
    final history = <String>[];
    container.listen(clubEventsProvider, (_, next) {
      final value = next.valueOrNull;
      if (value != null) events.add(value.single.title);
    });
    container.listen(allHistoricalMatchesProvider, (_, next) {
      final value = next.valueOrNull;
      if (value != null) history.add(value.single.opponentName);
    });

    await _waitUntil(() => events.length == 2 && history.length == 2);
    expect(events, ['Repas du club', 'Tournoi de printemps']);
    expect(history, ['FC Ancien', 'FC Nouveau']);
  });

  test('la disponibilité d’un match n’est demandée qu’une fois à la fois',
      () async {
    final repository = SupabaseMatchAvailabilityRepository(client());

    await Future.wait([
      repository.fetchMyAvailability('m1'),
      repository.fetchMyAvailability('m1'),
      repository.fetchMyAvailability('m2'),
    ]);

    expect(server.hits('/rest/v1/rpc/get_my_match_availability'), 2);
  });

  test('le profil n’est demandé qu’une fois à la fois', () async {
    final repository = AuthRepository(client());

    final profiles = await Future.wait([
      repository.fetchProfile(),
      repository.fetchProfile(),
    ]);
    expect(server.hits('/rest/v1/rpc/get_my_profile'), 1);
    expect(profiles.first?.firstName, 'Karim');

    // Une fois la réponse reçue, une nouvelle demande repart au serveur.
    await repository.fetchProfile();
    expect(server.hits('/rest/v1/rpc/get_my_profile'), 2);
  });

  group('calendrier', () {
    ProviderContainer containerWith(_FakeMatchesRepository repository) {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => _SignedInController()),
          matchesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('deux chargements simultanés ne font qu’une série de requêtes',
        () async {
      final repository = _FakeMatchesRepository();
      final controller =
          containerWith(repository).read(matchesControllerProvider.notifier);

      await Future.wait([
        controller.load(allSeasons: true),
        controller.load(allSeasons: true),
      ]);

      expect(repository.seasonLoads, 1);
      expect(repository.matchLoads, 1);
    });

    test(
      'une relecture immédiate réutilise le snapshot sauf refresh forcé',
      () async {
        final repository = _FakeMatchesRepository();
        final controller =
            containerWith(repository).read(matchesControllerProvider.notifier);

        await controller.load(allSeasons: true);
        await controller.load(allSeasons: true);

        expect(repository.seasonLoads, 1);
        expect(repository.opponentLoads, 1);
        expect(repository.matchLoads, 1);

        await controller.load(allSeasons: true, forceRefresh: true);

        expect(repository.seasonLoads, 2);
        expect(repository.opponentLoads, 2);
        expect(repository.matchLoads, 2);
      },
    );

    test('saisons, adversaires et matchs partent en même temps', () async {
      final repository = _FakeMatchesRepository()
        ..seasonsGate = Completer<void>();
      final controller =
          containerWith(repository).read(matchesControllerProvider.notifier);

      final load = controller.load(allSeasons: true);
      await _waitUntil(() => repository.seasonLoads == 1);

      // Les saisons ne sont pas encore arrivées : les autres lectures sont
      // pourtant déjà parties.
      expect(repository.opponentLoads, 1);
      expect(repository.matchLoads, 1);

      repository.seasonsGate!.complete();
      await load;
    });

    test('sans réseau, le calendrier garde la dernière copie de l’appareil',
        () async {
      final online = _FakeMatchesRepository();
      await containerWith(online)
          .read(matchesControllerProvider.notifier)
          .load(allSeasons: true);

      final offline = _FakeMatchesRepository()..failure = StateError('hors');
      final container = containerWith(offline);
      await container
          .read(matchesControllerProvider.notifier)
          .load(allSeasons: true);

      final state = container.read(matchesControllerProvider);
      expect(state.matches.map((match) => match.id), ['m1']);
      expect(state.error, isNull);
    });

    test('la copie de l’appareil appartient au joueur connecté', () async {
      await containerWith(_FakeMatchesRepository())
          .read(matchesControllerProvider.notifier)
          .load(allSeasons: true);

      await _signInAs('user-2');
      addTearDown(() => _signInAs('user-1'));
      final offline = _FakeMatchesRepository()..failure = StateError('hors');
      final container = containerWith(offline);
      await container
          .read(matchesControllerProvider.notifier)
          .load(allSeasons: true);

      final state = container.read(matchesControllerProvider);
      expect(state.matches, isEmpty);
      expect(state.error, isNotNull);
    });
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition jamais atteinte');
}

String _base64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// Installe une session locale non vérifiée, suffisante pour que
/// l'application sache quel joueur est connecté. Aucun serveur d'identité
/// n'est contacté.
Future<void> _signInAs(String userId) async {
  final expiresAt =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000;
  final token = [
    _base64({'alg': 'HS256', 'typ': 'JWT'}),
    _base64({
      'sub': userId,
      'exp': expiresAt,
      'role': 'authenticated',
      'aud': 'authenticated',
    }),
    'signature',
  ].join('.');
  await supabase.Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': expiresAt,
      'refresh_token': 'refresh-$userId',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

/// Faux serveur Supabase : compte les requêtes par chemin et peut retenir
/// une réponse pour observer ce qui s'affiche en attendant.
class _FakeServer {
  _FakeServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeServer> start() async =>
      _FakeServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _hits = <String, int>{};
  Completer<void>? _gate;
  String eventTitle = 'Repas du club';
  String historicalOpponent = 'FC Ancien';

  String get url => 'http://127.0.0.1:${_server.port}';

  int hits(String path) => _hits[path] ?? 0;

  Completer<void> holdNextResponse() => _gate = Completer<void>();

  void reset() {
    _hits.clear();
    _gate = null;
    eventTitle = 'Repas du club';
    historicalOpponent = 'FC Ancien';
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    _hits[path] = hits(path) + 1;
    await request.drain<void>();
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      await gate.future;
    }
    final Object? body = switch (path) {
      '/rest/v1/club_events' => [
          {
            'id': 'e1',
            'season_id': 's1',
            'title': eventTitle,
            'starts_at': '2026-10-10T18:00:00Z',
            'location': 'Club house',
            'created_by': 'admin',
          },
        ],
      '/rest/v1/rpc/get_all_historical_match_results' => [
          {
            'id': 'h1',
            'match_date': '2019-05-12',
            'opponent_name': historicalOpponent,
            'score_as_grinta': 3,
            'score_adverse': 1,
            'is_home': true,
          },
        ],
      '/rest/v1/rpc/get_my_profile' => {
          'id': 'user-1',
          'first_name': 'Karim',
          'last_name': 'Test',
          'role': 'pronostiqueur',
          'is_goalkeeper': false,
          'is_active': true,
        },
      _ => null,
    };
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}

class _FakeMatchesRepository implements MatchesRepository {
  int seasonLoads = 0;
  int opponentLoads = 0;
  int matchLoads = 0;
  Completer<void>? seasonsGate;

  /// Refus du serveur sur la première lecture attendue (les saisons). Les
  /// autres lectures répondent : si elles échouaient aussi, leur erreur ne
  /// serait jamais récupérée par l'application et ferait échouer le test.
  Object? failure;

  void _failIfOffline() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSeasons() async {
    seasonLoads += 1;
    await seasonsGate?.future;
    _failIfOffline();
    return [
      {'id': 's1', 'name': '2026-2027', 'status': 'open'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOpponents() async {
    opponentLoads += 1;
    return const [];
  }

  @override
  Future<List<MatchModel>> fetchMatches({String? seasonId}) async {
    matchLoads += 1;
    return [
      MatchModel(
        id: 'm1',
        seasonId: 's1',
        opponentId: 'o1',
        kickoffAt: DateTime.utc(2026, 10, 4, 19),
        isHome: true,
        plannedDurationMinutes: 90,
        status: 'a_venir',
        grintaScore: null,
        opponentScore: null,
        opponentName: 'FC Test',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInController extends AuthController {
  _SignedInController() : super(_FakeAuthRepository()) {
    state = const AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: AuthProfile(
        id: 'user-1',
        firstName: 'Karim',
        lastName: 'Test',
        role: AuthRole.pronostiqueur,
        isGoalkeeper: false,
        isActive: true,
        mustChangePassword: false,
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
