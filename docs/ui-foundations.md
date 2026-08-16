# Fondations UI — AS Grinta

Ce document résume les composants à privilégier pour conserver une interface cohérente après la refonte visuelle.

## Structure des pages

- `GrintaAdaptiveForm` organise les champs sur une ou deux colonnes selon la largeur.
- `GrintaAuthSurface` fournit la structure commune des écrans d’authentification.

Éviter les largeurs fixes directement dans les pages lorsqu’un composant partagé actuel couvre le besoin.

## États et retours utilisateur

- `GrintaStatusBanner` pour les informations, confirmations, avertissements et erreurs persistantes.
- `GrintaEmptyState` pour les listes ou sections sans contenu.
- `GrintaProgressIndicator` pour les chargements intégrés aux écrans et aux boutons.

Les erreurs importantes doivent être annoncées comme régions dynamiques et ne doivent pas dépendre uniquement d’une couleur.

## Navigation et accessibilité

- `GrintaAppBar` pour les en-têtes de page.
- `GrintaAccessibilityScope` centralise l’ordre de focus et les périphériques de défilement supportés.
- Les zones interactives doivent conserver une cible tactile Material confortable.
- Toute icône sans texte visible doit avoir une info-bulle ou un libellé sémantique.
- Les animations doivent respecter la préférence de réduction des mouvements.

## Thème

Utiliser les constantes de `AppTheme` pour les couleurs, espacements, rayons et surfaces. Les couleurs ou rayons codés en dur sont réservés aux cas réellement spécifiques et doivent rester exceptionnels.

## Typographie

Deux familles embarquées, déclarées dans `pubspec.yaml` et documentées dans `assets/fonts/README.md` :

- `AppTheme.display` (Barlow Condensed) porte `displaySmall`, `headlineMedium`, `headlineSmall`, `titleLarge`, `titleMedium`, le titre des barres d'application et les noms d'équipe des cartes de match ;
- `AppTheme.body` (Inter) est la famille par défaut du thème et porte `titleSmall`, les textes, les étiquettes, les boutons, les onglets et les puces.

Quatre niveaux suffisent : chiffre héros, titre, texte courant, étiquette. La hiérarchie vient de l'écart entre ces niveaux, pas de la graisse.

Aucune graisse 800 n'est embarquée, volontairement. Un `FontWeight.w800` ou `w900` posé dans un widget retombe sur la graisse 700. Préférer `w600` ou `w700` explicitement dans le code nouveau.

Les fichiers de police conservent la fonctionnalité `tnum` (chiffres à chasse fixe), utile pour aligner les colonnes de statistiques et les scores.

## Lisibilité sur le fond

Le texte clair n'est plus entouré d'un liseré noir. La lisibilité par-dessus l'illustration de fond est assurée par le voile de `GrintaAppBackground` (`veilOpacity`).

Un texte posé sur une image locale — photo de joueur, vignette — doit donc porter son propre voile ou son propre aplat, et non un contour de glyphes.

## Validation avant fusion

Pour toute évolution visuelle :

1. vérifier un petit écran mobile ;
2. vérifier le mode paysage ;
3. vérifier une largeur tablette ou web ;
4. vérifier le texte agrandi ;
5. vérifier le clavier et le focus ;
6. exécuter le formatage, l’analyse, les tests et le build web.
