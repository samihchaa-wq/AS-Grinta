import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('AuthController', () {
    test('loads an active profile on startup', () async {
      final repository = _FakeAuthRepository(fetchResults: [_activeProfile]);
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isTrue);
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
      expect(controller.state.profile, isNull);
      expect(controller.state.error, isNull);
    });

    test('signIn authenticates after the post-login refresh', () async {
      final initialRefresh = Completer<AuthProfile?>();
      final repository = _FakeAuthRepository(
        fetchResults: [initialRefresh.future, _activeProfile],
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      final signInFuture = controller.signIn(
        username: 'samih',
        password: 'password123',
      );
      initialRefresh.complete(null);
      await signInFuture;

      expect(repository.signInCalls, 1);
      expect(repository.fetchRetryFlags, [false, true]);
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.profile, same(_activeProfile));
      expect(controller.state.error, isNull);
    });

    test('inactive profiles are signed out and rejected', () async {
      final repository = _FakeAuthRepository(fetchResults: [_inactiveProfile]);
      final controller = AuthController(repository);
      addTearDown(controller.dispose);

      await _flushAsync();

      expect(repository.signOutCalls, 1);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.profile, isNull);
      expect(
        controller.state.error,
        'Ton compte doit être validé par l’admin avant de pouvoir te connecter.',
      );
    });

    test('signIn exposes a stable user-facing error on failure', () async {
      final repository = _FakeAuthRepository(
        fetchResults: [null],
        signInError: StateError('backend failure'),
      );
      final controller = AuthController(repository);
      addTearDown(controller.dispose);
      await _flushAsync();

      await controller.signIn(username: 'samih', password: 'wrong-password');

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.profile, isNull);
      expect(
        controller.state.error,
        'Connexion impossible. Vérifie ton identifiant et ton mot de passe.',
      );
    });

    test('signOut clears the authenticated state', () async {
      final repository = _FakeAuthRepository(fetchResults: [_activeProfile]);
      final controller = AuthController(repository);
      addTearDown(controller.dispose);
      await _flushAsync();

      await controller.signOut();

      expect(repository.signOutCalls, 1);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isAuthenticated, isFalse);
      expect(controller.state.profile, isNull);
      expect(controller.state.error, isNull);
    });

    test(
      'ignores a refresh result that became stale after signedOut',
      () async {
        final pendingRefresh = Completer<AuthProfile?>();
        final repository = _FakeAuthRepository(
          fetchResults: [pendingRefresh.future],
        );
        final controller = AuthController(repository);
        addTearDown(controller.dispose);

        repository.emit(supabase.AuthChangeEvent.signedOut);
        pendingRefresh.complete(_activeProfile);
        await _flushAsync();

        expect(controller.state.isLoading, isFalse);
        expect(controller.state.isAuthenticated, isFalse);
        expect(controller.state.profile, isNull);
      },
    );
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
  mustChangePassword: false,
);

const _inactiveProfile = AuthProfile(
  id: 'pending-user',
  username: 'pending',
  firstName: 'Pending',
  lastName: 'User',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: false,
  mustChangePassword: false,
);

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required List<Object?> fetchResults, this.signInError})
    : _fetchResults = List<Object?>.from(fetchResults);

  final List<Object?> _fetchResults;
  final Object? signInError;
  final StreamController<supabase.AuthState> _authController =
      StreamController<supabase.AuthState>.broadcast();

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
  }

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    return _activeProfile;
  }

  @override
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    return 'samihc';
  }
}
