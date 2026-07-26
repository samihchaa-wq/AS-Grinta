# Processus de livraison Supabase

## Règle principale

`main` est la source de vérité du schéma de production.

Aucune migration ne doit être appliquée directement en production avant que son fichier SQL ne soit fusionné dans `main`.

## Créer une migration

1. Créer un nouveau fichier dans `supabase/migrations/`.
2. Utiliser un nom au format `YYYYMMDDHHMMSS_description.sql`.
3. Utiliser un timestamp unique.
4. Ne jamais modifier ou supprimer une migration déjà fusionnée.
5. Ajouter un test SQL pour les permissions ou invariants modifiés.
6. Préparer un script de retour arrière dans `supabase/rollbacks/` lorsqu’un retour est techniquement possible.
7. Ouvrir une pull request et attendre toutes les validations.
8. Déployer uniquement depuis le commit fusionné dans `main`.

## Contrôle avant production

Avant toute migration qui supprime, renomme ou transforme des données :

1. vérifier qu’une sauvegarde Supabase récente est disponible ;
2. noter l’heure de la sauvegarde et le commit GitHub à déployer ;
3. exécuter la migration sur un environnement temporaire ou dans une transaction annulée ;
4. exécuter les tests pgTAP et les requêtes d’intégrité concernées ;
5. relire le script de retour arrière ;
6. prévoir une fenêtre pendant laquelle aucun administrateur ne modifie les mêmes données.

Une sauvegarde n’est considérée comme fiable qu’après un test périodique de restauration sur un environnement non productif.

## Déploiement

1. relever les indicateurs d’intégrité avant le changement ;
2. appliquer une seule migration ou un lot cohérent ;
3. vérifier immédiatement les droits, contraintes, triggers et données touchés ;
4. relancer les conseillers de sécurité et de performance Supabase ;
5. effectuer un test fonctionnel avec les rôles `anon`, `authenticated` et administrateur ;
6. surveiller les erreurs de l’application et des fonctions Edge.

En cas d’anomalie, arrêter les autres déploiements. Utiliser le rollback seulement si son effet a été validé ; sinon restaurer la sauvegarde dans un environnement isolé avant toute action destructive.

## Historique existant

Le dépôt contient un historique ancien dont certains noms de fichiers ne correspondent pas exactement aux identifiants enregistrés par Supabase. Cette situation est figée dans `supabase/production_migrations.lock`.

À partir de la baseline actuelle, toute nouvelle migration doit conserver le même identifiant dans GitHub et dans l’historique Supabase.

## Contrôle automatique

Le workflow `Supabase migration guard` :

- refuse la modification ou la suppression d’une migration existante ;
- vérifie le format et l’unicité des nouvelles migrations ;
- empêche une PR fonctionnelle de modifier directement la baseline de production ;
- compare chaque jour l’historique distant à la baseline vérifiée.

Le contrôle distant nécessite les secrets GitHub suivants :

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`

Le projet utilisé est `ovzijmqrnsgcmryinkfa`.

## Mise à jour de la baseline

La baseline ne doit être modifiée qu’après :

1. fusion de la migration dans `main` ;
2. déploiement réussi depuis `main` ;
3. vérification de l’historique distant ;
4. mise à jour dédiée de `production_migrations.lock` depuis la branche `ci/supabase-migration-drift-guard`.

Une dérive détectée doit être traitée avant toute nouvelle modification de schéma.
