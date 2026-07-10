# AS Grinta

Application mobile pour une équipe de football amateur.

## V1

- Comptes sur invitation
- Rôles : joueur, admin, modérateur, coach
- Saisons et effectif
- Création, modification, finalisation et archivage des matchs
- Saisie des statistiques uniquement après le match
- Buts, passes décisives, fautes provoquant un penalty, clean sheets et hommes du match
- Pronostics de match et de saison

## Navigation

- Accueil
- Matchs
- Pronostics
- Statistiques
- Plus : profil, paramètres et administration

## Flux d’un match

1. Le staff crée le match.
2. Le pronostic est immédiatement ouvert.
3. Le pronostic est automatiquement fermé cinq minutes avant le coup d’envoi.
4. Aucune composition et aucune saisie en direct ne sont utilisées.
5. Après le match, le staff renseigne le score, les présences et les statistiques individuelles.
6. La validation rend les pronostics visibles aux autres utilisateurs et calcule les classements.

## Joueurs invités

Les invités sont ajoutés uniquement dans la feuille de statistiques du match. Ils peuvent avoir des buts, des passes décisives et des fautes provoquant un penalty, mais aucune fiche permanente ni statistique de carrière ou de saison n’est créée.

## Stack

- Flutter
- Supabase Auth
- PostgreSQL
- Supabase Storage

## Qualité

Chaque pull request exécute :

- l’analyse statique Flutter ;
- les tests automatisés ;
- le build Flutter Web en mode release.

Le déploiement GitHub Pages contrôle ensuite l’accessibilité des fichiers essentiels du site.

## Règle produit

Aucune fonctionnalité non validée ne doit être ajoutée.
