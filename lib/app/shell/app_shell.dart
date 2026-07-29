import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
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
  bool _matchFocusScheduled = false;

  Uri get _uri => Uri.parse(widget.location);

  int get _selectedIndex => widget.navigationShell.currentIndex;

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

  void _selectDestination(int index) {
    if (index == 0) {
      _openMatches();
    } else {
      _openStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewingAsUser = ref.watch(viewAsUserProvider);
    final moduleTheme = Theme.of(context).copyWith(
      scaffoldBackgroundColor: Colors.transparent,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 840;
        final extendRail = constraints.maxWidth >= 1180;
        final content = Theme(
          data: moduleTheme,
          child: widget.navigationShell,
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: !useRail,
            child: Column(
              children: [
                if (viewingAsUser)
                  _PreviewBanner(
                    onExit: () =>
                        ref.read(viewAsUserProvider.notifier).state = false,
                  ),
                Expanded(
                  child: useRail
                      ? Row(
                          children: [
                            _DesktopNavigation(
                              selectedIndex: _selectedIndex,
                              extended: extendRail,
                              onSelected: _selectDestination,
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: AppTheme.outline.withValues(alpha: .35),
                            ),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                ),
              ],
            ),
          ),
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: _selectDestination,
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
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      extended: extended,
      minWidth: 76,
      minExtendedWidth: 208,
      groupAlignment: -.7,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      onDestinationSelected: onSelected,
      leading: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 22),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: AppTheme.primaryBright.withValues(alpha: .28),
            ),
          ),
          child: const Icon(
            Icons.sports_soccer_rounded,
            color: AppTheme.primaryBright,
          ),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.sports_soccer_outlined),
          selectedIcon: Icon(Icons.sports_soccer_rounded),
          label: Text('Matchs'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.query_stats_outlined),
          selectedIcon: Icon(Icons.query_stats_rounded),
          label: Text('Stats'),
        ),
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
