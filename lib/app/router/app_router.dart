import 'package:as_grinta/app/shell/app_shell.dart';
import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_forgot_password_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_up_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/presentation/home_page.dart';
import 'package:as_grinta/features/live/presentation/live_gameplay_page.dart';
import 'package:as_grinta/features/live/presentation/live_page.dart';
import 'package:as_grinta/features/matches/presentation/match_correction_page.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_page.dart';
import 'package:as_grinta/features/matches/presentation/match_participants_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:as_grinta/features/predictions/presentation/leaderboard_page.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart';
import 'package:as_grinta/features/profile/presentation/profile_page.dart';
import 'package:as_grinta/features/statistics/presentation/statistics_page.dart';
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
        return '/auth/sign-in';
      }
      if (authState.isAuthenticated && isAuthRoute) return '/home';
      if (location == '/') return '/home';

      final role = authState.profile?.role;
      final isLiveOverviewRoute = RegExp(r'^/live/[^/]+$').hasMatch(location);
      final isLiveGameplayRoute = location.endsWith('/gameplay');
      final isFinalizationRoute =
          location.startsWith('/matches/') && location.endsWith('/finalize');
      final isParticipantsRoute = location.startsWith('/matches/') &&
          location.endsWith('/participants');
      final isCorrectionRoute =
          location.startsWith('/matches/') && location.endsWith('/correction');
      final isAdminRoute = location == '/admin';

      if (isLiveOverviewRoute &&
          role != AuthRole.admin &&
          role != AuthRole.moderateur) {
        return '/matches';
      }
      if (isLiveGameplayRoute &&
          role != AuthRole.admin &&
          role != AuthRole.moderateur) {
        return '/matches';
      }
      if (isFinalizationRoute && role != AuthRole.admin) return '/matches';
      if (isParticipantsRoute && role != AuthRole.admin) return '/matches';
      if (isCorrectionRoute && role != AuthRole.moderateur) return '/matches';
      if (isAdminRoute && role != AuthRole.moderateur) return '/home';

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
          GoRoute(path: '/matches', builder: (_, __) => const MatchesPage()),
          GoRoute(
            path: '/matches/:matchId',
            builder: (context, state) => MatchDetailsPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/participants',
            builder: (context, state) => MatchParticipantsPage(
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
            builder: (_, __) => const StatisticsPage(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(
            path: '/live/:matchId',
            builder: (context, state) =>
                LivePage(matchId: state.pathParameters['matchId'] ?? ''),
          ),
          GoRoute(
            path: '/live/:matchId/gameplay',
            builder: (context, state) => LiveGameplayPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/matches/:matchId/finalize',
            builder: (context, state) => MatchFinalizationPage(
              matchId: state.pathParameters['matchId'] ?? '',
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
