import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Garantit un ordre de focus prévisible et un défilement utilisable au clavier,
/// à la souris et au tactile sur toutes les plateformes.
class GrintaAccessibilityScope extends StatelessWidget {
  const GrintaAccessibilityScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: ScrollConfiguration(
        behavior: const _GrintaScrollBehavior(),
        child: Semantics(
          container: true,
          explicitChildNodes: false,
          child: child,
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
