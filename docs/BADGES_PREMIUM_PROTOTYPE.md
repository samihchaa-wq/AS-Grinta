# Prototype — 14 fonds premium des badges AS Grinta

Statut : **prototype isolé**, à valider visuellement et techniquement. **Ne pas fusionner / déployer avant recette.**

## Périmètre

- Refonte des 14 traitements de fond : gris, bronze, argent, or ; bleu clair, bleu, bleu foncé, noir ; orange, rubis, grenat ; diamant ; émeraude, violet.
- Effets peints en Flutter, sans boucle d'animation, sans assets réseau et sans nouvelle dépendance.
- Le composant commun `BadgeEmblem` diffuse les nouveaux traitements dans l'armoire, la fiche joueur, les statistiques, l'administration et les écrans de bilan qui l'utilisent.
- Couleurs `badges.color` d'origine conservées en base ; correspondance en lecture seule par `badgePremiumSkinFor`.
- Texte **entièrement dynamique** : valeur, critère, période, nom long, étoiles et progression ne sont pas réécrits.

## Correspondance sans migration

| Ancienne valeur `color` | Prototype | Groupe |
| --- | --- | --- |
| #6E7A86 / #7A858D | Gris acier | Saison |
| #B87333 / #CD7F32 | Bronze | Saison |
| #C4CBD4 / #C0C0C0 | Argent | Saison |
| #E3B23C / #D4AF37 | Or | Saison |
| #4FA9E8 | Bleu clair | Historique |
| #1E3A8A | Bleu | Historique |
| #7C3AED | Bleu foncé | Historique |
| #1C1C24 | Noir obsidienne | Historique |
| #F1706E | Orange | Exploits |
| #E23B36 | Rubis | Exploits |
| #9E1B1B | Grenat | Exploits |
| #5FC9D9 / #B9F2FF | Diamant | Titres |
| #F2811D | Émeraude | Spéciaux |
| #F97316 | Violet | Mystères |

**Attention** : la correspondance par couleur n'est valable que pour le catalogue observé. Avant production, vérifier si des badges ajoutés manuellement portent d'autres couleurs, ou si certaines catégories réutilisent les mêmes codes couleur. Un futur paramètre explicite `skin_id` serait plus robuste ; il nécessiterait une migration revue séparément.

## Limite majeure : photos déjà composites

Certaines images de badges dans `badge-images` sont des JPEG **opaques** avec l'ancien fond directement imprimé. Dans ces cas, le nouveau motif peint **derrière** la photo n'est pas visible : le prototype ajoute tout de même un cadre et un socle premium, sans modifier le visage ni écraser l'illustration. Les images réellement transparentes laissent apparaître la texture intégrale.

**Les maquettes d'images générées précédemment ne sont pas encore intégrées pixel à pixel** : ce prototype redessine leurs effets en Flutter, afin de valider l'architecture et le traitement des textes sans remplacer les photos originales.

Après validation visuelle, il faudra soit :
1. récupérer des originaux détourés fiables, puis placer les illustrations transparentes sur les fonds ;
2. ou reconstruire chaque image composite avec validation humaine, sans altérer les visages.

Ne pas faire de conversion destructive automatique de la production.

## Comportements préservés

- Même hauteur d'emblème (`1.48 × largeur` sans étoile) et de socle, même ordre : illustration → valeur → critère → période.
- Valeur/texte blanc avec contour noir, textes longs adaptés par les composants historiques.
- Étoiles, cadenas, état noir et blanc, badge nouveau et badge arboré.
- Même moteur d'attribution et de déblocage, mêmes données sportives et `profile_badges`.
- Les fonds inconnus (couleurs non reconnues) conservent l'ancien rendu.

## Recette obligatoire avant fusion

- `flutter analyze`
- `flutter test test/features/badges/presentation/badge_emblem_body_test.dart`
- `flutter test test/features/badges/presentation/badge_premium_skins_test.dart`
- `flutter test test/features/badges/`
- Captures des 14 variantes **avec images de joueurs réelles** à 46, 81, 87, 123 px.
- Vérifier iPhone étroit, tablette, PWA, zoom du texte, noms très longs et contraste.
- Vérifier mystères jamais gagnés, connus du club, gagnés, étoilés et arborés.
- Vérifier que le rendu des photos JPEG opaques est jugé acceptable ; sinon ne pas fusionner.

## Garantie de périmètre

Aucun accès ni modification de base de données, aucune migration SQL, aucun téléversement Storage, aucune modification des attributions, aucun déploiement, aucune modification du dépôt commercial Petit Filet.
