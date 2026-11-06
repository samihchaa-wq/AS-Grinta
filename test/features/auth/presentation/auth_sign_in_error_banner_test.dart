import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  Future<void> pumpWithError(WidgetTester tester, String error) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _ErrorAuthController(error),
          ),
        ],
        child: const MaterialApp(home: AuthSignInPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('l’erreur de connexion ne répète pas « Connexion impossible »',
      (tester) async {
    await pumpWithError(
      tester,
      'Connexion impossible. Vérifie ton identifiant et ton mot de passe.',
    );

    expect(find.text('Connexion impossible'), findsOneWidget);
    expect(
      find.text('Vérifie ton identifiant et ton mot de passe.'),
      findsOneWidget,
    );
    expect(find.textContaining('Connexion impossible.'), findsNothing);
  });

  testWidgets('un compte inactif garde son titre et son message',
      (tester) async {
    await pumpWithError(tester, 'Ce compte n’est pas actif.');

    expect(find.text('Accès refusé'), findsOneWidget);
    expect(find.text('Ce compte n’est pas actif.'), findsOneWidget);
  });

  testWidgets('un autre message reste affiché en entier', (tester) async {
    await pumpWithError(
      tester,
      'Connexion au serveur impossible. Vérifie ton réseau.',
    );

    expect(find.text('Connexion impossible'), findsOneWidget);
    expect(
      find.text('Connexion au serveur impossible. Vérifie ton réseau.'),
      findsOneWidget,
    );
  });
}

class _ErrorAuthController extends AuthController {
  _ErrorAuthController(String error) : super(_FakeAuthRepository()) {
    state = AuthState(isLoading: false, error: error);
  }
}

class _FakeAuthRepository implements AuthRepository {
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => false;

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
