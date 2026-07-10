import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  static const _destinations = <_ModuleDestination>[
    _ModuleDestination(route: '/home', label: 'Accueil', icon: Icons.home_rounded),
    _ModuleDestination(route: '/matches', label: 'Matchs', icon: Icons.sports_soccer_rounded),
    _ModuleDestination(route: '/predictions', label: 'Pronos', icon: Icons.bolt_rounded),
    _ModuleDestination(route: '/statistics', label: 'Stats', icon: Icons.insights_rounded),
    _ModuleDestination(route: '/more', label: 'Plus', icon: Icons.more_horiz_rounded),
  ];

  int _selectedIndex() {
    const moreRoutes = {'/more','/profile','/notifications','/settings','/admin','/players'};
    final normalized = moreRoutes.any((route) => location == route || location.startsWith('$route/'))
        ? '/more'
        : location;
    final index = _destinations.indexWhere(
      (destination) => normalized == destination.route || normalized.startsWith('${destination.route}/'),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _selectedIndex(),
          onDestinationSelected: (index) {
            final route = _destinations[index].route;
            if (location != route) context.go(route);
          },
          destinations: _destinations
              .map((d) => NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.icon), label: d.label))
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ModuleDestination {
  const _ModuleDestination({required this.route, required this.label, required this.icon});
  final String route;
  final String label;
  final IconData icon;
}
