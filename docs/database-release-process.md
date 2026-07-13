# Processus de livraison Supabase

## Règle principale

`main` est la source de vérité du schéma de production.

Aucune migration ne doit être appliquée directement en production avant que son fichier SQL ne soit fusionné dans `main`.

## Créer une migration

1. Créer un nouveau fichier dans `supabase/migrations/`.
2. Utiliser un nom au format `YYYYMMDDHHMMSS_description.sql`.
3. Utiliser un timestamp unique.
4. Ne jamais modifier ou supprimer une migration déjà fusionnée.
5. Ouvrir une pull request et attendre les validations.
6. Déployer uniquement depuis le commit fusionné dans `main`.

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
4. mise à jour dédiée de `production_migrations.lock`.

Une dérive détectée doit être traitée avant toute nouvelle modification de schéma.
