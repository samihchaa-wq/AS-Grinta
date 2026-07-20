# Module sportif — Procédure de mise en production

Statut : **préparation uniquement — aucune action Production autorisée par ce document**  
Date : **20 juillet 2026**

## 1. Principe de sécurité

Le module doit arriver en Production avec le feature flag `sports_management` **désactivé**. Les migrations sont additives et conservent toutes les données lorsque le module est désactivé.

Aucune des opérations ci-dessous ne doit être exécutée sans validation explicite de l’administrateur du projet :

- fusion des pull requests ;
- application des migrations Supabase ;
- déploiement de l’Edge Function `send-push` ;
- déploiement de Flutter Web ;
- activation du feature flag.

## 2. Ordre obligatoire des fusions

Les PR sont empilées et doivent être fusionnées dans cet ordre strict :

1. `#293` — feature flag serveur ;
2. `#294` — feature flag Flutter ;
3. `#295` — disponibilité serveur ;
4. `#296` — disponibilité Flutter ;
5. `#297` — liste d’attente et convocations ;
6. `#298` — notifications de disponibilité ;
7. `#299` — composition serveur ;
8. `#300` — composition Flutter ;
9. `#301` — invités réutilisables ;
10. `#302` — présence finale et statistiques ;
11. `#303` — vote collectif HDM ;
12. `#304` — notifications HDM ;
13. `#305` — finition, intégrité et préparation de mise en production.

Après chaque fusion, la PR suivante doit être rebasée ou retargetée sur `main`, puis ses contrôles doivent rester verts avant la fusion suivante.

## 3. Contrôles avant toute fusion

Pour chaque PR :

- garde-fou des migrations vert ;
- formatage Dart vert ;
- `flutter analyze --fatal-infos` vert ;
- tests Flutter verts ;
- build Web release vert ;
- diagnostic responsive vert ;
- installation complète des migrations sur Supabase local ;
- toutes les suites pgTAP/RLS vertes ;
- `supabase db lint --level error` vert ;
- aucun fichier temporaire de CI dans le diff ;
- un seul commit fonctionnel relatif à la PR précédente.

## 4. Préparation Supabase Production

### 4.1 Sauvegarde et état initial

Avant application :

- confirmer que le projet est `ACTIVE_HEALTHY` ;
- exporter la liste des migrations appliquées ;
- vérifier les extensions `pg_cron`, `pg_net` et `vault` ;
- relever les tâches `cron.job` existantes ;
- relever les Edge Functions et leur version ;
- effectuer une sauvegarde logique ou confirmer la restauration disponible selon le plan Supabase.

### 4.2 Application des migrations

Appliquer uniquement les migrations nouvellement fusionnées, dans l’ordre chronologique. Ne jamais modifier une migration déjà appliquée.

Après application, vérifier :

- toutes les nouvelles tables ont RLS activée ;
- aucune table privée n’est exposée à `anon` ou `authenticated` ;
- les RPC publiques sont `SECURITY INVOKER` ;
- les helpers `SECURITY DEFINER` ont un `search_path` vide et leurs contrôles de rôle ;
- le flag `sports_management` existe et vaut `false` ;
- les tâches cron sont créées une seule fois ;
- aucune notification sportive ne part tant que le flag est désactivé.

### 4.3 Edge Function

Déployer la version fusionnée de `send-push` **après** les migrations et **avant** l’activation du flag.

Vérifier :

- authentification interne `x-push-token` ;
- types historiques toujours pris en charge ;
- nouveaux types disponibilité et HDM pris en charge ;
- préférence utilisateur respectée ;
- abonnements 404/410 nettoyés ;
- aucune donnée privée incluse dans les charges utiles.

## 5. Déploiement Flutter

Déployer Flutter Web avec le flag toujours désactivé.

Contrôler le parcours historique :

- accueil ;
- pronostics ;
- création et modification de match ;
- finalisation historique ;
- statistiques ;
- badges ;
- notifications ;
- administration.

Aucun menu, route ou appel réseau sportif ne doit apparaître lorsque le flag est désactivé.

## 6. Activation progressive

### Étape A — Administrateur uniquement

Activer le flag pendant une fenêtre supervisée, puis contrôler :

- apparition des menus sportifs ;
- création/synchronisation du workflow d’un match de test ;
- disponibilité ;
- liste d’attente ;
- convocation ;
- invité ;
- composition et publication.

Ne pas utiliser un match officiel pour le premier essai.

### Étape B — Match test complet

Exécuter un match de test de bout en bout :

1. création ;
2. disponibilité ;
3. convocations ;
4. composition ;
5. validation finale ;
6. statistiques ;
7. vote HDM ;
8. clôture ;
9. notifications ;
10. contrôle d’intégrité depuis `Admin → Suivi des votes HDM`.

Le contrôle doit afficher :

- Présences : OK ;
- Buts : OK ;
- Clean sheets : OK ;
- Hommes du match : OK ;
- Intégrité globale : OK.

### Étape C — Ouverture à l’effectif

Conserver une surveillance renforcée pendant les premiers matchs :

- erreurs Edge Function ;
- journaux `pg_cron` ;
- doublons de notification ;
- écarts statistiques ;
- retours joueurs sur l’accès aux routes et le vote.

## 7. Retour arrière

Le retour arrière fonctionnel prioritaire consiste à désactiver immédiatement `sports_management`.

Cette action :

- masque les écrans et routes ;
- bloque les RPC sportives côté serveur ;
- empêche les nouveaux envois ;
- conserve toutes les données ;
- rétablit le parcours historique.

Ne pas supprimer les tables ni inverser les migrations en urgence. Une suppression DDL risquerait de casser l’historique des matchs, des invités, des compositions et des votes.

Après désactivation :

1. arrêter uniquement les tâches cron sportives si nécessaire ;
2. conserver les données pour diagnostic ;
3. corriger dans une nouvelle migration additive ;
4. rejouer les tests locaux ;
5. réactiver seulement après validation.

## 8. Requêtes de contrôle post-déploiement

Les contrôles doivent confirmer :

- `sports_management = false` avant activation ;
- une seule tâche cron par nom ;
- aucune RPC anonyme ;
- aucun vote individuel lisible par le client ;
- aucune présence statistique avant validation finale ;
- aucun doublon dans `match_attendance`, `match_player_stats` ou `match_man_of_match` ;
- cohérence des compteurs du tableau de bord administrateur ;
- Production sans branche Supabase payante non autorisée.

## 9. Critère de réussite

La mise en production est considérée comme réussie uniquement lorsque :

- le parcours historique reste intact flag désactivé ;
- le match test complet passe flag activé ;
- toutes les statistiques sont cohérentes ;
- le secret du vote est préservé ;
- les notifications sont idempotentes ;
- le retour au parcours historique est possible par simple désactivation du flag.
