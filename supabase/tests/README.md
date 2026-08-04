# Tests Supabase

La suite métier utilise une pile Supabase locale et éphémère. Elle ne se connecte jamais à la production.

## Schéma de test

L’ancien historique du dépôt n’est pas entièrement rejouable depuis une base vide. Le workflow `Supabase business and RLS tests` installe donc une baseline structurelle contrôlée, puis rejoue explicitement les migrations nécessaires jusqu’aux règles actuelles, notamment Live, temporalité T−15, notifications et résultat HDM.

Les anciennes migrations de production ne sont jamais modifiées pour faciliter les tests. Quand une nouvelle migration courante dépend d’un objet absent de la baseline, la baseline est complétée avec le contrat minimal réellement présent en production ou la migration historique nécessaire est ajoutée à la chaîne de test.

## Exécution

La CI :

1. vérifie le contrat de sécurité des Edge Functions ;
2. exécute les tests de résilience de `send-push` ;
3. démarre une base Supabase locale isolée ;
4. installe le schéma métier courant ;
5. découvre et exécute **tous** les fichiers `supabase/tests/database/*.test.sql` ;
6. exécute `supabase db lint --level error`.

Les tests pgTAP sont transactionnels et annulent leurs fixtures avec `ROLLBACK`.

## Contrats actuels importants

La suite couvre notamment :

- rôles, ACL, RLS, Storage et fonctions `SECURITY DEFINER` ;
- pronostics sans ×2 et fermeture à T−15 ;
- disponibilités et gestion sportive ;
- Effectif, Composition, Live et joueurs ajoutés tardivement ;
- matchs entre nous ;
- météo ;
- finalisation et cycle HDM ancré sur la validation pendant 24 h ;
- ouverture **et résultat** HDM sous le contrat de notifications actuel ;
- signaux Realtime partagés ;
- statistiques, saisons et historique.

Une nouvelle règle Supabase n’est considérée couverte que si la migration qui la définit est effectivement installée dans la base éphémère avant les assertions concernées.
