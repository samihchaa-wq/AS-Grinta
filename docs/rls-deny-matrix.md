# Tables internes fermées par RLS

## Principe

Les tables ci-dessous ne sont jamais lues ou modifiées directement par les rôles `anon` et `authenticated`. Leur accès passe par des fonctions serveur contrôlées ou par le rôle interne `service_role`.

RLS était déjà activée et aucun privilège direct n'était accordé aux clients. La politique restrictive `deny_client_access` rend désormais ce refus explicite et testable.

## Schéma `private`

- `app_feature_flag_audit`
- `app_feature_flags`
- `sport_admin_audit_log`

## Schéma `public`

- `historical_match_scores`
- `match_composition_entries`
- `match_compositions`
- `match_sport_finalization_versions`
- `match_sport_finalizations`
- `match_sport_motm_elections`
- `match_sport_motm_results`
- `match_sport_motm_votes`
- `sport_availability_notification_events`

## Invariants automatiques

La suite pgTAP vérifie que :

- RLS reste activée sur les douze tables ;
- chaque table possède une politique restrictive pour `anon` et `authenticated` ;
- aucun rôle client ne possède de privilège direct ;
- `service_role` conserve les droits nécessaires.

Toute table interne ajoutée à cette liste doit être ajoutée simultanément à la migration, au rollback et au test.
