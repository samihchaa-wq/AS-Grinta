# Observabilité et références d’incident

Les erreurs interceptées par l’application reçoivent une référence non sensible de la forme `ASG-AAAAMMJJ-HHMMSS-NNN`.

## Règles

- ne jamais afficher le message technique brut à l’utilisateur ;
- journaliser uniquement l’opération, le type d’erreur, la version et la référence ;
- afficher la même référence dans l’interface afin qu’elle puisse être communiquée au support ;
- proposer une action de reprise lorsqu’elle est sûre ;
- ne jamais inclure d’adresse électronique, de jeton, d’URL Push ou de contenu métier dans la référence.

## Incidents globaux

Les erreurs de framework, de plateforme et de zone sont interceptées dès le démarrage. Les erreurs de rendu utilisent une vue de secours centralisée avec une référence unique.

## Collecte

`dart:developer.log()` n’émet rien dans un build web release : la référence affichée à l’utilisateur ne serait retrouvable nulle part si elle n’était que journalisée localement. `AppLogger` alimente donc aussi un collecteur serveur, branché au démarrage sur la RPC `log_client_incident`.

Les incidents atterrissent dans `private.client_incident_log`, qui ne contient **que** l’opération, le type d’erreur, la version de l’application, la référence et l’identifiant du profil — jamais le message de l’erreur. La table est purgée au-delà de 90 jours (`private.purge_client_incident_log`), et la RPC est limitée à 20 événements par minute et par compte.

## Diagnostic

Pour rapprocher un signal utilisateur d’un journal :

1. relever la référence affichée ;
2. la rechercher côté serveur — `select * from public.admin_recent_client_incidents(500)` depuis un compte d’administration, ou directement `private.client_incident_log` ;
3. vérifier la version enregistrée ;
4. corréler avec les journaux Supabase sans recopier de donnée personnelle dans GitHub.

En développement, le même enregistrement reste visible dans la console sous la forme `incident=<référence>`.
