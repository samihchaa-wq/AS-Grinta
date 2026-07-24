import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static final _matchesBackground = ResizeImage.resizeIfNeeded(
    432,
    null,
    const AssetImage('assets/images/module_backgrounds/matches.webp'),
  );
  static final _statsBackground = ResizeImage.resizeIfNeeded(
    432,
    null,
    const AssetImage('assets/images/module_backgrounds/stats.webp'),
  );
  static final _settingsBackground = ResizeImage.resizeIfNeeded(
    432,
    null,
    const AssetImage('assets/images/module_backgrounds/settings.webp'),
  );
  static final _badgesBackground = ResizeImage.resizeIfNeeded(
    432,
    null,
    const AssetImage('assets/images/module_backgrounds/badges.webp'),
  );
  static final _backgrounds = <ImageProvider<Object>>[
    _matchesBackground,
    _statsBackground,
    _settingsBackground,
    _badgesBackground,
  ];

  bool _precacheScheduled = false;
  late ThemeData _transparentTheme;

  Uri get _uri => Uri.parse(widget.location);

  int get _selectedIndex {
    final path = _uri.path;
    if (path == '/stats' || path == '/statistics') return 1;
    if (path == '/pronos') {
      final category = _uri.queryParameters['category'];
      if (category == 'general' || category == 'scorers') return 1;
    }
    return 0;
  }

  ImageProvider<Object>? get _moduleBackground {
    final path = _uri.path;
    if (path == '/matches' || path.startsWith('/matches/')) {
      return _matchesBackground;
    }
    if (path == '/stats' || path == '/statistics') {
      return _statsBackground;
    }
    if (path == '/more' || path == '/profile' || path == '/notifications') {
      return _settingsBackground;
    }
    if (path == '/armoire' || path == '/admin/badges') {
      return _badgesBackground;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transparentTheme = Theme.of(
      context,
    ).copyWith(scaffoldBackgroundColor: Colors.transparent);
    if (_precacheScheduled) return;
    _precacheScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheBackgrounds();
    });
  }

  Future<void> _precacheBackgrounds() async {
    final current = _moduleBackground;
    final ordered = <ImageProvider<Object>>[
      if (current != null) current,
      for (final background in _backgrounds)
        if (background != current) background,
    ];

    for (final background in ordered) {
      if (!mounted) return;
      await precacheImage(background, context);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewingAsUser = ref.watch(viewAsUserProvider);
    final background = _moduleBackground;
    final moduleContent = background == null
        ? widget.child
        : _ModuleBackground(image: background, child: widget.child);

    return Scaffold(
      body: Column(
        children: [
          if (viewingAsUser)
            _PreviewBanner(
              onExit: () => ref.read(viewAsUserProvider.notifier).state = false,
            ),
          Expanded(
            child: Theme(data: _transparentTheme, child: moduleContent),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index == 0) {
            final focusRequest = DateTime.now().microsecondsSinceEpoch;
            context.go('/matches?focusRequest=$focusRequest');
            return;
          }
          if (_uri.path != '/stats') context.go('/stats');
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

  final ImageProvider<Object> image;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppTheme.background),
        RepaintBoundary(
          child: Image(
            image: image,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            excludeFromSemantics: true,
          ),
        ),
        const ColoredBox(color: Color(0x24000000)),
        child,
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
