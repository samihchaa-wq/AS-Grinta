import 'package:as_grinta/features/players/data/player_card_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Adresse de la fiche joueur dans l'onglet Statistiques.
String playerCardLocation(PlayerCardKey key) {
  return Uri(
    path: '/stats/joueur',
    queryParameters: {
      if (key.profileId != null) 'profil': key.profileId!,
      if (key.fullName.isNotEmpty) 'nom': key.fullName,
      if (key.isGoalkeeper) 'gardien': '1',
    },
  ).toString();
}

/// Relit une [PlayerCardKey] depuis l'adresse ; `null` si elle ne désigne
/// personne.
PlayerCardKey? playerCardKeyFromUri(Uri uri) {
  final params = uri.queryParameters;
  final profileId = params['profil']?.trim();
  final fullName = params['nom']?.trim() ?? '';
  if ((profileId == null || profileId.isEmpty) && fullName.isEmpty) {
    return null;
  }
  return (
    profileId: (profileId == null || profileId.isEmpty) ? null : profileId,
    fullName: fullName,
    isGoalkeeper: params['gardien'] == '1',
  );
}

/// Active l'ouverture de la fiche joueur au toucher d'un nom.
///
/// Les mêmes tableaux sont montés hors du module Statistiques (le classement
/// des pronostics dans le Calendrier, par exemple) : seul le module les rend
/// cliquables, en posant cette portée au-dessus de ses panneaux.
class PlayerCardLinkScope extends InheritedWidget {
  const PlayerCardLinkScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<PlayerCardLinkScope>();
    return scope?.enabled ?? false;
  }

  @override
  bool updateShouldNotify(PlayerCardLinkScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Rend [child] (un nom de joueur) cliquable vers sa fiche, sous une
/// [PlayerCardLinkScope] active. Ailleurs, [child] est rendu tel quel.
class PlayerCardLink extends StatelessWidget {
  const PlayerCardLink({
    super.key,
    required this.playerKey,
    required this.child,
  });

  final PlayerCardKey playerKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlayerCardLinkScope.of(context)) return child;
    return Semantics(
      button: true,
      hint: 'Ouvrir la fiche joueur',
      child: InkWell(
        onTap: () => context.push(playerCardLocation(playerKey)),
        child: child,
      ),
    );
  }
}
