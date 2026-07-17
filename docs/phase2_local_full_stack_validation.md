# Phase 2 — validation Supabase locale full-stack

## Périmètre et isolation

Validation finale exécutée sur la branche `agent/phase-1-supabase-hardening`, dans GitHub Actions, avec Supabase CLI 2.81.3 et une pile Docker jetable nommée `as-grinta-ci-local`.

Aucun projet Supabase distant n'est lié ou contacté. Aucun secret GitHub/Supabase distant et aucune donnée de production ne sont utilisés. Les trois migrations de sécurité sont retirées du replay initial afin d'établir le baseline vulnérable, puis appliquées, testées, annulées et réappliquées explicitement.

Run final validé : `Supabase local full-stack validation` #74, run `29617577787`, commit testé `4b957456d6ed0a752f0adaa1fb806ecf08ea7010`.

## Résultat final

- garde-fou local-only : réussi ;
- reconstruction complète de toutes les migrations du dépôt : réussie ;
- données uniquement fictives : réussie ;
- rôles `anon`, `authenticated`, administrateur et `service_role` : vérifiés ;
- RPC `SECURITY DEFINER` : signatures, attribut et permissions vérifiés ;
- `v_statistics_players` : `security_invoker=true`, lecture authentifiée et données non vides vérifiées ;
- profils, badges, titres de saison, statistiques et classement : condensats inchangés ;
- trois index : créés et sélectionnés par le planificateur ;
- trois rollbacks : réussis ;
- réapplication : réussie ;
- Flutter Analyze : réussi ;
- Flutter Test : 53 tests réussis ;
- Flutter Web release : réussi ;
- suppression du workspace, des fichiers d'identification locale et des conteneurs : vérifiée ;
- artefact : aseptisé puis contrôlé sans secret.

## Jeu de données synthétique et invariance

Snapshots identiques avant migration, après migration, après rollback et après réapplication :

| Ensemble | Lignes | MD5 |
|---|---:|---|
| profils CI | 120 | `a7ce46cc780cf764a12ac022f5659ebe` |
| associations profil/badge | 8 400 | `2143a065da53c4f9d2a16e2a18f73474` |
| titres de saison | 360 | `62d933a0ae28f79fea42c5389da5cf9a` |
| badges arborés | 120 | `ad41526246ef6a29deb7a65b7cd55dcc` |
| statistiques | 2 | `7ab8f923ba536d457a196ce444a0bc32` |
| classement | 2 | `54c14542d97177145ec580ba1cb269ba` |

Les différences de snapshots et la différence entre la réponse statistiques de l'utilisateur normal et celle de l'administrateur sont vides.

## Permissions et sécurité

Les quatre fonctions préparées dans la phase 1 restent `SECURITY DEFINER` :

- `featured_badges()` ;
- `profile_badge_stars(uuid)` ;
- `staff_list_historical_players()` ;
- `staff_set_historical_profile(uuid,bigint)`.

Après application :

- `anon` reçoit `permission denied` sur `featured_badges()` ;
- `authenticated` conserve l'exécution ;
- le compte administrateur local conserve l'exécution ;
- `service_role` conserve l'exécution ;
- `v_statistics_players` utilise `security_invoker=true`.

## Index

Les plans `EXPLAIN` sélectionnent effectivement :

- `profile_badges_awarded_by_idx` ;
- `profile_badges_badge_id_idx` ;
- `season_awards_profile_id_idx`.

## Compatibilité historique strictement locale

L'environnement hébergé avait été construit en partie avant le suivi complet par migrations. Le replay depuis une base vide a donc nécessité des shims injectés uniquement dans le checkout éphémère du runner :

1. baseline pré-migrations : colonnes, contraintes, tables, triggers et helpers supposés déjà présents par les premières migrations ;
2. conversion historique de `matches.status` de l'enum vers le texte avant la création des politiques RLS ;
3. anciennes tables et fonctions du flux post-match ;
4. tables du coach supprimées puis réutilisées plus tard dans l'historique ;
5. vues analytiques/statistiques attendues avant les migrations de classement ;
6. 156 matchs fictifs construits uniquement à partir des dates présentes dans la migration versionnée de restauration ;
7. transition de signature de `claim_player_profile(uuid)` de `uuid` vers `boolean` ;
8. reconstruction des vues supprimées en cascade avec l'ancienne table `goals`, dont le contrat `penalty_faults` ;
9. transition vers l'effectif nommé lorsque `season_players.is_active` existait déjà ;
10. colonne historique `matches.location`, utilisée par les anciens calculs de cotes mais absente de la création versionnée ;
11. RPC historiques de saison `open_or_create_season`, `set_season_status` et `set_season_predictions_lock` ;
12. fonctions V3 du moteur de cotes attendues par une migration de durcissement, reliées localement au moteur V4 ;
13. noms des saisons fictives conformes au format ultérieur `AAAA-AAAA` ;
14. ancien trigger de statut de profil référençant `season_predictions.player_profile_id`, désactivé uniquement pendant le seed puis réactivé ;
15. insertion idempotente dans `auth.users` sans supposer une contrainte compatible avec `ON CONFLICT(email)` ;
16. alimentation de l'ancienne colonne obligatoire `season_players.player_id` parallèlement au lien moderne facultatif `profile_id`.

Aucun shim n'est ajouté à `supabase/migrations` dans le dépôt. Ils sont copiés dans le checkout temporaire, normalisés pour le replay, puis supprimés. Aucune ancienne migration de production n'est modifiée.

## Artefacts et nettoyage

Artefact final Supabase : `supabase-local-validation-29617577787`, digest GitHub `sha256:05d0bf2233cdc3b3e5691c8f93aad4fdabc959861bf367080eeead545db61046`.

Artefact Flutter : `supabase-local-flutter-29617577787`, digest GitHub `sha256:28431840177dedc5cfd57eec620c21dc66555238e10a04d3e563f43698b67b20`.

Le workflow vérifie l'absence du workspace temporaire, des fichiers d'identification locale et de tout conteneur contenant `as-grinta-ci-local`. Il aseptise ensuite l'artefact et refuse JWT, clés Supabase, mot de passe local, URL PostgreSQL avec identifiants, clés S3 locales et affectations d'environnement sensibles.

## Verdict

La PR est techniquement prête pour une revue humaine de ses migrations, rollbacks et tests locaux. Elle doit rester en brouillon et ne constitue pas une autorisation de fusion ou de déploiement.
