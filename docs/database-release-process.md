# Processus de livraison Supabase

## Sources de vérité

La **production distante** est la source de vérité de l’état réellement en service.

`main` contient l’historique Git conservé et la définition des changements qui doivent être livrés. Une migration nouvelle ne doit pas être appliquée en production avant que son fichier SQL ne soit fusionné dans `main`.

L’historique ancien GitHub et le registre de migrations Supabase ne sont pas historiquement 1:1. Cette divergence ne doit jamais être « réparée » dans le cadre d’un changement fonctionnel en renommant, supprimant, rejouant ou marquant arbitrairement d’anciennes migrations.

## Créer une migration

1. créer une nouvelle migration via l’outil Supabase prévu (`supabase migration new <nom>`) ou produire un fichier au format courant équivalent ;
2. utiliser un timestamp nouveau et unique ;
3. ne jamais modifier, renommer ou supprimer une migration déjà appliquée ;
4. ajouter ou adapter les tests SQL pour les permissions et invariants modifiés ;
5. préparer un retour arrière uniquement lorsqu’il est techniquement sûr et utile ;
6. ouvrir une pull request et attendre les contrôles requis ;
7. déployer uniquement depuis une révision fusionnée et identifiée de `main`.

## CI avant fusion

La suite Supabase isolée doit :

- démarrer une base éphémère ;
- installer le schéma métier et les migrations courantes nécessaires dans leur ordre réel ;
- vérifier le contrat de sécurité des Edge Functions ;
- tester la résilience de `send-push` ;
- découvrir et exécuter tous les fichiers `supabase/tests/database/*.test.sql` ;
- exécuter `supabase db lint --level error`.

Une CI verte n’autorise pas à réécrire l’historique : elle prouve seulement que la révision candidate respecte les contrats testés.

## Contrôle avant production

Avant tout déploiement SQL :

1. relever l’état distant (`supabase migration list`) ;
2. comparer cet état au lock de production et au changement à livrer ;
3. traiter toute dérive inattendue comme un incident séparé avant d’appliquer une nouvelle migration ;
4. confirmer qu’une sauvegarde/restauration adaptée est disponible pour une opération destructive ou de transformation ;
5. vérifier les tests et diagnostics liés au domaine modifié ;
6. noter le commit GitHub exact à déployer.

## Déploiement

1. partir d’un commit fusionné dans `main` ;
2. vérifier une dernière fois le registre distant ;
3. appliquer uniquement les migrations nouvelles réellement attendues ;
4. vérifier immédiatement contraintes, triggers, RLS, ACL et données touchées ;
5. relancer les conseillers de sécurité et de performance ;
6. vérifier les parcours applicatifs concernés ;
7. surveiller les journaux et tâches planifiées affectés.

En cas d’anomalie, arrêter les autres changements. Préférer une migration corrective additive ou une restauration dont l’effet a été validé à la modification d’un fichier déjà appliqué.

## Verrou de production

`supabase/production_migrations.lock` représente un **point de contrôle vérifié** du registre distant : nombre de versions, dernière version et empreinte.

Le workflow de garde des migrations vérifie le format local et contrôle la dérive distante dans ses exécutions prévues. Une PR ordinaire ne doit pas modifier ce lock pour masquer un écart.

Après un déploiement vérifié, la resynchronisation du lock se fait dans le mécanisme dédié prévu par le dépôt, actuellement la branche `ci/supabase-migration-drift-guard`.

## Historique ancien

Les anciens fichiers de migration sont une archive exécutable du projet et sont classés **historique nécessaire**. Un comportement obsolète dans une ancienne migration n’est jamais du code mort à supprimer. Le comportement actuel se vérifie sur les objets réellement présents en production et sur les dernières définitions qui les ont remplacés.
