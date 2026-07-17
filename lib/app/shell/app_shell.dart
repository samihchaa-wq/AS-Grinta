import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  Uri get _uri => Uri.parse(location);

  bool get _isMoreRoute {
    const moreRoutes = {
      '/more',
      '/profile',
      '/notifications',
      '/admin',
      '/players',
      '/armoire',
    };
    return moreRoutes.any(
      (route) => _uri.path == route || _uri.path.startsWith('$route/'),
    );
  }

  int get _selectedIndex {
    if (_isMoreRoute) return 5;
    if (_uri.path == '/statistics') return 4;
    if (_uri.path == '/pronos') {
      return switch (_uri.queryParameters['category']) {
        'scorers' => 2,
        'general' => 3,
        _ => 1,
      };
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _selectedIndex,
        // Icônes seules : les libellés restent définis (accessibilité) mais ne
        // sont pas affichés.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (index) {
          final destination = switch (index) {
            0 => '/accueil',
            1 => '/pronos?category=matches',
            2 => '/pronos?category=scorers',
            3 => '/pronos?category=general',
            4 => '/statistics',
            _ => '/more',
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
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search_rounded),
            label: 'Prono joueurs',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'Classements',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats_rounded),
            label: 'Statistiques',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Paramètres',
            tooltip: 'Paramètres',
          ),
        ],
      ),
    );
  }
}
