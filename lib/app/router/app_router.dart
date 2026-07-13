import 'package:as_grinta/app/shell/app_shell.dart';
import 'package:as_grinta/features/admin/presentation/admin_page.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_register_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/auth/presentation/forced_password_change_page.dart';
import 'package:as_grinta/features/matches/presentation/match_details_page.dart';
import 'package:as_grinta/features/matches/presentation/match_finalization_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:as_grinta/features/more/presentation/faq_page.dart';
import 'package:as_grinta/features/more/presentation/more_page.dart';
import 'package:as_grinta/features/notifications/presentation/notifications_page.dart';
import 'package:as_grinta/features/players/presentation/players_registry_page.dart';
import 'package:as_grinta/features/predictions/presentation/leaderboard_page.dart';
import 'package:as_grinta/features/predictions/presentation/pronos_hub_page.dart';
import 'package:as_grinta/features/profile/presentation/profile_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/matches',
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (authState.isLoading) return '/auth/loading';

      final isPasswordChangeRoute = location == '/auth/new-password';
      final mustChangePassword =
          authState.profile?.mustChangePassword == true;

      if (authState.isAuthenticated && mustChangePassword) {
        return isPasswordChangeRoute ? null : '/auth/new-password';
      }
      if (isPasswordChangeRoute && !mustChangePassword) return '/matches';

      final isAuthRoute = location.startsWith('/auth');
      if (!authState.isAuthenticated && !isAuthRoute && location != '/') {
        final target = state.uri.toString();
        return '/auth/sign-in?redirect=${Uri.encodeComponent(target)}';
      }
      if (authState.isAuthenticated && isAuthRoute) {
        final redirect = state.uri.queryParameters['redirect'];
        if (redirect != null && redirect.startsWith('/')) return redirect;
        return '/matches';
      }
      if (location == '/' || location == '/home') return '/matches';

      final role = authState.profile?.role;
      final isAdmin = role == AuthRole.admin;
      final isStaff = role?.isStaff == true;
      final isFinalizationRoute =
          location.startsWith('/matches/') && location.endsWith('/finalize');
      final isAdminRoute = location == '/admin';
      final isPlayersRoute = location == '/players';

      if (isFinalizationRoute && !isAdmin) return '/matches';
      if (isAdminRoute && !isStaff) return '/matches';
      if (isPlayersRoute && !isStaff) return '/matches';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/matches'),
      GoRoute(path: '/home', redirect: (_, __) => '/matches'),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
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
            path: '/matches/:matchId/finalize',
            builder: (context, state) => MatchFinalizationPage(
              matchId: state.pathParameters['matchId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/pronos',
            builder: (_, __) => const PronosHubPage(),
          ),
          GoRoute(path: '/predictions', redirect: (_, __) => '/pronos'),
          GoRoute(
            path: '/predictions/leaderboard',
            builder: (_, __) => const LeaderboardPage(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsPage(),
          ),
          GoRoute(path: '/faq', builder: (_, __) => const FaqPage()),
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
