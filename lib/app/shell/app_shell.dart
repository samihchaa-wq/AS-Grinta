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

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  bool _matchFocusScheduled = false;
  bool _wasBackgrounded = false;
  // On mémorise nous-même l'index affiché à la frame précédente : le prop
  // `navigationShell` est le MÊME objet à chaque rebuild (StatefulShellRoute
  // ne le remplace pas), donc comparer `oldWidget.navigationShell.currentIndex`
  // à `widget.navigationShell.currentIndex` ne détecte jamais de transition —
  // les deux lisent l'état actuel du shell.
  int? _previousShellIndex;

  Uri get _uri => Uri.parse(widget.location);
  int get _selectedIndex => widget.navigationShell.currentIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_wasBackgrounded) return;
    _wasBackgrounded = false;
    if (_selectedIndex != 0 || _uri.path != '/matches') return;

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || _selectedIndex != 0 || _uri.path != '/matches') return;
      _scheduleMatchFocus();
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

  /// Bascule d'onglet sans empiler d'entrée d'historique.
  ///
  /// `goBranch` passe par `GoRouter.go()`, qui signale un `navigate` au moteur
  /// et crée donc une entrée à chaque aller-retour entre les onglets : après
  /// une session normale, l'historique atteignait le plafond de 50 entrées et
  /// le bouton Retour ne sortait plus jamais de l'application.
  /// `Router.neglect` conserve la mise à jour de l'URL mais la signale en
  /// remplacement de l'entrée courante.
  void _goBranchWithoutHistory(int index) {
    Router.neglect(
      context,
      () => widget.navigationShell.goBranch(index, initialLocation: true),
    );
  }

  void _openMatches() {
    if (widget.navigationShell.currentIndex != 0 || _uri.path != '/matches') {
      _goBranchWithoutHistory(0);
    }
    _scheduleMatchFocus();
  }

  void _openStats() {
    if (widget.navigationShell.currentIndex != 1 || _uri.path != '/stats') {
      _goBranchWithoutHistory(1);
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
    // Un changement explicite de branche vers Calendrier recentre la liste sur
    // l'élément pertinent. En revanche, un simple pop depuis une fiche match
    // reste dans la branche 0 : il doit conserver exactement la position de
    // défilement (ou le mois) que l'utilisateur consultait.
    final currentShellIndex = widget.navigationShell.currentIndex;
    final switchedToMatchesBranch = _previousShellIndex != null &&
        _previousShellIndex != 0 &&
        currentShellIndex == 0;

    if (switchedToMatchesBranch) {
      _scheduleMatchFocus();
    }
    _previousShellIndex = currentShellIndex;

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
                    onExit: () => setViewAsUser(ref, false),
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
          extended ? NavigationRailLabelType.none : NavigationRailLabelBehavior.all,
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
