import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.child,
    required this.location,
    super.key,
  });

  final Widget child;
  final String location;

  static const _destinations = <_ModuleDestination>[
    _ModuleDestination(
      route: '/home',
      label: 'Accueil',
      icon: Icons.home_rounded,
    ),
    _ModuleDestination(
      route: '/matches',
      label: 'Matchs',
      icon: Icons.sports_soccer_rounded,
    ),
    _ModuleDestination(
      route: '/predictions',
      label: 'Pronos',
      icon: Icons.bolt_rounded,
    ),
    _ModuleDestination(
      route: '/statistics',
      label: 'Stats',
      icon: Icons.insights_rounded,
    ),
    _ModuleDestination(
      route: '/profile',
      label: 'Profil',
      icon: Icons.person_rounded,
    ),
  ];

  int get _selectedIndex {
    final index = _destinations.indexWhere(
      (destination) => location == destination.route ||
          location.startsWith('${destination.route}/'),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            final destination = _destinations[index];
            if (location != destination.route) {
              context.go(destination.route);
            }
          },
          destinations: _destinations
              .map(
                (destination) => NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.icon),
                  label: destination.label,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ModuleDestination {
  const _ModuleDestination({
    required this.route,
    required this.label,
    required this.icon,
  });

  final String route;
  final String label;
  final IconData icon;
}
