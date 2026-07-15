# AS Grinta — Référence fonctionnelle V1

Ce document décrit le fonctionnement post-match de la V1 publique.

## Comptes et rôles

- Les comptes sont créés uniquement sur invitation.
- Les rôles disponibles sont `pronostiqueur`, `admin` et `moderateur`.
- Un compte non actif ne peut pas utiliser l’application.
- Un joueur permanent peut être rattaché à un compte grâce à un token temporaire.
- Un invité de match ne possède pas de compte permanent.

## Saisons et effectif

- Une seule saison peut être ouverte à la fois.
- L’effectif d’une saison est défini par `season_players`.
- La feuille de match propose uniquement les joueurs actifs de l’effectif de la saison concernée.

## Matchs

Un match contient :

- la saison ;
- l’adversaire ;
- la date et l’heure ;
- le lieu ;
- la compétition ;
- les cotes victoire, nul et défaite.

Les statuts autorisés sont :

- `a_venir` ;
- `termine` ;
- `archive`.

Il n’existe aucun statut ni aucune fonctionnalité de match en direct.

## Pronostics de match

- Ils sont ouverts dès la création du match.
- Ils sont modifiables jusqu’à cinq minutes avant le coup d’envoi.
- Chaque utilisateur voit uniquement son propre pronostic avant la validation du résultat.
- Après validation, les pronostics remplis deviennent consultables.
- Barème : score exact = cote × 15 ; bon résultat = cote × 10 ; sinon 0.

## Pronostics de saison

- Joueur de champ : nombre de buts sur la saison.
- Gardien : nombre de clean sheets sur la saison.
- Un pronostiqueur doit remplir tout l’effectif pour participer au classement saison.
- Les pronostics deviennent comparables après le verrouillage de la saison.
- Pour chaque joueur, les pronostiqueurs sont classés selon leur écart à la valeur réelle ou projetée.
- Avec `N` pronostiqueurs complets : 1er = `N × 3`, 2e = `(N − 1) × 3`, puis ainsi de suite.
- Un nombre exact double les points obtenus sur le joueur concerné.
- Les ex æquo obtiennent tous les points du meilleur rang commun ; le rang suivant saute les places occupées (`1, 1, 3`).
- L’ordre global des buteurs est évalué sur toutes les paires de joueurs de champ.
- Le bonus d’ordre est nul jusqu’à 50 % de duels correctement classés, puis augmente jusqu’à `N × 30` pour un ordre parfait.
- Le classement général est une addition directe : `points matchs + points saison`.

## Feuille de match post-match

La validation initiale est réservée aux administrateurs.

Pour chaque joueur permanent :

- présence ;
- buts ;
- passes décisives ;
- fautes provoquant un penalty ;
- clean sheet pour les gardiens.

Pour chaque invité temporaire :

- nom ;
- poste ;
- présence ;
- buts ;
- passes décisives ;
- fautes provoquant un penalty.

L’homme du match est facultatif et doit être un joueur permanent présent.
Le score AS Grinta est calculé automatiquement à partir des buts saisis.
Le score adverse est saisi manuellement.

## Corrections

- Les corrections après validation sont réservées au staff autorisé.
- Elles passent exclusivement par les RPC prévues à cet effet.
- Chaque correction est enregistrée dans le journal d’audit.

## Statistiques

Les statistiques de carrière comprennent :

- matchs joués ;
- buts ;
- passes décisives ;
- fautes provoquant un penalty ;
- hommes du match ;
- clean sheets.

Les invités temporaires n’entrent pas dans les statistiques de carrière.
Les statistiques individuelles commencent avec les feuilles de match saisies dans cette version.

## Éléments absents de la V1

- tableau du coach ;
- chronomètre ;
- composition en direct ;
- substitutions en direct ;
- événements Realtime ;
- cartons jaunes ou rouges ;
- minutes jouées, titularisations et entrées en jeu.

## Livraison

Une version est livrable uniquement si :

- `flutter analyze` ne signale aucune erreur ;
- tous les tests passent ;
- le build Web release réussit ;
- GitHub Pages est publié ;
- le smoke test Web et Supabase réussit ;
- les migrations GitHub et Supabase sont alignées.
