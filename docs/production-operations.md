# Exploitation de la production

Ce document décrit les contrôles durables à effectuer sur la production AS Grinta. Les valeurs opérationnelles changent : **la base et les journaux Supabase distants doivent toujours être relus avant de conclure sur l’état courant**.

## Source de vérité

Pour diagnostiquer la production, utiliser dans cet ordre :

1. l’état du projet Supabase distant et ses objets réellement déployés ;
2. les journaux API, Postgres, Auth, Realtime et Edge ;
3. les tâches `cron.job` réellement actives ;
4. le commit `main` actuellement déployé côté Flutter ;
5. la documentation pour expliquer le contrat attendu, jamais pour remplacer la vérification distante.

Le script `supabase/diagnostics/production_health.sql` fournit des contrôles SQL reproductibles en lecture seule.

## Topologie attendue

La production utilise actuellement les fonctions Edge suivantes :

- `manage-user` ;
- `register-account` ;
- `send-push` ;
- `claim-account`, endpoint de compatibilité retiré qui répond `410 Gone` ;
- `send-prediction-reminders`, endpoint de compatibilité retiré qui répond `410 Gone`.

Les deux endpoints `410` ne doivent pas être réactivés. Leur suppression physique n’est autorisée qu’après preuve qu’aucun ancien client ou appel externe ne les utilise encore.

Les tâches planifiées métier attendues sont :

- `sports-availability-reminders` ;
- `match-weather-refresh` ;
- `sports-motm-jobs` ;
- `prediction-j5-reminders` ;
- `finish-due-internal-matches`.

Toujours lire `cron.job` avant une intervention : un ancien enregistrement dans `cron.job_run_details` n’est pas la preuve qu’une tâche est encore active.

## Notifications

Le coupe-circuit global des notifications est une **valeur opérationnelle**, pas une constante fonctionnelle. Vérifier le flag distant avant d’analyser une absence de push.

Même lorsque les push sont suspendus, les transitions métier qui ne dépendent pas d’un envoi doivent continuer à fonctionner. Ne jamais déduire l’état d’une disponibilité, d’un prono ou d’un scrutin HDM uniquement à partir des journaux de push.

## Sauvegarde gratuite

Le projet restant sur Supabase Free, la sauvegarde applicative est assurée par `.github/workflows/free_encrypted_backup.yml` :

- exécution hebdomadaire et déclenchement manuel possible ;
- export logique de la base via la CLI Supabase ;
- copie des buckets `app-assets`, `badge-images` et `profile-photos` ;
- chiffrement AES-256 avant tout stockage GitHub ;
- seuls le fichier chiffré et son SHA-256 sont conservés ;
- stockage dans une **draft release GitHub**, qui n’est listée que pour les utilisateurs disposant d’un accès push au dépôt ;
- conservation des huit dernières sauvegardes hebdomadaires ;
- aucun artefact GitHub Actions n’est utilisé pour le backup afin de ne pas consommer son quota de stockage facturable ;
- aucune fonction Push de l’application n’est appelée par cette sauvegarde.

Le secret GitHub `BACKUP_ENCRYPTION_PASSPHRASE` est recommandé pour disposer d’une clé de restauration indépendante des identifiants Supabase. Tant qu’il n’est pas configuré, le workflow utilise une clé dérivée des deux secrets Supabase déjà présents dans la CI ; cette solution de secours protège l’archive mais ne doit pas être considérée comme une clé d’archivage durable en cas de rotation de ces secrets.

La draft release de backup ne doit jamais être publiée. Une sauvegarde n’est considérée comme valide qu’après contrôle d’un run vert et, périodiquement, un test de restauration sur un environnement isolé. Ne jamais tester une restauration destructive sur la production.

### Version de la CLI pour une restauration

Une restauration se fait dans une base Supabase neuve démarrée par la CLI. Le schéma `auth` de cette base vient de la version de la CLI : il doit être **au moins aussi récent que celui de la production**, sinon la restauration des données échoue sur une table de connexion inconnue.

