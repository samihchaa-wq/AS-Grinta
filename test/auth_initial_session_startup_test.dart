import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  test('initialSession does not invalidate the startup profile refresh', () async {
    final profileCompleter = Completer<AuthProfile?>();
    final repository = _StartupAuthRepository(
      profileCompleter: profileCompleter,
      hasSession: true,
    );
    final controller = AuthController(repository);
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    repository.emit(supabase.AuthChangeEvent.initialSession);
    profileCompleter.complete(_activeProfile);
    await _flushAsync();

    expect(repository.fetchRetryFlags, [false]);
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.isAuthenticated, isTrue);
    expect(controller.state.hasSession, isTrue);
    expect(controller.state.profile, same(_activeProfile));
    expect(controller.state.error, isNull);
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

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _StartupAuthRepository implements AuthRepository {
  _StartupAuthRepository({
    required this.profileCompleter,
    this.hasSession = false,
  });

  final Completer<AuthProfile?> profileCompleter;
  final StreamController<supabase.AuthState> _authController =
      StreamController<supabase.AuthState>.broadcast();

  @override
  bool hasSession;

  final List<bool> fetchRetryFlags = <bool>[];

  void emit(supabase.AuthChangeEvent event) {
    _authController.add(supabase.AuthState(event, null));
  }

  Future<void> dispose() => _authController.close();

  @override
  Stream<supabase.AuthState> get authStateChanges => _authController.stream;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) {
    fetchRetryFlags.add(retryAfterSignIn);
    return profileCompleter.future;
  }

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {
    hasSession = false;
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
