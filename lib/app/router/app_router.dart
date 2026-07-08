import 'package:as_grinta/features/home/presentation/home_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_page.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_page.dart';
import 'package:as_grinta/features/statistics/presentation/statistics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(path: '/matches', builder: (_, __) => const MatchesPage()),
      GoRoute(path: '/predictions', builder: (_, __) => const PredictionsPage()),
      GoRoute(path: '/statistics', builder: (_, __) => const StatisticsPage()),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('Profil')),
        ),
      ),
    ],
  );
});
