import 'dart:async';

import 'package:as_grinta/core/widgets/grinta_status_banner.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Une erreur de connexion reste affichée dans un bandeau d'erreur de l'écran
/// de connexion, et non dans un message éphémère qui disparaît avant d'avoir
/// été lu.
void main() {
  Future<void> pumpSignIn(WidgetTester tester, {String? error}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(error),
          ),
        ],
        child: const MaterialApp(home: AuthSignInPage()),
      ),
    );
    await tester.pump();
  }

  GrintaStatusBanner banner(WidgetTester tester) =>
      tester.widget<GrintaStatusBanner>(find.byType(GrintaStatusBanner));

  testWidgets('l’erreur reste affichée dans un bandeau d’erreur',
      (tester) async {
    const error = 'Connexion au serveur impossible. Vérifie ton réseau.';
    await pumpSignIn(tester, error: error);

    expect(banner(tester).tone, GrintaStatusTone.error);
    expect(banner(tester).title, 'Connexion impossible');
    expect(find.text(error), findsOneWidget);

    // Bien après la durée d'un message éphémère, l'erreur est toujours là.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text(error), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('un compte inactif est annoncé comme un accès refusé',
      (tester) async {
    await pumpSignIn(tester, error: 'Ce compte n’est pas actif.');

    expect(banner(tester).tone, GrintaStatusTone.error);
    expect(find.text('Accès refusé'), findsOneWidget);
    expect(find.text('Ce compte n’est pas actif.'), findsOneWidget);
  });

  testWidgets('sans erreur, aucun bandeau', (tester) async {
    await pumpSignIn(tester);

    expect(find.byType(GrintaStatusBanner), findsNothing);
  });
}

class _StaticAuthController extends AuthController {
  _StaticAuthController(String? error) : super(_FakeAuthRepository()) {
    state = AuthState(isLoading: false, error: error);
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
