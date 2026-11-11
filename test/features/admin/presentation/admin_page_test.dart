import 'dart:async';

import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/players/data/roster_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Écrans Effectif et Réglages, avec un faux dépôt : les comptes rangés par statut,
/// les actions sur un compte et leur confirmation, la saison ouverte.
void main() {
  late _FakeAdminRepository repository;
  late _FakeRosterRepository roster;

  setUp(() {
    repository = _FakeAdminRepository();
    roster = _FakeRosterRepository();
  });

  Future<void> pumpAdmin(
    WidgetTester tester, {
    Widget home = const AdminPage(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _SignedInAdminController(_FakeAuthRepository()),
          ),
          adminRepositoryProvider.overrideWithValue(repository),
          rosterRepositoryProvider.overrideWithValue(roster),
        ],
        child: MaterialApp(home: home),
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

    expect(find.textContaining('Toi'), findsNothing);
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

  testWidgets('une ligne repliée ne montre que le nom et se déplie au toucher',
      (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];
    roster.seasonId = 's-1';

    await pumpAdmin(tester);

    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Fermer'), findsNothing);
    expect(find.textContaining('karim'), findsNothing);
    expect(find.textContaining('Utilisateur'), findsNothing);
    expect(find.textContaining('Hors effectif'), findsNothing);
    expect(find.text('Rôle :'), findsNothing);

    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier'), findsNWidgets(2));
    expect(find.text('Fermer'), findsNothing);
    expect(find.text('Identifiant : karim'), findsOneWidget);
    expect(find.text('Rôle :'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Oui'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Non'), findsOneWidget);

    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Identifiant : karim'), findsNothing);
  });

  testWidgets('un compte hors effectif peut y être ajouté', (tester) async {
    repository.profiles = [_profile('p-1', 'Roman', status: 'active')];
    roster.seasonId = 's-1';

    await pumpAdmin(tester);
    expect(find.textContaining('Hors effectif'), findsNothing);

    await tester.tap(find.text('Roman'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Oui'));
    await tester.pumpAndSettle();

    expect(roster.added, [('s-1', 'p-1', 'Roman', null)]);
    expect(find.text('Roman est ajouté à l’effectif.'), findsOneWidget);
    expect(find.textContaining('Hors effectif'), findsNothing);
  });

  testWidgets('retirer de l’effectif demande confirmation et garde la fiche',
      (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];
    roster.seasonId = 's-1';
    roster.players = [_rosterPlayer('sp-1', 'Karim', profileId: 'p-1')];

    await pumpAdmin(tester);
    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Non'));
    await tester.pumpAndSettle();
    expect(find.text('Retirer de l’effectif ?'), findsOneWidget);
    await confirmDialog(tester);

    expect(roster.activeChanges, [('sp-1', false)]);
    expect(find.textContaining('Hors effectif'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Non'))
          .selected,
      isTrue,
    );
  });

  testWidgets('une fiche retirée est réactivée plutôt que recréée',
      (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];
    roster.seasonId = 's-1';
    roster.players = [
      _rosterPlayer('sp-1', 'Karim', profileId: 'p-1', active: false),
    ];

    await pumpAdmin(tester);
    await tester.tap(find.text('Karim'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Oui'));
    await tester.pumpAndSettle();

    expect(roster.added, [('s-1', 'p-1', 'Karim', 'sp-1')]);
  });

  testWidgets('les fiches sans compte restent visibles', (tester) async {
    repository.profiles = [_profile('p-1', 'Karim', status: 'active')];
    roster.seasonId = 's-1';
    roster.players = [_rosterPlayer('sp-2', 'Yanis')];

    await pumpAdmin(tester);

    expect(find.text('Dans l’effectif, sans compte'), findsOneWidget);
    expect(find.text('Yanis'), findsOneWidget);
  });

  testWidgets('les Réglages montrent la saison ouverte', (tester) async {
    repository.seasons = const [
      AdminSeasonItem(id: 's-1', name: '2025-2026', status: 'archived'),
      AdminSeasonItem(id: 's-2', name: '2026-2027', status: 'open'),
    ];

    await pumpAdmin(tester, home: const AdminSettingsPage());

    expect(find.text('Saison 2026-2027'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Finir la saison'), findsOneWidget);
    expect(find.text('Créer une saison'), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
    expect(find.byIcon(Icons.stadium_outlined), findsNothing);
  });

  testWidgets('finir la saison demande une confirmation explicite',
      (tester) async {
    repository.seasons = const [
      AdminSeasonItem(id: 's-2', name: '2026-2027', status: 'open'),
    ];

    await pumpAdmin(tester, home: const AdminSettingsPage());

    await tester.tap(find.text('Finir la saison'));
    await tester.pumpAndSettle();
    expect(find.text('Finir la saison ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(repository.seasonStatusChanges, isEmpty);

    await tester.tap(find.text('Finir la saison'));
    await tester.pumpAndSettle();
    await confirmDialog(tester);

    expect(repository.seasonStatusChanges, [('s-2', 'archived')]);
    expect(find.text('Créer une saison'), findsOneWidget);
  });

  testWidgets('les Réglages enregistrent les valeurs par défaut',
      (tester) async {
    await pumpAdmin(tester, home: const AdminSettingsPage());

    expect(find.text('Équipes & stades'), findsOneWidget);
    expect(find.text('Matchs'), findsOneWidget);
    expect(find.text('Joueurs convoqués'), findsOneWidget);
    expect(find.text('Terrain à domicile'), findsOneWidget);
    expect(find.text('Valeurs par défaut'), findsNothing);
    final size = find.byKey(const ValueKey('club-default-squad-size'));
    final address = find.byKey(const ValueKey('club-default-home-address'));
    expect(tester.widget<TextField>(size).controller!.text, '14');
    expect(tester.widget<TextField>(address).controller!.text, 'INP - Labège');

    // Une taille hors limites est refusée sans appeler le serveur.
    await tester.enterText(size, '45');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('La taille du groupe doit être entre 1 et 30.'),
      findsOneWidget,
    );
    expect(repository.savedDefaults, isEmpty);

    await tester.enterText(size, '16');
    await tester.enterText(address, '1 rue du Stade');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(repository.savedDefaults, [(16, '1 rue du Stade')]);
    expect(find.text('Valeurs par défaut enregistrées.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('club-default-squad-size')),
          )
          .controller!
          .text,
      '16',
    );
  });

  testWidgets('sans saison ouverte, les Réglages proposent d’en créer une',
      (tester) async {
    repository.seasons = const [
      AdminSeasonItem(id: 's-1', name: '2025-2026', status: 'archived'),
    ];

    await pumpAdmin(tester, home: const AdminSettingsPage());

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

RosterPlayer _rosterPlayer(
  String id,
  String firstName, {
  String? profileId,
  bool active = true,
}) =>
    RosterPlayer(
      id: id,
      firstName: firstName,
      lastName: '',
      isGoalkeeper: false,
      isCoach: false,
      isActive: active,
      linkedProfileId: profileId,
      linkedProfileName: profileId == null ? null : firstName,
      linkedProfileUsername: null,
    );

class _FakeRosterRepository implements RosterRepository {
  String? seasonId;
  List<RosterPlayer> players = const [];
  final added = <(String, String, String, String?)>[];
  final activeChanges = <(String, bool)>[];

  @override
  Future<String?> openSeasonId() async => seasonId;

  @override
  Future<List<RosterPlayer>> fetchRoster(String seasonId) async => players;

  @override
  Future<void> addProfileToRoster({
    required String seasonId,
    required String profileId,
    required String firstName,
    String? existingSeasonPlayerId,
  }) async {
    added.add((seasonId, profileId, firstName, existingSeasonPlayerId));
    players = [
      for (final player in players)
        if (player.id != existingSeasonPlayerId) player,
      _rosterPlayer(
        existingSeasonPlayerId ?? 'sp-new',
        firstName,
        profileId: profileId,
      ),
    ];
  }

  @override
  Future<void> setActive({required String id, required bool active}) async {
    activeChanges.add((id, active));
    players = [
      for (final player in players)
        player.id == id
            ? _rosterPlayer(
                player.id,
                player.firstName,
                profileId: player.linkedProfileId,
                active: active,
              )
            : player,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdminRepository implements AdminRepository {
  List<AdminProfileItem> profiles = const [];
  List<AdminSeasonItem> seasons = const [];
  bool failDashboard = false;
  bool failStatusChange = false;
  int dashboardLoads = 0;
  final statusChanges = <(String, String)>[];
  final seasonStatusChanges = <(String, String)>[];
  final deletedAccounts = <String>[];

  @override
  Future<void> setSeasonStatus(String id, String status) async {
    seasonStatusChanges.add((id, status));
    seasons = [
      for (final season in seasons)
        season.id == id
            ? AdminSeasonItem(id: season.id, name: season.name, status: status)
            : season,
    ];
  }

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

  AdminClubDefaults clubDefaults = const AdminClubDefaults(
    usualSquadSize: 14,
    homeAddress: 'INP - Labège',
  );
  final savedDefaults = <(int, String)>[];

  @override
  Future<AdminClubDefaults> fetchClubDefaults() async => clubDefaults;

  @override
  Future<AdminClubDefaults> saveClubDefaults({
    required int usualSquadSize,
    required String homeAddress,
  }) async {
    savedDefaults.add((usualSquadSize, homeAddress));
    return clubDefaults = AdminClubDefaults(
      usualSquadSize: usualSquadSize,
      homeAddress: homeAddress,
    );
  }

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
