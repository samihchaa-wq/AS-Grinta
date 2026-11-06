import 'package:as_grinta/app/shell/player_preview_banner.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_squad_plan_page.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_board_card.dart';
import 'package:as_grinta/features/auth/data/auth_repository.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/domain/badge_admin_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// « Voir l'app comme un joueur » : un admin regarde les écrans des joueurs
/// sans ses outils, et revient à sa vue d'un geste.
void main() {
  AuthProfile profile(String id, AuthRole role) => AuthProfile(
        id: id,
        firstName: id,
        lastName: '',
        role: role,
        isGoalkeeper: false,
        isActive: true,
        mustChangePassword: false,
      );

  (ProviderContainer, _FixedAuthController) containerFor(AuthProfile initial) {
    final controller = _FixedAuthController(initial);
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => controller)],
    );
    addTearDown(container.dispose);
    return (container, controller);
  }

  test('un admin en aperçu n’a plus la vue admin', () {
    final (container, _) = containerFor(profile('admin', AuthRole.admin));

    expect(container.read(isAdminViewProvider), isTrue);
    expect(container.read(isPlayerPreviewActiveProvider), isFalse);

    container.read(playerPreviewProvider.notifier).state = true;

    expect(container.read(isAdminViewProvider), isFalse);
    expect(container.read(isPlayerPreviewActiveProvider), isTrue);
    // Il reste un admin pour le serveur et pour l'interrupteur.
    expect(container.read(isRealAdminProvider), isTrue);
  });

  test('un joueur n’est jamais en aperçu', () {
    final (container, _) =
        containerFor(profile('player', AuthRole.pronostiqueur));

    container.read(playerPreviewProvider.notifier).state = true;

    expect(container.read(isAdminViewProvider), isFalse);
    expect(container.read(isPlayerPreviewActiveProvider), isFalse);
  });

  test('changer de compte ramène toujours à la vue admin', () {
    final (container, controller) =
        containerFor(profile('admin-1', AuthRole.admin));
    container.read(playerPreviewProvider.notifier).state = true;
    expect(container.read(isAdminViewProvider), isFalse);

    controller.switchTo(profile('admin-2', AuthRole.admin));

    expect(container.read(playerPreviewProvider), isFalse);
    expect(container.read(isAdminViewProvider), isTrue);
  });

  test('la gestion des badges disparaît aussi en aperçu', () {
    final (container, _) =
        containerFor(profile(badgeAdminProfileIds.first, AuthRole.admin));
    expect(container.read(canManageBadgesProvider), isTrue);

    container.read(playerPreviewProvider.notifier).state = true;

    expect(container.read(canManageBadgesProvider), isFalse);
  });

  testWidgets('le bandeau ramène à la vue admin', (tester) async {
    final (container, _) = containerFor(profile('admin', AuthRole.admin));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerPreviewBanner())),
      ),
    );

    final banner = find.byKey(const ValueKey('player-preview-banner'));
    expect(banner, findsNothing);

    container.read(playerPreviewProvider.notifier).state = true;
    await tester.pump();
    expect(banner, findsOneWidget);

    await tester.tap(find.text('Revenir en admin'));
    await tester.pump();

    expect(banner, findsNothing);
    expect(container.read(isAdminViewProvider), isTrue);
  });

  for (final preview in [false, true]) {
    testWidgets(
        'fiche du match, onglet Effectif : '
        '${preview ? 'page joueur en aperçu' : 'page admin sinon'}',
        (tester) async {
      final kickoffAt = DateTime.now().add(const Duration(days: 2));
      final router = GoRouter(
        initialLocation: '/matches/match-1/lineup?section=effectif',
        routes: [
          GoRoute(
            path: '/matches/:id/lineup',
            builder: (context, state) =>
                const MatchLineupPage(matchId: 'match-1'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sportsManagementEnabledProvider.overrideWithValue(true),
            isRealAdminProvider.overrideWithValue(true),
            playerPreviewProvider.overrideWith((ref) => preview),
            matchInfoProvider('match-1').overrideWith(
              (ref) async => MatchInfo(
                kickoffAt: kickoffAt,
                address: null,
                lastEncounters: const [],
                matchType: 'amical',
              ),
            ),
            upcomingMatchFixtureProvider('match-1').overrideWith(
              (ref) async => null,
            ),
            matchAvailabilityBoardProvider('match-1').overrideWith(
              (ref) async => MatchAvailabilityBoard.fromRpc({
                'match_id': 'match-1',
                'kickoff_at': kickoffAt.toUtc().toIso8601String(),
                'availability_opens_at': kickoffAt
                    .subtract(const Duration(days: 6))
                    .toUtc()
                    .toIso8601String(),
                'composition_published': false,
                'players': const [],
              }),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(AdminSquadPlanPage),
        preview ? findsNothing : findsOneWidget,
      );
      expect(
        find.byType(MatchAvailabilityBoardCard),
        preview ? findsOneWidget : findsNothing,
      );
    });
  }
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AuthProfile profile)
      : this._(_FixedAuthRepository(profile));

  _FixedAuthController._(this._repository) : super(_repository) {
    switchTo(_repository.profile);
  }

  final _FixedAuthRepository _repository;

  /// Change de compte comme après une déconnexion puis une reconnexion.
  void switchTo(AuthProfile profile) {
    _repository.profile = profile;
    state = AuthState(
      isLoading: false,
      isAuthenticated: true,
      hasSession: true,
      profile: profile,
    );
  }
}

/// Dépôt qui renvoie toujours le profil fixé par le test.
class _FixedAuthRepository implements AuthRepository {
  _FixedAuthRepository(this.profile);

  AuthProfile profile;

  @override
  Stream<supabase.AuthState> get authStateChanges => const Stream.empty();

  @override
  bool get hasSession => true;

  @override
  Future<AuthProfile?> fetchProfile({bool retryAfterSignIn = false}) async =>
      profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
