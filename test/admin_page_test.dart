import 'dart:async';

import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Écran Administration, avec un faux dépôt : les comptes rangés par statut,
/// les actions sur un compte et leur confirmation, la saison ouverte.
void main() {
  late _FakeAdminRepository repository;

  setUp(() => repository = _FakeAdminRepository());

  Future<void> pumpAdmin(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _SignedInAdminController(_FakeAuthRepository()),
          ),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AdminPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmDialog(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmer'));
    await tester.pumpAndSettle();
  }

  testWidgets('range les comptes validés et ceux en attente', (tester) async {
    repository.profiles = [
      _profile('admin-1', 'Samih', status: 'active', role: 'admin'),
      _profile('p-1', 'Karim', status: 'active'),
      _profile('p-2', 'Maxime', status: 'pending'),
    ];

    await pumpAdmin(tester);

    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Samih'), findsOneWidget);
    expect(find.text('Maxime'), findsNothing);

    await tester.tap(find.text('En attente'));
    await tester.pumpAndSettle();

    expect(find.text('Maxime'), findsOneWidget);
    expect(find.text('Karim'), findsNothing);
    expect(find.text('Valider ce compte'), findsOneWidget);
  });

  testWidgets('annonce l’absence de compte en attente', (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];

    await pumpAdmin(tester);
    await tester.tap(find.text('En attente'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun compte en attente.'), findsOneWidget);
  });

  testWidgets('archiver un compte demande confirmation puis l’enregistre',
      (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];

    await pumpAdmin(tester);
    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();
    expect(find.text('Archiver ce compte ?'), findsOneWidget);

    // Annuler ne change rien.
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect(repository.statusChanges, isEmpty);

    await tester.tap(find.text('Archiver'));
    await confirmDialog(tester);

    expect(repository.statusChanges, [('p-1', 'archived')]);
    expect(find.text('Compte archivé.'), findsOneWidget);
    // Le tableau est relu après l'action.
    expect(repository.dashboardLoads, 2);
  });

  testWidgets('refuser un compte en attente le supprime après confirmation',
      (tester) async {
    repository.profiles = [_profile('p-2', 'Maxime', status: 'pending')];

    await pumpAdmin(tester);
    await tester.tap(find.text('En attente'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refuser et supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Refuser et supprimer ce compte ?'), findsOneWidget);
    await confirmDialog(tester);

    expect(repository.deletedAccounts, ['p-2']);
    expect(find.text('Compte supprimé.'), findsOneWidget);
  });

  testWidgets('une action refusée par le serveur est signalée', (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];
    repository.failStatusChange = true;

    await pumpAdmin(tester);
    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archiver'));
    await confirmDialog(tester);

    expect(repository.statusChanges, [('p-1', 'archived')]);
    expect(find.text('Compte archivé.'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('son propre compte ne propose aucune action', (tester) async {
    repository.profiles = [
      _profile('admin-1', 'Samih', status: 'active', role: 'admin'),
    ];

    await pumpAdmin(tester);
    await tester.tap(find.text('Samih'));
    await tester.pumpAndSettle();

    expect(find.text('Toi'), findsOneWidget);
    expect(find.text('Archiver'), findsNothing);
    expect(find.text('Supprimer'), findsNothing);
  });

  testWidgets('un échec de chargement propose de réessayer', (tester) async {
    repository.failDashboard = true;

    await pumpAdmin(tester);
    expect(
      find.textContaining('Impossible de charger l’administration'),
      findsOneWidget,
    );

    repository.failDashboard = false;
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('Karim'), findsOneWidget);
  });

  testWidgets('le lien d’inscription est copié pour être partagé',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpAdmin(tester);
    await tester.tap(find.text('Lien d’inscription'));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied, startsWith('https://samihchaa-wq.github.io/AS-Grinta/'));
    expect(copied, endsWith('auth/register'));
    expect(
      find.text('Lien d’inscription copié — partage-le sur WhatsApp.'),
      findsOneWidget,
    );
  });

  testWidgets('l’onglet Saison montre la saison ouverte', (tester) async {
    repository.seasons = const [
      AdminSeasonItem(id: 's-1', name: '2025-2026', status: 'archived'),
      AdminSeasonItem(id: 's-2', name: '2026-2027', status: 'open'),
    ];

    await pumpAdmin(tester);
    await tester.tap(find.text('Saison'));
    await tester.pumpAndSettle();

    expect(find.text('Saison 2026-2027'), findsOneWidget);
    expect(find.text('Finir la saison'), findsOneWidget);
    expect(find.text('Créer une saison'), findsNothing);
  });

  testWidgets('sans saison ouverte, l’onglet Saison propose d’en créer une',
      (tester) async {
    repository.seasons = const [
      AdminSeasonItem(id: 's-1', name: '2025-2026', status: 'archived'),
    ];

    await pumpAdmin(tester);
    await tester.tap(find.text('Saison'));
    await tester.pumpAndSettle();

    expect(find.text('Créer une saison'), findsOneWidget);
    expect(find.text('Finir la saison'), findsNothing);
  });
}

AdminProfileItem _profile(
  String id,
  String firstName, {
  required String status,
  String role = 'pronostiqueur',
}) =>
    AdminProfileItem(
      id: id,
      firstName: firstName,
      lastName: 'Test',
      surnom: '',
      username: firstName.toLowerCase(),
      passwordSet: true,
      role: role,
      status: status,
    );

class _FakeAdminRepository implements AdminRepository {
  List<AdminProfileItem> profiles = const [];
  List<AdminSeasonItem> seasons = const [];
  bool failDashboard = false;
  bool failStatusChange = false;
  int dashboardLoads = 0;
  final statusChanges = <(String, String)>[];
  final deletedAccounts = <String>[];

  @override
  Future<AdminDashboardData> fetchDashboard() async {
    dashboardLoads += 1;
    if (failDashboard) throw StateError('réseau indisponible');
    final open = seasons.where((season) => season.status == 'open');
    return AdminDashboardData(
      profiles: profiles,
      seasons: seasons,
      openSeasonId: open.isEmpty ? null : open.first.id,
    );
  }

  @override
  Future<List<AdminHistoricalPlayer>> fetchHistoricalPlayers() async =>
      const [];

  @override
  Future<void> updateProfileStatus(String profileId, String status) async {
    statusChanges.add((profileId, status));
    if (failStatusChange) throw StateError('refus du serveur');
  }

  @override
  Future<void> deleteAccount(String userId) async {
    deletedAccounts.add(userId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInAdminController extends AuthController {
  _SignedInAdminController(super.repository) {
    state = const AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: AuthProfile(
        id: 'admin-1',
        firstName: 'Samih',
        lastName: 'Test',
        role: AuthRole.admin,
        isGoalkeeper: false,
        isActive: true,
        mustChangePassword: false,
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _events = StreamController<supabase.AuthState>.broadcast();

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  @override
  bool get hasSession => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
