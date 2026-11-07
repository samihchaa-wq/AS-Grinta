import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_profile_cache.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Ouverture : le dernier profil confirmé s'affiche tout de suite, et la
/// réponse du serveur fait toujours foi.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AuthProfileCache cacheFor(String? userId) =>
      AuthProfileCache(currentUserId: () => userId);

  test('le profil gardé s’affiche avant la réponse du serveur', () async {
    await cacheFor('user-1').remember(_makeProfile());
    final server = Completer<AuthProfile?>();
    final repository = _Repository(server.future);
    final controller =
        AuthController(repository, profileCache: cacheFor('user-1'));
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await _flush();
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.isAuthenticated, isTrue);
    expect(controller.state.profile?.firstName, 'Karim');

    // Le serveur répond : sa version remplace la copie.
    server.complete(_makeProfile(firstName: 'Karim (serveur)'));
    await _flush();
    expect(controller.state.profile?.firstName, 'Karim (serveur)');
  });

  test('un compte devenu inactif est déconnecté malgré la copie', () async {
    await cacheFor('user-1').remember(_makeProfile());
    final server = Completer<AuthProfile?>();
    final repository = _Repository(server.future);
    final controller =
        AuthController(repository, profileCache: cacheFor('user-1'));
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await _flush();
    expect(controller.state.isAuthenticated, isTrue);

    server.complete(_makeProfile(status: 'archived'));
    await _flush();
    expect(controller.state.isAuthenticated, isFalse);
    expect(repository.signedOut, isTrue);
    expect(await cacheFor('user-1').read(), isNull);
  });

  test('sans profil confirmé par le serveur, la copie n’autorise rien',
      () async {
    await cacheFor('user-1').remember(_makeProfile());
    final server = Completer<AuthProfile?>();
    final repository = _Repository(server.future);
    final controller =
        AuthController(repository, profileCache: cacheFor('user-1'));
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);

    await _flush();
    server.complete(null);
    await _flush();
    expect(controller.state.isAuthenticated, isFalse);
    expect(controller.state.profile, isNull);
    expect(await cacheFor('user-1').read(), isNull);
  });

  test('la copie d’un autre compte n’est jamais lue', () async {
    await cacheFor('user-1').remember(_makeProfile());
    expect(await cacheFor('user-2').read(), isNull);
  });

  test('un compte en attente ou à mot de passe imposé n’est pas gardé',
      () async {
    await cacheFor('user-1').remember(_makeProfile(status: 'pending'));
    expect(await cacheFor('user-1').read(), isNull);
    await cacheFor('user-1').remember(_makeProfile(mustChangePassword: true));
    expect(await cacheFor('user-1').read(), isNull);
  });

  test('la déconnexion efface la copie', () async {
    await cacheFor('user-1').remember(_makeProfile());
    final repository = _Repository(Future.value(_makeProfile()));
    final controller =
        AuthController(repository, profileCache: cacheFor('user-1'));
    addTearDown(controller.dispose);
    addTearDown(repository.dispose);
    await _flush();

    await controller.signOut();
    expect(await cacheFor('user-1').read(), isNull);
  });

  test('la copie garde le rôle et l’identité du profil', () async {
    await cacheFor('user-1').remember(_makeProfile(role: AuthRole.admin));
    final read = await cacheFor('user-1').read();
    expect(read?.id, 'user-1');
    expect(read?.role, AuthRole.admin);
    expect(read?.isActive, isTrue);
  });
}

AuthProfile _makeProfile({
  String firstName = 'Karim',
  String status = 'active',
  bool mustChangePassword = false,
  AuthRole role = AuthRole.pronostiqueur,
}) {
  return AuthProfile(
    id: 'user-1',
    username: 'karim',
    firstName: firstName,
    lastName: 'Test',
    role: role,
    isGoalkeeper: false,
    isActive: status == 'active',
    status: status,
    mustChangePassword: mustChangePassword,
  );
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Repository implements AuthRepository {
  _Repository(this._serverProfile);

  final Future<AuthProfile?> _serverProfile;
  final StreamController<supabase.AuthState> _auth =
      StreamController<supabase.AuthState>.broadcast();
  bool signedOut = false;

  Future<void> dispose() => _auth.close();

  @override
  bool get hasSession => !signedOut;

  @override
  Stream<supabase.AuthState> get authStateChanges => _auth.stream;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) =>
      _serverProfile;

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) async =>
      _makeProfile(firstName: firstName);

  @override
  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async =>
      _makeProfile();

  @override
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async =>
      'test-user';
}
