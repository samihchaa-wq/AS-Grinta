import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    required this.child,
    required this.location,
    super.key,
  });

  final Widget child;
  final String location;

  Uri get _uri => Uri.parse(location);

  bool get _isMoreRoute {
    const moreRoutes = {
      '/more',
      '/profile',
      '/notifications',
      '/faq',
      '/admin',
      '/players',
    };
    return moreRoutes.any(
      (route) => _uri.path == route || _uri.path.startsWith('$route/'),
    );
  }

  int get _selectedIndex {
    if (_isMoreRoute) return 3;
    if (_uri.path.startsWith('/matches/')) return 0;

    return switch (_uri.queryParameters['category']) {
      'scorers' => 1,
      'general' => 2,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          final destination = switch (index) {
            0 => '/pronos?category=matches',
            1 => '/pronos?category=scorers',
            2 => '/pronos?category=general',
            _ => '/more',
          };
          if (location != destination) context.go(destination);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer_rounded),
            label: 'Matchs',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search_rounded),
            label: 'Buteurs',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'Général',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '',
          ),
        ],
      ),
    );
  }
}
