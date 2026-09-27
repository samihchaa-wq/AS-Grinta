import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/preferences/data/push_subscriptions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// À la déconnexion, l'appareil est désinscrit des notifications push, pour
/// qu'un téléphone prêté ne reçoive plus celles du compte précédent. La
/// désinscription passe avant la déconnexion (la session sert à supprimer
/// l'abonnement enregistré), et son échec ne bloque jamais la déconnexion.
void main() {
  tearDown(() => AppLogger.sink = null);

  test('la déconnexion désinscrit d’abord cet appareil', () async {
    final events = <String>[];
    final auth = _FakeAuthRepository(events);
    final push = _FakePushRepository(events);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pushSubscriptionsRepositoryProvider.overrideWithValue(push),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).signOut();

    expect(events, ['push.disable', 'auth.signOut']);
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
    expect(container.read(authControllerProvider).error, isNull);
  });

  test('un échec de désinscription n’empêche pas la déconnexion', () async {
    final events = <String>[];
    final auth = _FakeAuthRepository(events);
    final push = _FakePushRepository(events, fail: true);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pushSubscriptionsRepositoryProvider.overrideWithValue(push),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).signOut();

    expect(events, ['push.disable', 'auth.signOut']);
    expect(container.read(authControllerProvider).isLoading, isFalse);
    expect(container.read(authControllerProvider).error, isNull);
  });
}

class _FakePushRepository implements PushSubscriptionsRepository {
  _FakePushRepository(this.events, {this.fail = false});

  final List<String> events;
  final bool fail;

  @override
  Future<void> disable() async {
    events.add('push.disable');
    if (fail) throw StateError('service worker indisponible');
  }

  @override
  Future<bool> enable() async => false;

  @override
  Future<bool> isSubscribed() async => true;

  @override
  Future<bool> isSupported() async => true;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.events);

  final List<String> events;
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => false;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async =>
      null;

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {
    events.add('auth.signOut');
  }

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
