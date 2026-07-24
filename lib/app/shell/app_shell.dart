import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  Uri get _uri => Uri.parse(location);

  int get _selectedIndex {
    final path = _uri.path;
    if (path == '/stats' || path == '/statistics') return 1;
    if (path == '/pronos') {
      final category = _uri.queryParameters['category'];
      if (category == 'general' || category == 'scorers') return 1;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewingAsUser = ref.watch(viewAsUserProvider);
    return Scaffold(
      body: Column(
        children: [
          if (viewingAsUser)
            _PreviewBanner(
              onExit: () => ref.read(viewAsUserProvider.notifier).state = false,
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          final destination = index == 0 ? '/matches' : '/stats';
          if (location != destination) context.go(destination);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer_rounded),
            label: 'Matchs',
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

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Aperçu utilisateur',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: onExit,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Revenir en admin',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
