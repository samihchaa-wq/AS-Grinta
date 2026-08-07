import 'dart:ui';

import 'package:as_grinta/app/shell/module_navigation.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
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
  // On mémorise nous-même l'index affiché à la frame précédente : le prop
  // `navigationShell` est le MÊME objet à chaque rebuild (StatefulShellRoute
  // ne le remplace pas), donc comparer `oldWidget.navigationShell.currentIndex`
  // à `widget.navigationShell.currentIndex` ne détecte jamais de transition —
  // les deux lisent l'état actuel du shell.
  int? _previousShellIndex;

  // Une grande partie de l'application (fiche match, administration, profil,
  // notifications…) vit dans la même branche que le Calendrier. Dans ces cas,
  // revenir en arrière vers `/matches` ne change pas `currentIndex` : sans
  // mémoriser aussi le chemin précédent, aucun nouveau focus n'était demandé
  // et la liste pouvait réapparaître tout en haut de l'historique.
  String? _previousLocationPath;

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
    // Toute arrivée sur la racine du Calendrier doit déclencher un re-focus
    // sur l'élément pertinent : changement d'onglet, retour système depuis
    // une fiche/admin/profil, ou goBranch tiers. Le seul index de branche ne
    // suffit pas puisque ces écrans partagent la branche 0 avec `/matches`.
    final currentShellIndex = widget.navigationShell.currentIndex;
    final currentLocationPath = _uri.path;
    final switchedToMatchesBranch = _previousShellIndex != null &&
        _previousShellIndex != 0 &&
        currentShellIndex == 0;
    final returnedToMatchesRoot = _previousLocationPath != null &&
        _previousLocationPath != '/matches' &&
        currentLocationPath == '/matches';

    if (switchedToMatchesBranch || returnedToMatchesRoot) {
      _scheduleMatchFocus();
    }
    _previousShellIndex = currentShellIndex;
    _previousLocationPath = currentLocationPath;

    final viewingAsUser = ref.watch(viewAsUserProvider);
    final moduleTheme = Theme.of(
      context,
    ).copyWith(scaffoldBackgroundColor: Colors.transparent);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 840;
        final extendRail = constraints.maxWidth >= 1180;
        final content = Theme(data: moduleTheme, child: widget.navigationShell);

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
                              color: AppTheme.outline.withValues(alpha: .28),
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
              : ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: NavigationBar(
                      selectedIndex: _selectedIndex,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      onDestinationSelected: _selectDestination,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.calendar_month_outlined),
                          selectedIcon: Icon(Icons.calendar_month_rounded),
                          label: 'Calendrier',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.leaderboard_outlined),
                          selectedIcon: Icon(Icons.leaderboard_rounded),
                          label: 'Statistiques',
                        ),
                      ],
                    ),
                  ),
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
      minWidth: 72,
      minExtendedWidth: 200,
      groupAlignment: -.7,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      onDestinationSelected: onSelected,
      leading: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 22),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: AppTheme.primaryBright.withValues(alpha: .22),
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
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month_rounded),
          label: Text('Calendrier'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.leaderboard_outlined),
          selectedIcon: Icon(Icons.leaderboard_rounded),
          label: Text('Statistiques'),
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
      color: AppTheme.admin,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.microGap,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 17,
                color: Colors.white,
              ),
              const SizedBox(width: AppSpacing.contentGap),
              const Expanded(
                child: Text(
                  'Aperçu utilisateur',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
