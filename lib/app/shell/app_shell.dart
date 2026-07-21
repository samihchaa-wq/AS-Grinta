import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  Uri get _uri => Uri.parse(location);

  /// Seuls les 4 onglets principaux affichent la barre du bas. Les autres écrans
  /// (Paramètres, Armoire, Profil, Admin, détail de match…) sont des pages
  /// poussées, en plein écran avec un bouton retour.
  bool get _isMainTab {
    final p = _uri.path;
    return p == '/accueil' || p == '/pronos' || p == '/statistics';
  }

  int get _selectedIndex {
    if (_uri.path == '/statistics') return 3;
    if (_uri.path == '/pronos') {
      return switch (_uri.queryParameters['category']) {
        'general' || 'scorers' => 2,
        _ => 1,
      };
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isMainTab) return child;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          final destination = switch (index) {
            0 => '/accueil',
            1 => '/pronos?category=matches',
            2 => '/pronos?category=general',
            _ => '/statistics',
          };
          if (location != destination) context.go(destination);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer_rounded),
            label: 'Matchs',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard_rounded),
            label: 'Classements',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
