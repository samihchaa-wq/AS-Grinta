import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Garantit un ordre de focus prévisible et un défilement utilisable au clavier,
/// à la souris et au tactile sur toutes les plateformes.
///
/// La vue suit également le focus : sans cela, la navigation au clavier
/// démarrait sur les fiches de matchs terminés situées plus de 1 600 px
/// au-dessus de la fenêtre, et il fallait dix-sept tabulations devant un écran
/// figé avant qu'un élément visible ne réagisse (échec WCAG 2.4.7).
class GrintaAccessibilityScope extends StatefulWidget {
  const GrintaAccessibilityScope({required this.child, super.key});

  final Widget child;

  @override
  State<GrintaAccessibilityScope> createState() =>
      _GrintaAccessibilityScopeState();
}

class _GrintaAccessibilityScopeState extends State<GrintaAccessibilityScope> {
  FocusNode? _lastFocused;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || identical(node, _lastFocused)) return;
    _lastFocused = node;

    // Un focus pris au doigt est déjà à l'écran : seul le parcours au clavier
    // a besoin de ce rattrapage.
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }

    final focusContext = node.context;
    if (focusContext == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusContext.mounted) return;
      if (Scrollable.maybeOf(focusContext) == null) return;
      Scrollable.ensureVisible(
        focusContext,
        alignment: .5,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: ScrollConfiguration(
        behavior: const _GrintaScrollBehavior(),
        child: Semantics(
          container: true,
          explicitChildNodes: false,
          child: widget.child,
        ),
      ),
    );
  }
}

class _GrintaScrollBehavior extends MaterialScrollBehavior {
  const _GrintaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
