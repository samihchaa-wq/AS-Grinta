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

## Validation avant fusion

Pour toute évolution visuelle :

1. vérifier un petit écran mobile ;
2. vérifier le mode paysage ;
3. vérifier une largeur tablette ou web ;
4. vérifier le texte agrandi ;
5. vérifier le clavier et le focus ;
6. exécuter le formatage, l’analyse, les tests et le build web.
