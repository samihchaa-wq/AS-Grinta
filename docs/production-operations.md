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
- `prediction-j5-reminders`.

Toujours lire `cron.job` avant une intervention : un ancien enregistrement dans `cron.job_run_details` n’est pas la preuve qu’une tâche est encore active.

## Notifications

Le coupe-circuit global des notifications est une **valeur opérationnelle**, pas une constante fonctionnelle. Vérifier le flag distant avant d’analyser une absence de push.

Même lorsque les push sont suspendus, les transitions métier qui ne dépendent pas d’un envoi doivent continuer à fonctionner. Ne jamais déduire l’état d’une disponibilité, d’un prono ou d’un scrutin HDM uniquement à partir des journaux de push.

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
