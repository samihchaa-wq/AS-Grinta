# Matrice de sécurité des RPC Supabase

Audit préparatoire réalisé sur le projet de production le 20 juillet 2026, sans écriture de données.

## Principes

- `anon` ne doit exécuter aucune fonction `SECURITY DEFINER` applicative.
- Les RPC utilisateur restent accessibles à `authenticated`, avec une portée limitée à l’identité courante ou à un agrégat non sensible.
- Les RPC d’administration restent accessibles à `authenticated` parce que Flutter les appelle avec le JWT de l’administrateur. Leur corps doit revérifier `public.is_match_staff()` ou `private.is_admin()`.
- Les aides internes ne doivent pas être directement exécutables par `authenticated`.
- Toute fonction `SECURITY DEFINER` conserve un `search_path` vide et des références qualifiées par schéma.

## RPC utilisateur ou agrégats contrôlés

| RPC | Contrôle attendu | Motif de `SECURITY DEFINER` |
|---|---|---|
| `complete_password_change()` | identité courante | mise à jour contrôlée du profil après Auth |
| `get_my_profile()` | identité courante | lecture du profil malgré les restrictions de colonnes |
| `match_prediction_participant_count(uuid)` | profil actif, résultat agrégé | compter sans révéler les pronostics adverses |
| `profile_badge_metrics(uuid)` | métriques agrégées uniquement | agréger des tables internes, dont `season_awards` |
| `register_push_subscription(text,text,text,text)` | identité courante | écrire une souscription privée sans exposer la table |
| `save_match_prediction(uuid,integer,integer,boolean)` | identité courante, profil actif, premier match ouvert | écriture atomique et contrôle concurrent du ×2 |
| `set_badge_featured(text,boolean)` | `auth.uid()` propriétaire du badge | mise à jour limitée aux badges du compte courant |
| `update_my_app_preferences(boolean,boolean,boolean)` | identité courante | mise à jour limitée aux préférences du compte |

## RPC d’administration conservées

Les 23 fonctions suivantes sont des points d’entrée applicatifs. L’audit de production confirme qu’elles contiennent toutes un contrôle explicite `is_match_staff()` ou `private.is_admin()` :

- `admin_require_password_change(uuid)`
- `admin_update_profile_fields(uuid,text,text,boolean)`
- `archive_match(uuid)`
- `close_match_predictions(uuid)`
- `create_match_with_odds(uuid,uuid,date,time,text,numeric,numeric,numeric)`
- `delete_match(uuid)`
- `finalize_match_postgame_with_lineup(uuid,integer,jsonb,uuid,integer,uuid[],uuid)`
- `get_or_create_opponent(text)`
- `open_or_create_season(text)`
- `preview_match_odds(uuid,text)`
- `set_season_predictions_lock(uuid,boolean)`
- `set_season_status(uuid,text)`
- `staff_app_integrity_report()`
- `staff_award_badge(uuid,text)`
- `staff_create_badge(text,text,text,text,text,text)`
- `staff_list_historical_players()`
- `staff_list_profiles()`
- `staff_profile_username(uuid)`
- `staff_revoke_badge(uuid,text)`
- `staff_set_historical_profile(uuid,bigint)`
- `staff_set_season_player_profile(uuid,uuid)`
- `staff_validate_profile(uuid,uuid)`
- `update_match_with_odds(uuid,uuid,uuid,date,time,text,text,numeric,numeric,numeric)`

L’avertissement Supabase « signed-in users can execute SECURITY DEFINER » reste attendu pour ces RPC, car l’autorisation métier est vérifiée dans leur corps et couverte par pgTAP.

## Aides internes fermées par la passe 2

| Fonction | Remplacement public |
|---|---|
| `finalize_match_postgame(uuid,integer,jsonb,uuid,integer)` | `finalize_match_postgame_with_lineup(...)` |
| `staff_set_match_attendance(uuid,uuid[])` | appelée uniquement par la finalisation atomique |
| `staff_set_match_mvp(uuid,uuid[])` | appelée uniquement par la finalisation atomique |
| `set_match_odds(uuid,numeric,numeric,numeric)` | `create_match_with_odds(...)` et `update_match_with_odds(...)` |

Ces fonctions restent disponibles au `service_role` et au propriétaire SQL pour les appels internes transactionnels, mais plus au rôle `authenticated`.

## Tables internes

- `push_delivery_log`
- `season_awards`

Elles conservent RLS et reçoivent une politique restrictive `false` ciblant `anon` et `authenticated`. Le `service_role` continue de les utiliser en contournant RLS.

## Vérifications avant production

1. Exécuter la migration sur une base locale ou une branche Supabase de test.
2. Exécuter les tests métier/RLS et `security_hardening_pass_2.test.sql`.
3. Vérifier l’administration Flutter : création et modification de match, finalisation, profils, saisons et badges.
4. Relancer le conseiller de sécurité Supabase et comparer la liste des avertissements.
5. Appliquer en production seulement après autorisation explicite.
