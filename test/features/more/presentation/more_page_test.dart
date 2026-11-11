import 'dart:async';
import 'dart:typed_data';

import 'package:as_grinta/features/admin/data/admin_repository.dart';
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
  '/admin/stadiums',
];

Future<_FakeAuthRepository> _pumpMorePage(
  WidgetTester tester, {
  required AuthProfile profile,
  required bool sportsEnabled,
  _FakeClubAdminRepository? clubRepository,
}) async {
  final repository = _FakeAuthRepository(profile);
  final club = clubRepository ?? _FakeClubAdminRepository();
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
        adminRepositoryProvider.overrideWithValue(club),
        adminDashboardProvider.overrideWith(
          (ref) => ref.read(adminRepositoryProvider).fetchDashboard(),
        ),
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
    // Écran de téléphone : la page dépasse la petite fenêtre de test par
    // défaut.
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpMorePage(tester, profile: _admin, sportsEnabled: true);

    expect(find.text('Karim Benali'), findsOneWidget);
    expect(find.text('@karim.b · Admin'), findsOneWidget);
    // La carte du compte remplace l'ancienne ligne « Profil ».
    expect(find.text('Profil'), findsNothing);

    expect(find.text('MON COMPTE'), findsOneWidget);
    expect(find.text('CLUB · ADMIN'), findsOneWidget);
    // Les notifications s'ouvrent désormais depuis la cloche de l'en-tête.
    expect(find.text('Notifications'), findsNothing);
    for (final title in [
      'Indisponibilité',
      'Liste d’attente',
      'Effectif',
      'Équipes & stades',
      'Finir la saison',
      'Se déconnecter',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }

    expect(find.text('Réglages'), findsNothing);
    // Les deux groupes sont chacun une seule carte.
    expect(
      find.ancestor(
          of: find.text('Indisponibilité'), matching: find.byType(Card)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Indisponibilité'),
          matching: find.byType(Card),
        ),
        matching: find.text('Liste d’attente'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an admin opens the stadiums directly from Paramètres', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpMorePage(tester, profile: _admin, sportsEnabled: true);

    expect(find.text('Réglages'), findsNothing);
    expect(find.text('Équipes & stades'), findsOneWidget);
    await tester.ensureVisible(find.text('Équipes & stades'));
    await tester.tap(find.text('Équipes & stades'));
    await tester.pumpAndSettle();
    expect(find.text('page /admin/stadiums'), findsOneWidget);
  });

  testWidgets('finir la saison demande confirmation depuis Paramètres',
      (tester) async {
    final club = _FakeClubAdminRepository();
    await _pumpMorePage(
      tester,
      profile: _admin,
      sportsEnabled: true,
      clubRepository: club,
    );
    await tester.ensureVisible(find.text('Finir la saison'));
    await tester.tap(find.text('Finir la saison'));
    await tester.pumpAndSettle();
    expect(find.text('Finir la saison ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(club.seasonStatusChanges, isEmpty);

    await tester.tap(find.text('Finir la saison'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmer'));
    await tester.pumpAndSettle();
    expect(club.seasonStatusChanges, [('s-1', 'archived')]);
    expect(find.text('Créer une saison'), findsOneWidget);
  });

  testWidgets(
      'après avoir fini la saison, on peut en créer une depuis Paramètres',
      (tester) async {
    final club = _FakeClubAdminRepository()..seasons = const [];
    await _pumpMorePage(
      tester,
      profile: _admin,
      sportsEnabled: true,
      clubRepository: club,
    );
    await tester.ensureVisible(find.text('Créer une saison'));
    await tester.tap(find.text('Créer une saison'));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle saison'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '2027-2028');
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle();

    expect(club.createdSeasons, ['2027-2028']);
    expect(find.text('Finir la saison'), findsOneWidget);
  });

  testWidgets('a player without sports management only sees their account', (
    tester,
  ) async {
    await _pumpMorePage(tester, profile: _player, sportsEnabled: false);

    expect(find.text('Julien Martin'), findsOneWidget);
    expect(find.text('@julien · Utilisateur'), findsOneWidget);
    // Sans gestion sportive, le groupe « Mon compte » n'a plus de ligne :
    // il disparaît plutôt que de laisser une carte vide.
    expect(find.text('MON COMPTE'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Se déconnecter'), findsOneWidget);

    expect(find.text('CLUB · ADMIN'), findsNothing);
    expect(find.text('Effectif'), findsNothing);
    expect(find.text('Réglages'), findsNothing);
    expect(find.text('Équipes & stades'), findsNothing);
    expect(find.text('Finir la saison'), findsNothing);
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

class _FakeClubAdminRepository implements AdminRepository {
  List<AdminSeasonItem> seasons = const [
    AdminSeasonItem(id: 's-1', name: '2026-2027', status: 'open'),
  ];
  final seasonStatusChanges = <(String, String)>[];
  final createdSeasons = <String>[];

  @override
  Future<AdminDashboardData> fetchDashboard() async => AdminDashboardData(
        profiles: const [],
        seasons: seasons,
        openSeasonId: seasons.where((s) => s.status == 'open').firstOrNull?.id,
      );

  @override
  Future<void> setSeasonStatus(String seasonId, String status) async {
    seasonStatusChanges.add((seasonId, status));
    seasons = [
      for (final season in seasons)
        if (season.id == seasonId)
          AdminSeasonItem(id: season.id, name: season.name, status: status)
        else
          season,
    ];
  }

  @override
  Future<String> createSeason(String name) async {
    createdSeasons.add(name);
    seasons = [
      AdminSeasonItem(id: 'new', name: name, status: 'open'),
      ...seasons,
    ];
    return 'new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
