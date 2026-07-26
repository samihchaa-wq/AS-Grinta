# Surveillance de production

## Périmètre

Cette procédure couvre les services Supabase utilisés par l’application : API REST, PostgreSQL, Auth, Storage, Realtime et fonctions Edge.

Le script `supabase/diagnostics/production_health.sql` fournit les contrôles SQL reproductibles. Il est strictement en lecture seule.

## Seuils d’intervention

Une investigation est nécessaire dans les situations suivantes :

- une fonction Edge renvoie une réponse `500` ;
- une tâche planifiée termine avec un statut différent de `succeeded` ;
- une requête applicative récurrente dépasse 100 ms en moyenne ou 1 seconde au maximum ;
- une transaction reste ouverte ou bloquée plus de 30 secondes ;
- un profil actif n’a plus de compte Auth associé ;
- le conseiller Supabase signale un index manquant, une RLS absente ou une fonction privilégiée nouvellement exposée ;
- le nombre d’échecs de notification augmente ou des abonnements invalides ne sont pas nettoyés.

## État de référence du 26 juillet 2026

- les accès API observés sont servis normalement ;
- les tâches de disponibilité sportive et de vote HDM terminent correctement ;
- les requêtes applicatives récurrentes principales restent sous 30 ms en moyenne ;
- aucune alerte d’index manquant n’est remontée ;
- neuf index sont signalés comme non utilisés depuis le redémarrage de la base du 8 juillet 2026 ;
- aucun de ces index ne doit être supprimé avant une période d’observation plus longue couvrant les opérations rares et les pics de saison ;
- aucun profil actif ou en attente n’est actuellement dépourvu de compte Auth ;
- le seul échec Edge récent encore présent sur la version courante de `manage-user` correspondait à une tentative de réinitialisation d’un compte Auth déjà absent.

## Traitement des index non utilisés

L’indicateur `idx_scan = 0` ne suffit pas à prouver qu’un index est inutile. Avant toute suppression :

1. conserver au moins trente jours de statistiques représentatives ;
2. vérifier que l’index ne protège pas une clé étrangère ou une opération administrative rare ;
3. comparer sa taille au gain d’écriture attendu ;
4. tester la suppression sur un environnement isolé ;
5. conserver un script de retour arrière ;
6. mesurer les requêtes concernées avant et après le changement.

## Fonctions Edge temporaires

`import-match-background` et `tmp-match-form-merge-493` sont neutralisées et répondent `410 Gone`. Leur présence active ne donne plus accès à une opération de maintenance, mais elles pourront être supprimées depuis le tableau de bord Supabase lorsque la suppression de fonctions sera disponible dans le processus de livraison.

## Contrôle après déploiement

Après chaque changement de fonction Edge ou de base de données :

1. vérifier les journaux de la fonction et de l’API ;
2. exécuter le diagnostic SQL ;
3. relancer les conseillers Supabase de sécurité et de performance ;
4. confirmer l’absence de nouveaux `500`, blocages et échecs de tâches planifiées ;
5. vérifier les parcours réellement modifiés avec un compte joueur et un compte administrateur.
