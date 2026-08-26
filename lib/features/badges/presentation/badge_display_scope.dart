import 'package:flutter/material.dart';

/// Portée d'affichage des badges arborés.
///
/// Les emblèmes n'apparaissent à côté des noms que dans les sous-arbres qui
/// l'activent explicitement (aujourd'hui : le module Statistiques). Partout
/// ailleurs — et dans les tests widget montés sans écran hôte — seul le nom
/// est rendu, sans dépendre du routeur.
class BadgeDisplayScope extends InheritedWidget {
  const BadgeDisplayScope({
    super.key,
    required this.showBadges,
    required super.child,
  });

  final bool showBadges;

  /// `false` quand aucune portée n'est posée au-dessus du contexte.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BadgeDisplayScope>();
    return scope?.showBadges ?? false;
  }

  @override
  bool updateShouldNotify(BadgeDisplayScope oldWidget) =>
      showBadges != oldWidget.showBadges;
}
