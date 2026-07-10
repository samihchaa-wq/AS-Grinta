import 'package:as_grinta/app/shell/app_shell.dart';
import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_forgot_password_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_up_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/presentation/home_page.dart';
import 'package:as_grinta/features/matches/presentation/match_correction_page.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:as_grinta/features/more/presentation/more_page.dart';
import 'package:as_grinta/features/notifications/presentation/notifications_page.dart';
import 'package:as_grinta/features/players/presentation/players_page.dart';
import 'package:as_grinta/features/players/presentation/players_registry_page.dart';
import 'package:as_grinta/features/predictions/presentation/leaderboard_page.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:as_grinta/features/preferences/presentation/settings_page.dart';
import 'package:as_grinta/features/profile/presentation/profile_page.dart';
import 'package:as_grinta/features/statistics/presentation/statistics_page_v2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (authState.isLoading) return '/auth/loading';

      final isAuthRoute = location.startsWith('/auth');
      if (!authState.isAuthenticated && !isAuthRoute && location != '/') {
        final target = state.uri.toString();
        return '/auth/sign-in?redirect=${Uri.encodeComponent(target)}';
      }
      if (authState.isAuthenticated && isAuthRoute) {
        final redirect = state.uri.queryParameters['redirect'];
        if (redirect != null && redirect.startsWith('/')) return redirect;
        return '/home';
      }
      if (location == '/') return '/home';

      final role = authState.profile?.role;
      final isAdmin = role == AuthRole.admin;
      final isStaff = role?.isStaff == true;
      final isFinalizationRoute =
          location.startsWith('/matches/') && location.endsWith('/finalize');
      final isCorrectionRoute =
          location.startsWith('/matches/') && location.endsWith('/correction');
      final isAdminRoute = location == '/admin';
      final isPlayersRoute = location == '/players';

      if (isFinalizationRoute && !isAdmin) return '/matches';
      if (isCorrectionRoute && !isStaff) return '/matches';
      if (isAdminRoute && !isStaff) return '/home';
      if (isPlayersRoute && !isStaff) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
          GoRoute(path: '/more', builder: (_, __) => const MorePage()),
          GoRoute(
            path: '/players',
            builder: (_, __) => const PlayersRegistryPage(),
          ),
          GoRoute(path: '/matches', builder: (_, __) => const MatchesPage()),
          GoRoute(
            path: '/matches/:matchId',
            builder: (context, state) => MatchDetailsPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/correction',
            builder: (context, state) => MatchCorrectionPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/finalize',
            builder: (context, state) => MatchFinalizationPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/predictions',
            builder: (_, __) => const PredictionsPage(),
          ),
          GoRoute(
            path: '/predictions/season',
            builder: (_, __) => const SeasonPredictionsPage(),
          ),
          GoRoute(
            path: '/predictions/leaderboard',
            builder: (_, __) => const LeaderboardPage(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (_, __) => const StatisticsPageV2(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsPage(),
          ),
          GoRoute(
            path: '/claim',
            builder: (context, state) => ClaimPlayerPage(
              token: state.uri.queryParameters['token'],
            ),
          ),
        ],
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
        path: '/auth/sign-up',
        builder: (_, __) => const AuthSignUpPage(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, __) => const AuthForgotPasswordPage(),
      ),
    ],
  );
});
