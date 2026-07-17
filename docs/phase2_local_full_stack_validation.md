# Phase 2 — validation Supabase locale full-stack

Rapport final validé par le run local full-stack #74 (`29617577787`) sur le commit `4b957456d6ed0a752f0adaa1fb806ecf08ea7010`.

La PR est techniquement prête pour une revue humaine, mais reste en brouillon. Aucun projet Supabase distant n'a été lié ou modifié, aucun secret ou donnée de production n'a été utilisé, et aucun déploiement ou fusion n'a été effectué.

## Dépendances historiques reconstituées uniquement dans le runner

1. Baseline antérieur au suivi complet des migrations : colonnes, contraintes, tables, triggers et helpers supposés déjà présents.
2. Conversion historique de `matches.status` de l'enum vers le texte avant les politiques RLS.
3. Anciennes tables et fonctions du flux post-match.
4. Tables du coach supprimées puis réutilisées plus tard.
5. Vues analytiques et statistiques attendues avant les migrations de classement.
6. 156 matchs fictifs construits uniquement à partir des dates de la migration versionnée de restauration.
7. Transition de signature de `claim_player_profile(uuid)` de `uuid` vers `boolean`.
8. Reconstruction des vues supprimées en cascade avec l'ancienne table `goals`, dont le contrat `penalty_faults`.
9. Transition vers l'effectif nommé lorsque `season_players.is_active` existait déjà.
10. Colonne historique `matches.location`, utilisée par les anciens calculs de cotes mais absente de la création versionnée.
11. RPC historiques `open_or_create_season`, `set_season_status` et `set_season_predictions_lock`.
12. Fonctions V3 du moteur de cotes attendues par une migration de durcissement, reliées localement au moteur V4.
13. Noms des saisons fictives conformes au format ultérieur `AAAA-AAAA`.
14. Ancien trigger de statut de profil référençant `season_predictions.player_profile_id`, désactivé uniquement pendant le seed puis réactivé.
15. Insertion idempotente dans `auth.users` sans supposer une contrainte compatible avec `ON CONFLICT(email)`.
16. Alimentation de l'ancienne colonne obligatoire `season_players.player_id` parallèlement au lien moderne facultatif `profile_id`.

Aucun shim n'est ajouté à `supabase/migrations`. Ils sont copiés dans le checkout temporaire puis supprimés. Aucune ancienne migration de production n'est modifiée.

## Preuves finales

- 120 profils fictifs, 8 400 associations profil/badge, 360 titres de saison et 120 badges arborés.
- Deux lignes statistiques et deux lignes de classement, avec condensats inchangés avant/après, après rollback et après réapplication.
- `anon` refusé ; `authenticated`, administrateur et `service_role` autorisés selon le contrat.
- Les quatre RPC ciblées restent `SECURITY DEFINER` et `v_statistics_players` utilise `security_invoker=true`.
- Les trois nouveaux index sont sélectionnés dans les plans `EXPLAIN`.
- Les trois rollbacks et la réapplication sont réussis.
- Flutter Analyze, les 53 tests et le build Web release sont réussis.
- Le workspace, les identifiants locaux et les conteneurs temporaires sont supprimés.
- L'artefact final est aseptisé et contrôlé sans identifiant sensible.

Artefact Supabase : `supabase-local-validation-29617577787`, digest `sha256:05d0bf2233cdc3b3e5691c8f93aad4fdabc959861bf367080eeead545db61046`.

Artefact Flutter : `supabase-local-flutter-29617577787`, digest `sha256:28431840177dedc5cfd57eec620c21dc66555238e10a04d3e563f43698b67b20`.
