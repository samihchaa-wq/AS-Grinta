import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/more/presentation/more_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _admin = AuthProfile(
  id: 'admin',
  username: 'karim.b',
  firstName: 'Karim',
  lastName: 'Benali',
  role: AuthRole.admin,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);

const _player = AuthProfile(
  id: 'player',
  username: 'julien',
  firstName: 'Julien',
  lastName: 'Martin',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);

/// Pages cibles réduites à leur chemin : le test vérifie où mène chaque
/// ligne, pas le contenu des écrans ouverts.
const _destinations = [
  '/profile',
  '/notifications',
  '/unavailability',
  '/waitlist',
  '/admin/waitlist',
  '/admin',
];

Future<_FakeAuthRepository> _pumpMorePage(
  WidgetTester tester, {
  required AuthProfile profile,
  required bool sportsEnabled,
}) async {
  final repository = _FakeAuthRepository(profile);
  final router = GoRouter(
    initialLocation: '/more',
    routes: [
      GoRoute(path: '/more', builder: (_, __) => const MorePage()),
      for (final path in _destinations)
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('page $path')),
        ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController(repository),
        ),
        sportsManagementEnabledProvider.overrideWithValue(sportsEnabled),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('an admin sees the account card and both setting groups', (
    tester,
  ) async {
    await _pumpMorePage(tester, profile: _admin, sportsEnabled: true);

    expect(find.text('Karim Benali'), findsOneWidget);
    expect(find.text('@karim.b · Admin'), findsOneWidget);
    // La carte du compte remplace l'ancienne ligne « Profil ».
    expect(find.text('Profil'), findsNothing);

    expect(find.text('MON COMPTE'), findsOneWidget);
    expect(find.text('CLUB · ADMIN'), findsOneWidget);
    for (final title in [
      'Notifications',
      'Indisponibilité',
      'Liste d’attente',
      'Équipes & stades',
      'Administration',
      'Se déconnecter',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }

    // Les deux groupes sont chacun une seule carte.
    expect(
      find.ancestor(
          of: find.text('Notifications'), matching: find.byType(Card)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Notifications'),
          matching: find.byType(Card),
        ),
        matching: find.text('Liste d’attente'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a player without sports management only sees their account', (
    tester,
  ) async {
    await _pumpMorePage(tester, profile: _player, sportsEnabled: false);

    expect(find.text('Julien Martin'), findsOneWidget);
    expect(find.text('@julien · Utilisateur'), findsOneWidget);
    expect(find.text('MON COMPTE'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);

    expect(find.text('CLUB · ADMIN'), findsNothing);
    expect(find.text('Équipes & stades'), findsNothing);
    expect(find.text('Administration'), findsNothing);
    expect(find.text('Indisponibilité'), findsNothing);
    expect(find.text('Liste d’attente'), findsNothing);
  });

  testWidgets('the account card is announced as a single button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpMorePage(tester, profile: _admin, sportsEnabled: true);

    expect(
      tester.getSemantics(find.text('Karim Benali')),
      isSemantics(
        label: 'Karim Benali\n@karim.b · Admin',
        hint: 'Ouvrir le profil',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('MON COMPTE')),
      isSemantics(label: 'Mon compte', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('the account card opens the profile', (tester) async {
    await _pumpMorePage(tester, profile: _player, sportsEnabled: true);

    await tester.tap(find.text('Julien Martin'));
    await tester.pumpAndSettle();

    expect(find.text('page /profile'), findsOneWidget);
  });

  testWidgets('a player opens the read-only waitlist', (tester) async {
    await _pumpMorePage(tester, profile: _player, sportsEnabled: true);

    await tester.tap(find.text('Liste d’attente'));
    await tester.pumpAndSettle();

    expect(find.text('page /waitlist'), findsOneWidget);
  });

  testWidgets('an admin opens the editable waitlist', (tester) async {
    await _pumpMorePage(tester, profile: _admin, sportsEnabled: true);

    await tester.tap(find.text('Liste d’attente'));
    await tester.pumpAndSettle();

    expect(find.text('page /admin/waitlist'), findsOneWidget);
  });

  testWidgets('sign out asks for confirmation before disconnecting', (
    tester,
  ) async {
    final repository = await _pumpMorePage(
      tester,
      profile: _player,
      sportsEnabled: true,
    );

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter ?'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(repository.signOutCalls, 0);

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Se déconnecter'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.signOutCalls, 1);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.profile);

  final AuthProfile profile;
  int signOutCalls = 0;
  final StreamController<supabase.AuthState> _events =
      StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async =>
      profile;

  @override
  Future<void> signInWithUsername({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async => signOutCalls += 1;

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) async =>
      profile;

  @override
  Future<AuthProfile> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileExt,
  }) async =>
      profile;

  @override
  Future<String> registerAccount({
    required String firstName,
    required String lastName,
    required String password,
  }) async =>
      'test-user';
}
