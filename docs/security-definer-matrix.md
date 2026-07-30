# Matrice des fonctions `SECURITY DEFINER`

## But

Une fonction `SECURITY DEFINER` s’exécute avec les droits de son propriétaire. Elle est nécessaire pour certaines actions atomiques, mais son accès doit être contrôlé dans la fonction elle-même et par les privilèges PostgreSQL.

État vérifié après la migration `20260727000100_restrict_public_definer_execution` :

- 84 fonctions `SECURITY DEFINER` dans le schéma `public` ;
- 0 fonction exécutable par le rôle anonyme ;
- 37 fonctions exécutable par un utilisateur connecté ;
- les autres fonctions sont réservées au service interne ou utilisées uniquement par des triggers.

## Fonctions administrateur

Ces fonctions vérifient explicitement le rôle administrateur :

- `admin_set_guest_photo`
- `admin_set_match_address`
- `is_admin`

## Fonctions staff

Ces fonctions vérifient explicitement `is_match_staff()` avant toute lecture sensible ou écriture :

- `admin_require_password_change`
- `admin_update_profile_fields`
- `archive_match`
- `close_match_predictions`
- `create_match_with_odds`
- `delete_match`
- `finalize_match_postgame_with_lineup`
- `get_or_create_opponent`
- `is_match_staff`
- `open_or_create_season`
- `preview_match_odds`
- `set_season_predictions_lock`
- `set_season_status`
- `staff_app_integrity_report`
- `staff_award_badge`
- `staff_create_badge`
- `staff_list_historical_players`
- `staff_list_profiles`
- `staff_profile_username`
- `staff_revoke_badge`
- `staff_set_historical_profile`
- `staff_set_season_player_profile`
- `staff_validate_profile`
- `update_match_with_odds`

## Fonctions personnelles

Ces fonctions utilisent l’identité de la session avec `auth.uid()` et ne modifient que les données de l’utilisateur courant :

- `complete_password_change`
- `get_my_profile`
- `register_push_subscription`
- `save_match_prediction`
- `send_test_push`
- `set_badge_featured`
- `update_my_app_preferences`

## Lectures partagées entre joueurs actifs

Ces fonctions ne réalisent pas d’écriture et exposent uniquement des informations prévues dans l’interface de l’équipe :

- `get_last_opponent_encounters` — contrôle `is_active_profile()` ;
- `get_sport_waitlist` — contrôle `is_active_profile()` ; lecture seule de l'ordre de la liste d'attente, sans les effets de bord ni les droits de modification réservés à `admin_get_sport_waitlist` ;
- `match_prediction_participant_count` — contrôle `is_active_profile()` et renvoie uniquement un nombre ;
- `profile_badge_metrics` — renvoie uniquement des compteurs sportifs et de pronostics associés à un profil. Cette exception est explicitement surveillée par les tests.

## Règle pour toute nouvelle fonction

Une nouvelle fonction `SECURITY DEFINER` accessible à `authenticated` doit respecter au moins une des conditions suivantes :

1. vérifier `public.is_match_staff()` ou `private.is_match_staff()` ;
2. vérifier `public.is_admin()` ou `private.is_admin()` ;
3. vérifier `public.is_active_profile()` pour une lecture destinée aux joueurs ;
4. utiliser `auth.uid()` pour limiter l’action aux données personnelles ;
5. être ajoutée comme exception de lecture, après revue explicite et ajout d’un test.

Aucune fonction `SECURITY DEFINER` ne doit être exécutable par `anon`.
