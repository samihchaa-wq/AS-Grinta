# AS Grinta

Application mobile pour une équipe de football amateur.

## V1

- Comptes sur invitation
- Rôles : joueur, admin, modérateur, coach
- Saisons et effectif
- Matchs, live facultatif et archivage
- Buts, passes décisives, gardiens et hommes du match
- Statistiques : matchs joués, buts, passes, HDM, clean sheets
- Pronostics de match et de saison

## Navigation

- Accueil
- Matchs
- Tableau du coach
- Statistiques
- Pronostics
- Profil
- Administration pour le staff

## Joueurs exceptionnels

Les invités d’un seul match sont créés depuis le Tableau du coach. Ils peuvent marquer, faire une passe décisive et participer aux remplacements.

Chaque invité possède un identifiant temporaire unique limité au match. Aucune fiche permanente et aucune statistique de carrière ou de saison ne sont créées.

## Stack

- Flutter
- Supabase Auth
- PostgreSQL
- Supabase Realtime
- Supabase Storage

## Qualité

Chaque pull request exécute :

- l’analyse statique Flutter ;
- les tests automatisés ;
- le build Flutter Web en mode release.

Le déploiement GitHub Pages contrôle ensuite l’accessibilité des fichiers essentiels du site.

## Règle produit

Aucune fonctionnalité non validée ne doit être ajoutée.
