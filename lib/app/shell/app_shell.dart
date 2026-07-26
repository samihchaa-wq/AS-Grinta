import 'dart:convert';

import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    required this.navigationShell,
    required this.location,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final String location;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _matchesBackground = AssetImage(
    'assets/images/module_backgrounds/matches_blue.webp',
  );

  static const _statsBackgroundParts = <String>[
    'assets/images/module_backgrounds/stats_black.webp.b64.00',
    'assets/images/module_backgrounds/stats_black.webp.b64.01',
    'assets/images/module_backgrounds/stats_black.webp.b64.02',
    'assets/images/module_backgrounds/stats_black.webp.b64.03',
    'assets/images/module_backgrounds/stats_black.webp.b64.04',
    'assets/images/module_backgrounds/stats_black.webp.b64.05',
  ];

  bool _matchFocusScheduled = false;
  bool _matchesPrecacheScheduled = false;
  MemoryImage? _statsBackground;

  Uri get _uri => Uri.parse(widget.location);

  int get _selectedIndex => widget.navigationShell.currentIndex;

  ImageProvider<Object>? get _moduleBackground {
    final path = _uri.path;
    if (path == '/matches' || path.startsWith('/matches/')) {
      return _matchesBackground;
    }
    if (path == '/stats' || path.startsWith('/stats/')) {
      return _statsBackground;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadStatsBackground();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_matchesPrecacheScheduled) return;
    _matchesPrecacheScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) precacheImage(_matchesBackground, context);
    });
  }

  Future<void> _loadStatsBackground() async {
    final encoded = StringBuffer();
    for (final assetPath in _statsBackgroundParts) {
      encoded.write(await rootBundle.loadString(assetPath));
    }

    final image = MemoryImage(base64Decode(encoded.toString()));
    if (!mounted) return;
    setState(() => _statsBackground = image);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) precacheImage(image, context);
    });
  }

  void _scheduleMatchFocus() {
    if (_matchFocusScheduled) return;
    _matchFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _matchFocusScheduled = false;
      if (!mounted) return;
      final notifier = ref.read(matchesFocusRequestProvider.notifier);
      notifier.state++;
    });
  }

  void _openMatches() {
    if (widget.navigationShell.currentIndex != 0 || _uri.path != '/matches') {
      widget.navigationShell.goBranch(0, initialLocation: true);
    }
    _scheduleMatchFocus();
  }

  void _openStats() {
    if (widget.navigationShell.currentIndex != 1 || _uri.path != '/stats') {
      widget.navigationShell.goBranch(1, initialLocation: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewingAsUser = ref.watch(viewAsUserProvider);
    final background = _moduleBackground;
    final moduleTheme = Theme.of(context).copyWith(
      scaffoldBackgroundColor:
          background == null ? AppTheme.background : Colors.transparent,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          if (viewingAsUser)
            _PreviewBanner(
              onExit: () => ref.read(viewAsUserProvider.notifier).state = false,
            ),
          Expanded(
            child: _ModuleBackground(
              image: background,
              child: Theme(
                data: moduleTheme,
                child: widget.navigationShell,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index == 0) {
            _openMatches();
          } else {
            _openStats();
          }
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
  const _ModuleBackground({required this.image, required this.child});

  final ImageProvider<Object>? image;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        const ColoredBox(color: AppTheme.background),
        if (image != null)
          RepaintBoundary(
            child: Image(
              image: image!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.expand(),
            ),
          ),
        if (image != null) const ColoredBox(color: Color(0x14000000)),
        RepaintBoundary(child: child),
      ],
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
