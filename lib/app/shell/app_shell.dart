import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
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

  static const _staffDestinations = <_ModuleDestination>[
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
      route: '/coach',
      label: 'Tableau',
      icon: Icons.dashboard_customize_rounded,
    ),
    _ModuleDestination(
      route: '/statistics',
      label: 'Stats',
      icon: Icons.insights_rounded,
    ),
    _ModuleDestination(
      route: '/more',
      label: 'Plus',
      icon: Icons.more_horiz_rounded,
    ),
  ];

  static const _defaultDestinations = <_ModuleDestination>[
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
      route: '/coach',
      label: 'Tableau',
      icon: Icons.visibility_outlined,
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
      route: '/more',
      label: 'Plus',
      icon: Icons.more_horiz_rounded,
    ),
  ];

  List<_ModuleDestination> _destinations(AuthRole? role) {
    if (role?.isStaff == true) return _staffDestinations;
    return _defaultDestinations;
  }

  int _selectedIndex(List<_ModuleDestination> destinations) {
    const moreRoutes = {
      '/more',
      '/profile',
      '/notifications',
      '/settings',
      '/admin',
      '/players',
    };
    final normalizedLocation = moreRoutes.any(
      (route) => location == route || location.startsWith('$route/'),
    )
        ? '/more'
        : location;

    final index = destinations.indexWhere(
      (destination) => normalizedLocation == destination.route ||
          normalizedLocation.startsWith('${destination.route}/'),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(
      authControllerProvider.select((state) => state.profile?.role),
    );
    final destinations = _destinations(role);
    final selectedIndex = _selectedIndex(destinations);

    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            final destination = destinations[index];
            if (location != destination.route) {
              context.go(destination.route);
            }
          },
          destinations: destinations
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