- Utiliser la **CLI Supabase 2.118.0** (ou plus récente), comme `.github/workflows/backup_restore_drill.yml`.
- Ne pas utiliser la CLI 2.111.0 : son schéma `auth` ne contient pas `auth.mfa_recovery_code_sets`, et le test de restauration échouait pour cette raison depuis le 20 septembre 2026.
- Au 27 septembre 2026, la CLI 2.118.0 démarre exactement le même schéma `auth` que la production (82 étapes, dernière version `20260831180000`).
- Avant une restauration réelle, comparer `select max(version), count(*) from auth.schema_migrations` entre la production et la base neuve. Si la production est plus récente, prendre une version plus récente de la CLI.

Le test automatique `Production backup restore drill` restaure chaque dimanche la dernière sauvegarde dans une base jetable. Il peut aussi être lancé à la main depuis l’onglet Actions ; un changement de version de la CLI n’est validé qu’après un run vert.

## Contrôle des migrations

`.github/workflows/migration_inventory.yml` doit échouer si :

- les secrets nécessaires au contrôle distant manquent ;
- une migration existe seulement dans GitHub ou seulement en production ;
- `supabase/production_migrations.lock` ne correspond pas exactement à l’historique distant.

Le contrôle distant s’exécute sur les PR internes qui touchent les migrations ou le lock, sur les modifications correspondantes de `main`, quotidiennement et à la demande. Le lock ne doit être mis à jour qu’après une comparaison distante réussie.

### Contenu des fonctions

La liste des migrations ne dit pas si une fonction a été modifiée directement sur la base. `.github/workflows/function_definition_drift.yml` le vérifie chaque jour (et à la demande), en lecture seule :

1. il reconstruit une base à partir des migrations du dépôt **déjà appliquées en production** ; une migration fusionnée mais pas encore déployée est ignorée et simplement listée ;
2. il relève les fonctions des schémas `public` et `private` de cette base et de la production avec la même requête, `supabase/diagnostics/function_definitions_snapshot.sql` ; côté production, la requête passe par l’API de gestion Supabase en lecture seule ;
3. `tool/compare_function_definitions.py` compare, fonction par fonction, le corps (commentaires, espaces et casse des mots-clés ignorés), `SECURITY DEFINER`, la configuration (`search_path`), les droits d’exécution et l’en-tête (langage, arguments, type de retour, volatilité, propriétaire) ;
4. il échoue à la moindre différence réelle, et le résumé du run liste les fonctions concernées. Le corps d’une fonction de production n’est jamais affiché.

Une différence signifie qu’une modification a été faite en production hors migration, ou qu’une migration n’a pas eu l’effet attendu. La corriger par une nouvelle migration qui recopie l’état voulu, jamais en modifiant une migration existante.

## Contrôles avant un déploiement Supabase

1. confirmer que le projet est sain ;
2. relever la liste distante des migrations et la comparer au verrou vérifié ;
3. ne jamais tenter de « réparer » l’ancien historique de migrations pendant un déploiement fonctionnel ;
4. vérifier les tâches cron et les fonctions Edge actives ;
5. exécuter les tests Supabase/RLS et le lint SQL sur le schéma isolé ;
6. relever les alertes des conseillers de sécurité et de performance ;
7. confirmer qu’une restauration récente est disponible lorsqu’une opération transforme ou supprime des données.

## Contrôles après un déploiement

1. vérifier l’absence de nouveaux `500` dans les journaux concernés ;
2. vérifier les dernières exécutions des crons touchés ;
3. relancer `production_health.sql` ;
4. relancer les conseillers Supabase ;
5. vérifier les parcours réellement modifiés avec les rôles concernés ;
6. vérifier les notifications uniquement si le coupe-circuit global autorise les envois ;
7. confirmer que le registre distant des migrations correspond au déploiement réellement effectué avant toute mise à jour du lock.

## Index et performance

`idx_scan = 0` ou un avertissement « unused index » ne constitue jamais une preuve suffisante pour supprimer un index. Avant toute suppression :

- observer une période représentative couvrant les opérations rares ;
- vérifier clés étrangères, contraintes et requêtes administratives ;
- mesurer le coût et les plans avant/après sur un environnement isolé ;
- prévoir un retour arrière ;
- ne pas mélanger cette optimisation avec un nettoyage fonctionnel sans rapport.

## Incident

En cas d’anomalie après déploiement, arrêter les changements supplémentaires et isoler d’abord la cause. Préférer une migration corrective additive ou une restauration validée à la modification d’une migration déjà appliquée. Les références d’incident côté Flutter sont décrites dans `docs/observability.md`.
