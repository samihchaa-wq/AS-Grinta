# Observabilité et références d’incident

Les erreurs interceptées par l’application reçoivent une référence non sensible de la forme `MPG-AAAAMMJJ-HHMMSS-NNN`.

## Règles

- ne jamais afficher le message technique brut à l’utilisateur ;
- journaliser uniquement l’opération, le type d’erreur, la version et la référence ;
- afficher la même référence dans l’interface afin qu’elle puisse être communiquée au support ;
- proposer une action de reprise lorsqu’elle est sûre ;
- ne jamais inclure d’adresse électronique, de jeton, d’URL Push ou de contenu métier dans la référence.

## Incidents globaux

Les erreurs de framework, de plateforme et de zone sont interceptées dès le démarrage. Les erreurs de rendu utilisent une vue de secours centralisée avec une référence unique.

## Diagnostic

Pour rapprocher un signal utilisateur d’un journal :

1. relever la référence affichée ;
2. rechercher `incident=<référence>` dans les journaux de l’application ;
3. vérifier la version enregistrée ;
4. corréler avec les journaux Supabase sans recopier de donnée personnelle dans GitHub.
