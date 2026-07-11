# Ma Petite Grinta (MPG)

L’application de pronostics de l’AS Grinta — un clin d’œil à Mon Petit Prono.

Application mobile et web pour une équipe de football amateur.

## Fonctionnement

- Comptes sur invitation
- Rôles : joueur, administrateur et modérateur
- Saisons et effectif
- Création des matchs avec adversaire, date, heure, lieu et compétition
- Pronostics ouverts dès la création du match et fermés à H-5
- Pronostics privés jusqu’à la validation du résultat
- Saisie des statistiques uniquement après le match
- Score AS Grinta calculé automatiquement depuis les buts saisis
- Présence, buts, passes décisives, fautes provoquant un penalty et clean sheets
- Homme du match facultatif
- Invités temporaires limités à un seul match
- Classements de statistiques et de pronostics calculés automatiquement

## Navigation

- Accueil
- Matchs
- Statistiques
- Pronostics
- Profil
- Administration pour les administrateurs et modérateurs

## Invités d’un match

Les invités sont ajoutés directement dans la feuille de match post-match avec leur nom, leur poste, leur présence, leurs buts, leurs passes décisives et leurs fautes provoquant un penalty.

Ils ne créent aucun compte permanent et ne sont pas intégrés aux statistiques de carrière.

## Éléments volontairement absents

- Aucun tableau du coach
- Aucun chronomètre de match
- Aucune composition en direct
- Aucun événement en temps réel
- Aucun statut de match « en cours »
- Aucun carton jaune ou rouge

## Stack

- Flutter
- Supabase Auth
- PostgreSQL
- Supabase Storage
- GitHub Pages

## Qualité

Chaque modification exécute :

- l’analyse statique Flutter ;
- les tests automatisés ;
- le build Flutter Web en mode release.

Le déploiement GitHub Pages vérifie ensuite les fichiers publics essentiels et la disponibilité de l’API Supabase.
