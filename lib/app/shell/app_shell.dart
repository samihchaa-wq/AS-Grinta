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

  String? get _moduleBackgroundAsset {
    final path = _uri.path;
    if (path == '/matches' || path.startsWith('/matches/')) {
      return 'assets/images/module_backgrounds/matches.webp';
    }
    if (path == '/stats' || path == '/statistics') {
      return 'assets/images/module_backgrounds/stats.webp';
    }
    if (path == '/more' || path == '/profile' || path == '/notifications') {
      return 'assets/images/module_backgrounds/settings.webp';
    }
    if (path == '/armoire' || path == '/admin/badges') {
      return 'assets/images/module_backgrounds/badges.webp';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewingAsUser = ref.watch(viewAsUserProvider);
    final backgroundAsset = _moduleBackgroundAsset;
    final moduleContent = backgroundAsset == null
        ? child
        : _ModuleBackground(assetPath: backgroundAsset, child: child);

    return Scaffold(
      body: Column(
        children: [
          if (viewingAsUser)
            _PreviewBanner(
              onExit: () => ref.read(viewAsUserProvider.notifier).state = false,
            ),
          Expanded(child: moduleContent),
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

class _ModuleBackground extends StatelessWidget {
  const _ModuleBackground({required this.assetPath, required this.child});

  final String assetPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.background,
        image: DecorationImage(
          image: AssetImage(assetPath),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      child: ColoredBox(
        color: const Color(0x24000000),
        child: Theme(
          data: Theme.of(
            context,
          ).copyWith(scaffoldBackgroundColor: Colors.transparent),
          child: child,
        ),
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
