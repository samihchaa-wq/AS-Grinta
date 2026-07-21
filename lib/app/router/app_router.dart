import 'package:as_grinta/app/router/auth_redirect.dart';
import 'package:as_grinta/app/shell/app_shell.dart';
import 'package:as_grinta/features/admin/presentation/admin_access_denied_page.dart';
import 'package:as_grinta/features/admin/presentation/admin_menu_page.dart';
import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_register_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/auth/presentation/forced_password_change_page.dart';
import 'package:as_grinta/features/badges/presentation/armoire_page.dart';
import 'package:as_grinta/features/badges/presentation/badge_admin_page.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/home/presentation/accueil_page.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:as_grinta/features/matches/presentation/upcoming_match_prediction_page.dart';
import 'package:as_grinta/features/more/presentation/more_page.dart';
import 'package:as_grinta/features/notifications/presentation/notifications_page.dart';
import 'package:as_grinta/features/players/presentation/players_registry_page.dart';
import 'package:as_grinta/features/predictions/presentation/leaderboard_page.dart';
import 'package:as_grinta/features/predictions/presentation/pronos_hub_page.dart';
import 'package:as_grinta/features/profile/presentation/profile_page.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_squad_plan_page.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_convocations_page.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_guests_page.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_motm_dashboard_page.dart';
import 'package:as_grinta/features/sports_management/presentation/admin_waitlist_page.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:as_grinta/features/sports_management/presentation/sport_match_finalization_page.dart';
import 'package:as_grinta/features/sports_management/presentation/sport_motm_vote_page.dart';
import 'package:as_grinta/features/statistics/presentation/statistics_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(
    authControllerProvider,
    (_, __) => refreshNotifier.refresh(),
  );
  ref.listen(
    featureFlagsControllerProvider,
    (_, __) => refreshNotifier.refresh(),
  );
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/accueil',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => resolveAuthRedirect(
      authState: ref.read(authControllerProvider),
      uri: state.uri,
      matchedLocation: state.matchedLocation,
      sportsManagementEnabled: ref.read(sportsManagementEnabledProvider),
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/accueil'),
      GoRoute(path: '/home', redirect: (_, __) => '/accueil'),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.toString(), child: child),
        routes: [
          GoRoute(
            path: '/accueil',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: AccueilPage()),
          ),
          GoRoute(path: '/admin', builder: (_, __) => const AdminMenuPage()),
          GoRoute(
            path: '/admin/administration',
            builder: (_, __) => const AdminPage(),
          ),
          GoRoute(
            path: '/admin/matches',
            builder: (_, __) => const MatchesPage(),
          ),
          GoRoute(
            path: '/admin/convocations',
            builder: (_, __) => const AdminConvocationsPage(),
          ),
          GoRoute(
            path: '/admin/composition',
            builder: (_, __) => const AdminSquadPlanPage(),
          ),
          GoRoute(
            path: '/admin/guests',
            builder: (_, __) => const AdminGuestsPage(),
          ),
          GoRoute(
            path: '/admin/motm',
            builder: (_, __) => const AdminMotmDashboardPage(),
          ),
          GoRoute(
            path: '/admin/waitlist',
            builder: (_, __) => const AdminWaitlistPage(),
          ),
          GoRoute(
            path: '/admin/badges',
            builder: (_, __) => const BadgeAdminPage(),
          ),
          GoRoute(path: '/more', builder: (_, __) => const MorePage()),
          GoRoute(
            path: '/players',
            builder: (_, __) => const PlayersRegistryPage(),
          ),
          GoRoute(
            path: '/matches',
            redirect: (_, __) => '/pronos?category=matches',
          ),
          GoRoute(
            path: '/matches/:matchId',
            builder: (context, state) => MatchDetailsPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/lineup',
            builder: (context, state) =>
                MatchLineupPage(matchId: state.pathParameters['matchId'] ?? ''),
          ),
          GoRoute(
            path: '/matches/:matchId/vote',
            builder: (context, state) => SportMotmVotePage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/finalize',
            builder: (context, state) {
              final matchId = state.pathParameters['matchId'] ?? '';
              return ref.read(sportsManagementEnabledProvider)
                  ? SportMatchFinalizationPage(matchId: matchId)
                  : MatchFinalizationPage(matchId: matchId);
            },
          ),
          GoRoute(
            path: '/matches/:matchId/prediction',
            builder: (context, state) => UpcomingMatchPredictionPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/convocations',
            builder: (context, state) => AdminConvocationsPage(
              initialMatchId: state.pathParameters['matchId'],
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/composition',
            builder: (context, state) => AdminSquadPlanPage(
              initialMatchId: state.pathParameters['matchId'],
              initialStep: state.uri.queryParameters['step'],
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/guests',
            builder: (context, state) => AdminGuestsPage(
              initialMatchId: state.pathParameters['matchId'],
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/motm',
            builder: (context, state) => AdminMotmDashboardPage(
              initialMatchId: state.pathParameters['matchId'],
            ),
          ),
          GoRoute(
            path: '/pronos',
            pageBuilder: (context, state) => NoTransitionPage(
              child: PronosHubPage(
                initialCategory: state.uri.queryParameters['category'],
                initialView: state.uri.queryParameters['view'],
              ),
            ),
          ),
          GoRoute(
            path: '/predictions',
            redirect: (_, __) => '/pronos?category=matches',
          ),
          GoRoute(
            path: '/predictions/leaderboard',
            builder: (_, __) => const LeaderboardPage(),
          ),
          GoRoute(
            path: '/statistics',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: StatisticsPage()),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(path: '/armoire', builder: (_, __) => const ArmoirePage()),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/admin-access',
        builder: (_, __) => const AdminAccessDeniedPage(),
      ),
      GoRoute(
        path: '/auth/loading',
        builder: (_, __) => const AuthLoadingPage(),
      ),
      GoRoute(
        path: '/auth/sign-in',
        builder: (_, __) => const AuthSignInPage(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, __) => const AuthRegisterPage(),
      ),
      GoRoute(
        path: '/auth/new-password',
        builder: (_, __) => const ForcedPasswordChangePage(),
      ),
    ],
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
