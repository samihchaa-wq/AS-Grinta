import 'dart:async';

import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/profile/presentation/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Écran Profil, avec un faux dépôt de comptes : ce qui est enregistré, ce
/// qui est refusé avant tout envoi, et ce que voit le joueur dans chaque cas.
void main() {
  late _FakeAuthRepository repository;

  setUp(() => repository = _FakeAuthRepository());

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _SignedInAuthController(repository),
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pump();
  }

  Finder field(String label) =>
      find.widgetWithText(TextField, label, skipOffstage: false);

  Future<void> save(WidgetTester tester) async {
    final button = find.text('Enregistrer les modifications');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('pré-remplit le profil du joueur connecté', (tester) async {
    await pumpProfile(tester);

    expect(find.text('Karim Benali'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('Prénom')).controller!.text,
      'Karim',
    );
    expect(tester.widget<TextField>(field('Nom')).controller!.text, 'Benali');
    expect(
      tester.widget<TextField>(field('Surnom (optionnel)')).controller!.text,
      'Le Mur',
    );
  });

  testWidgets('enregistre les noms nettoyés et confirme l’enregistrement',
      (tester) async {
    await pumpProfile(tester);

    await tester.enterText(field('Prénom'), '  Karim ');
    await tester.enterText(field('Surnom (optionnel)'), ' Zizou ');
    await save(tester);

    expect(repository.savedProfiles, [
      (firstName: 'Karim', lastName: 'Benali', surnom: 'Zizou'),
    ]);
    expect(find.text('Profil enregistré.'), findsOneWidget);
  });

  testWidgets('refuse un prénom invalide sans rien envoyer', (tester) async {
    await pumpProfile(tester);

    await tester.enterText(field('Prénom'), 'Karim2');
    await tester.enterText(field('Nom'), '');
    await save(tester);

    expect(repository.savedProfiles, isEmpty);
    expect(
      find.text('Uniquement des lettres : ni emoji, ni chiffre, ni symbole.'),
      findsOneWidget,
    );
    expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
  });

  testWidgets('un refus du serveur se voit', (tester) async {
    repository.failProfileUpdate = true;
    await pumpProfile(tester);

    await save(tester);

    expect(repository.savedProfiles, hasLength(1));
    // Le bandeau de l'écran et le message de confirmation disent l'échec.
    expect(
      find.text('Le profil n’a pas pu être enregistré.'),
      findsNWidgets(2),
    );
    expect(find.text('Profil enregistré.'), findsNothing);
  });

  testWidgets('le changement de mot de passe applique la règle commune',
      (tester) async {
    await pumpProfile(tester);

    final button = find.text('Changer le mot de passe');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final password = find.widgetWithText(TextField, 'Nouveau mot de passe');
    final confirmation = find.widgetWithText(TextField, 'Confirmation');
    final submit = find.widgetWithText(FilledButton, 'Modifier');

    await tester.enterText(password, 'court');
    await tester.enterText(confirmation, 'court');
    await tester.tap(submit);
    await tester.pump();
    expect(
      find.text('Le mot de passe doit contenir entre 12 et 72 caractères.'),
      findsOneWidget,
    );

    await tester.enterText(password, 'GrandePhrase2026');
    await tester.enterText(confirmation, 'GrandePhrase2027');
    await tester.tap(submit);
    await tester.pump();
    expect(
      find.text('Les deux mots de passe ne correspondent pas.'),
      findsOneWidget,
    );

    // Tant que la saisie est refusée, rien n'est envoyé et la fenêtre reste
    // ouverte. La fermeture n'est pas testée ici : l'écran libère ses champs
    // avant la fin de l'animation de fermeture, ce que le mode test refuse.
    expect(repository.updatedPasswords, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}

const _profile = AuthProfile(
  id: 'profile-1',
  username: 'karim',
  firstName: 'Karim',
  lastName: 'Benali',
  surnom: 'Le Mur',
  role: AuthRole.pronostiqueur,
  isGoalkeeper: false,
  isActive: true,
  mustChangePassword: false,
);

class _SignedInAuthController extends AuthController {
  _SignedInAuthController(super.repository) {
    state = const AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: _profile,
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<supabase.AuthState>.broadcast();
  final savedProfiles =
      <({String firstName, String lastName, String? surnom})>[];
  final updatedPasswords = <String>[];
  bool failProfileUpdate = false;

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async =>
      _profile;

  @override
  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    String? surnom,
  }) async {
    savedProfiles.add(
      (firstName: firstName, lastName: lastName, surnom: surnom),
    );
    if (failProfileUpdate) throw StateError('refus du serveur');
    return AuthProfile(
      id: _profile.id,
      username: _profile.username,
      firstName: firstName,
      lastName: lastName,
      surnom: surnom ?? '',
      role: _profile.role,
      isGoalkeeper: false,
      isActive: true,
      mustChangePassword: false,
    );
  }

  @override
  Future<void> updatePassword(String password) async {
    updatedPasswords.add(password);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
