import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('AuthController', () {
    test('loads an active profile on startup', () async {
      final repository = _FakeAuthRepository(
        fetchResults: [_activeProfile],
        hasSession: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.hasSession, isTrue);
      expect(controller.state.profile, same(_activeProfile));
      expect(controller.state.error, isNull);
    });

    test('keeps the user signed out when no session profile exists', () async {
      final repository = _FakeAuthRepository(fetchResults: [null]);
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isFalse);
      expect(controller.state.profile, isNull);
      expect(controller.state.error, isNull);
    });

    test(
        'preserves the session when profile loading is temporarily unavailable',
        () async {
      final repository = _FakeAuthRepository(
        fetchResults: [StateError('temporary backend failure')],
        hasSession: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isTrue);
      expect(controller.state.profile, isNull);
      expect(
        controller.state.error,
        'Connexion temporairement indisponible. Réessaie dans un instant.',
      );
      expect(repository.signOutCalls, 0);
    });

    test('signIn authenticates after the post-login refresh', () async {
      final initialRefresh = Completer<AuthProfile?>();
      final repository = _FakeAuthRepository(
        fetchResults: [initialRefresh.future, _activeProfile],
        hasSession: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      final signInFuture = controller.signIn(
        username: 'samih@example.com',
        password: 'password123',
      );
      initialRefresh.complete(null);
      await signInFuture;

      expect(repository.signInCalls, 1);
      expect(repository.fetchRetryFlags, [false, true]);
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.hasSession, isTrue);
      expect(controller.state.profile, same(_activeProfile));
      expect(controller.state.error, isNull);
    });

    test('pending profiles keep their session and waiting profile', () async {
      final repository = _FakeAuthRepository(
        fetchResults: [_pendingProfile],
        hasSession: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(repository.signOutCalls, 0);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isTrue);
      expect(controller.state.profile, same(_pendingProfile));
      expect(controller.state.profile?.isPending, isTrue);
      expect(controller.state.error, isNull);
    });

    test(
        'archived profiles preserve their rejection when signedOut fires during signOut',
        () async {
      final repository = _FakeAuthRepository(
        fetchResults: [_archivedProfile],
        hasSession: true,
        emitSignedOutDuringSignOut: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(repository.signOutCalls, 1);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isFalse);
      expect(controller.state.profile, isNull);
      expect(controller.state.error, 'Ce compte n’est pas actif.');
    });

    test('signIn reports invalid credentials without blaming the network',
        () async {
      final repository = _FakeAuthRepository(
        fetchResults: [null],
        signInError: const supabase.AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);
      await _flushAsync();

      await controller.signIn(
        username: 'samih@example.com',
        password: 'wrong-password',
      );

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isFalse);
      expect(controller.state.profile, isNull);
      expect(
        controller.state.error,
        'Connexion impossible. Vérifie ton identifiant et ton mot de passe.',
      );
    });

    test('signIn reports a temporary outage for non-credential failures',
        () async {
      final repository = _FakeAuthRepository(
        fetchResults: [null],
        signInError: StateError('backend failure'),
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);
      await _flushAsync();

      await controller.signIn(
        username: 'samih@example.com',
        password: 'password123',
      );

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isFalse);
      expect(controller.state.profile, isNull);
      expect(
        controller.state.error,
        'Connexion temporairement indisponible. Vérifie ta connexion et réessaie.',
      );
    });

    test('signOut clears the authenticated state', () async {
      final repository = _FakeAuthRepository(
        fetchResults: [_activeProfile],
        hasSession: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);
      await _flushAsync();

      await controller.signOut();

      expect(repository.signOutCalls, 1);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isFalse);
      expect(controller.state.profile, isNull);
      expect(controller.state.error, isNull);
    });

    test('ignores a refresh result that became stale after signedOut',
        () async {
      final pendingRefresh = Completer<AuthProfile?>();
      final repository = _FakeAuthRepository(
        fetchResults: [pendingRefresh.future],
        hasSession: true,
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      repository.emit(supabase.AuthChangeEvent.signedOut);
      repository.hasSession = false;
      pendingRefresh.complete(_activeProfile);
      await _flushAsync();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.hasSession, isFalse);
      expect(controller.state.profile, isNull);
    });
  });
}

const _activeProfile = AuthProfile(
  id: 'active-user',
  username: 'samih',
  firstName: 'Samih',
  lastName: 'Chaa',
  role: AuthRole.admin,
  isGoalkeeper: false,
  isActive: true,
  status: 'active',
  mustChangePassword: false,
);

const _pendingProfile = AuthProfile(
  id: 'pending-user',
  username: 'pending',
  firstName: 'Pending',
  lastName: 'User',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: false,
  status: 'pending',
  mustChangePassword: false,
);

const _archivedProfile = AuthProfile(
  id: 'archived-user',
  username: 'archived',
  firstName: 'Archived',
  lastName: 'User',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: false,
  status: 'archived',
  mustChangePassword: false,
);

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    required List<Object?> fetchResults,
    this.signInError,
    this.hasSession = false,
    this.emitSignedOutDuringSignOut = false,
  }) : _fetchResults = List<Object?>.from(fetchResults);

  final List<Object?> _fetchResults;
  final Object? signInError;
  final bool emitSignedOutDuringSignOut;
  final StreamController<supabase.AuthState> _authController =
      StreamController<supabase.AuthState>.broadcast();

  @override
  bool hasSession;

  int signInCalls = 0;
  int signOutCalls = 0;
  final List<bool> fetchRetryFlags = <bool>[];

  void emit(supabase.AuthChangeEvent event) {
    _authController.add(supabase.AuthState(event, null));
  }

  @override
  Stream<supabase.AuthState> get authStateChanges => _authController.stream;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async {
    fetchRetryFlags.add(retryAfterSignIn);
    if (_fetchResults.isEmpty) return null;
    final result = _fetchResults.removeAt(0);
    if (result is Future<AuthProfile?>) return result;
    if (result is Object && result is! AuthProfile) throw result;
    return result as AuthProfile?;
  }

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {
    signInCalls += 1;
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    hasSession = false;
    if (emitSignedOutDuringSignOut) {
      emit(supabase.AuthChangeEvent.signedOut);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) async {
    return _activeProfile;
  }

  @override
  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async {
    return _activeProfile;
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
