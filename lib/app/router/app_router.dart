import 'package:as_grinta/features/auth/presentation/auth_forgot_password_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_loading_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_in_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_sign_up_page.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/home/presentation/home_page.dart';
import 'package:as_grinta/features/live/presentation/live_gameplay_page.dart';
import 'package:as_grinta/features/live/presentation/live_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_page.dart';
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
      if (authState.isLoading) {
        return '/auth/loading';
      }
      final isAuthRoute = location.startsWith('/auth');
      if (!authState.isAuthenticated && !isAuthRoute && location != '/') {
        return '/auth/sign-in';
      }
      if (authState.isAuthenticated && isAuthRoute) {
        return '/home';
      }
      if (location == '/') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(path: '/matches', builder: (_, __) => const MatchesPage()),
      GoRoute(
          path: '/predictions', builder: (_, __) => const PredictionsPage()),
      GoRoute(path: '/statistics', builder: (_, __) => const StatisticsPage()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
      GoRoute(
        path: '/live/:matchId',
        builder: (context, state) =>
            LivePage(matchId: state.pathParameters['matchId'] ?? ''),
      ),
      GoRoute(
        path: '/live/:matchId/gameplay',
        builder: (context, state) =>
            LiveGameplayPage(matchId: state.pathParameters['matchId'] ?? ''),
      ),
      GoRoute(
          path: '/auth/loading', builder: (_, __) => const AuthLoadingPage()),
      GoRoute(
          path: '/auth/sign-in', builder: (_, __) => const AuthSignInPage()),
      GoRoute(
          path: '/auth/sign-up', builder: (_, __) => const AuthSignUpPage()),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, __) => const AuthForgotPasswordPage(),
      ),
    ],
  );
});
