import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/app/router/app_router.dart';
import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/data/feature_flags_repository.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _player = AuthProfile(
  id: 'player',
  firstName: 'Joueur',
  lastName: 'Test',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);

const _signedIn = AuthState(
  isLoading: false,
  isAuthenticated: true,
  hasSession: true,
  profile: _player,
);

const _effectif = '/matches/m1/lineup?section=effectif';
final _loadingEffectif =
    '/auth/loading?redirect=${Uri.encodeComponent(_effectif)}';

String? _redirect(String location, {required bool? sportsEnabled}) {
  final uri = Uri.parse(location);
  return resolveAuthRedirect(
    authState: _signedIn,
    uri: uri,
    matchedLocation: uri.path,
    sportsManagementEnabled: sportsEnabled,
  );
}

void main() {
  group('page sportive ouverte pendant le chargement des réglages', () {
    test('elle attend sur l’écran de chargement avec sa destination', () {
      expect(_redirect(_effectif, sportsEnabled: null), _loadingEffectif);
    });

    test('l’écran de chargement ne décide rien tant que rien n’est connu', () {
      expect(_redirect(_loadingEffectif, sportsEnabled: null), isNull);
    });

    test('réglages connus et gestion active : la destination est rendue', () {
      expect(_redirect(_loadingEffectif, sportsEnabled: true), _effectif);
      expect(_redirect(_effectif, sportsEnabled: true), isNull);
    });

    test('réglages connus et gestion coupée : repli habituel sur les pronos',
        () {
      expect(
        _redirect(_loadingEffectif, sportsEnabled: false),
        '/matches/m1/prediction',
      );
      expect(
        _redirect(_effectif, sportsEnabled: false),
        '/matches/m1/prediction',
      );
    });

    test('après la connexion, une page sportive attend aussi les réglages', () {
      final signIn = '/auth/sign-in?redirect=${Uri.encodeComponent(_effectif)}';
      expect(_redirect(signIn, sportsEnabled: null), _loadingEffectif);
      expect(_redirect(signIn, sportsEnabled: true), _effectif);
      expect(
        _redirect(signIn, sportsEnabled: false),
        '/matches/m1/prediction',
      );
    });

    test('une page non sportive n’attend pas les réglages', () {
      expect(_redirect('/matches/m1', sportsEnabled: null), isNull);
      expect(_redirect('/matches', sportsEnabled: null), isNull);
    });
  });

  group('routeur complet', () {
    Future<GoRouter> pumpRouter(
      WidgetTester tester,
      ValueNotifier<bool?> sportsEnabled,
    ) async {
      final router = GoRouter(
        initialLocation: _effectif,
        refreshListenable: sportsEnabled,
        redirect: (context, state) => resolveAuthRedirect(
          authState: _signedIn,
          uri: state.uri,
          matchedLocation: state.matchedLocation,
          sportsManagementEnabled: sportsEnabled.value,
        ),
        routes: [
          for (final path in [
            '/matches',
            '/matches/:matchId',
            '/matches/:matchId/lineup',
            '/matches/:matchId/prediction',
            '/auth/loading',
            '/auth/sign-in',
          ])
            GoRoute(
              path: path,
              builder: (_, state) => Text(state.uri.toString()),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    String currentLocation(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('la page Effectif s’ouvre une fois les réglages chargés',
        (tester) async {
      final sportsEnabled = ValueNotifier<bool?>(null);
      addTearDown(sportsEnabled.dispose);
      final router = await pumpRouter(tester, sportsEnabled);

      expect(currentLocation(router), _loadingEffectif);

      sportsEnabled.value = true;
      await tester.pumpAndSettle();

      expect(currentLocation(router), _effectif);
    });

    testWidgets('gestion coupée : le repli se fait une fois les réglages lus',
        (tester) async {
      final sportsEnabled = ValueNotifier<bool?>(null);
      addTearDown(sportsEnabled.dispose);
      final router = await pumpRouter(tester, sportsEnabled);

      sportsEnabled.value = false;
      await tester.pumpAndSettle();

      expect(currentLocation(router), '/matches/m1/prediction');
    });
  });

  group('routeur de l’application', () {
    testWidgets(
        'à la fin de la connexion, la page Effectif attend les réglages au '
        'lieu de partir vers les pronos', (tester) async {
      final auth = _TestAuthController();
      final flags = _ControlledRepository();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          featureFlagsRepositoryProvider.overrideWithValue(flags),
        ],
      );
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      router.go(_effectif);
      await tester.pump();
      await tester.pump();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        _loadingEffectif,
      );

      // La session est restaurée : les réglages du club ne sont pas encore
      // lus. Avant le correctif, le routeur voyait ici « gestion coupée ».
      auth.emit(_signedIn);
      await tester.pump();
      await tester.pump();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        _loadingEffectif,
      );

      // Arrête les minuteries de l'écran de chargement et de la session.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });

  group('état des réglages vu par le routeur', () {
    test('inconnu pendant le premier chargement, puis la vraie valeur',
        () async {
      final repository = _ControlledRepository();
      final sessionReady = StateProvider<bool>((ref) => false);
      final container = ProviderContainer(
        overrides: [
          featureFlagsRepositoryProvider.overrideWithValue(repository),
          featureFlagsSessionReadyProvider.overrideWith(
            (ref) => ref.watch(sessionReady),
          ),
        ],
      );
      addTearDown(container.dispose);
      final states = <bool?>[];
      container.listen<bool?>(
        sportsManagementRoutingStateProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      await container.read(featureFlagsControllerProvider.future);

      // Connexion : la valeur de remplacement posée avant la session ne
      // compte pas, le routeur doit attendre la vraie lecture.
      container.read(sessionReady.notifier).state = true;
      expect(container.read(sportsManagementRoutingStateProvider), isNull);

      repository.pending.complete(
        const FeatureFlagsSnapshot(
          sportsManagement: SportsManagementFeature.permanentFallback(),
          sourceAvailable: true,
        ),
      );
      await container.read(featureFlagsControllerProvider.future);

      expect(container.read(sportsManagementRoutingStateProvider), isTrue);
      expect(states.last, isTrue);
      expect(states, contains(null));
    });
  });
}

class _ControlledRepository implements FeatureFlagsRepository {
  final pending = Completer<FeatureFlagsSnapshot>();

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() => pending.future;

  @override
  Stream<FeatureFlagChangeSignal> watchSportsManagementChanges() =>
      const Stream<FeatureFlagChangeSignal>.empty();

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) {
    throw UnimplementedError();
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController() : super(_FakeAuthRepository());

  void emit(AuthState value) => state = value;
}

class _FakeAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

  // La session se restaure lentement : l'écran reste sur le chargement tant
  // que le test ne publie pas lui-même l'état connecté.
  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) =>
      Completer<AuthProfile?>().future;

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    return 'test-user';
  }
}
