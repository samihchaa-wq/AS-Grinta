# AS-Grinta — instructions obligatoires pour les agents

## Source de vérité

La **production actuelle** est la référence fonctionnelle de AS Grinta.

Pour toute conclusion sur une fonctionnalité :

1. vérifier ce qui fonctionne réellement en production ;
2. vérifier le schéma et les objets Supabase distants ;
3. vérifier que le code GitHub actuel est réellement appelé ;
4. utiliser l'historique Git/PR uniquement pour comprendre pourquoi un élément existe.

Ne jamais conclure qu'une fonctionnalité existe simplement parce que son code est
présent dans le dépôt.

Les anciennes migrations dans `supabase/migrations/` sont l'historique immuable
de la base. Une migration appliquée ne doit jamais être modifiée ou supprimée,
même si elle décrit un comportement qui a depuis été remplacé.

Les documents historiques, notamment `docs/DESIGN_V1.md`, ne sont **pas** la
source de vérité du produit actuel. En cas de contradiction, la production et
l'implémentation active prévalent.

## État fonctionnel actuel à préserver

- Rôles actifs : `pronostiqueur`, `admin` et `moderateur`.
- Le module `sports_management` est en production.
- Le module **Live** est actuel et utilisé : sessions, chronomètre, événements,
  remplacements et validation du récapitulatif font partie du produit.
- Un match entre dans la fenêtre « Prochain match » à **J-6 à 12 h**, heure
  Europe/Paris.
- Les disponibilités ouvrent à **J-6 à 12 h**.
- Les pronostics ferment à **T-15**.
- Le Live ouvre à **T-15**.
- Effectif et Composition sont gelés à **T-15**.
- Un match Live doit être validé avant son passage normal en match passé.
- Le vote Homme du match ouvre après la validation du compte rendu et reste
  ouvert **24 heures**.
- Un joueur ajouté tardivement au Live est ajouté directement sur le banc.
- Le réglage utilisateur HDM couvre l'ouverture du vote **et** son résultat.
- Le portefeuille / multiplicateur **×2 a été retiré du produit actuel**. Des
  migrations ou signatures de compatibilité peuvent encore en garder la trace.

Les valeurs opérationnelles comme les feature flags ou le coupe-circuit des
notifications peuvent changer : toujours les lire en production avant d'en
conclure l'état.

## Règle de nettoyage

Pour chaque élément suspect, distinguer :

- **A — actuel et utilisé** : ne pas toucher ;
- **B — historique nécessaire** : conserver ;
- **C — code mort confirmé** : suppression possible ;
- **D — ancienne implémentation remplacée** : suppression possible après preuve
  qu'aucune dépendance actuelle ne l'utilise ;
- **E — doublon** : conserver l'implémentation actuelle ;
- **F — documentation/commentaire obsolète** : corriger ou supprimer ;
- **G — incertain** : ne rien supprimer.

**En cas de doute, ne pas supprimer.** Un nom comme `legacy`, `old`, `v2`, `v3`
ou un compteur d'utilisation nul ne constitue jamais une preuve suffisante.
Tenir compte des anciens clients, deep-links et contrats de compatibilité avant
de retirer une RPC, une route ou une Edge Function.

## Règles techniques

- Supabase reste l'unique source de vérité pour les données métier.
- Ne jamais utiliser la clé `service_role` dans Flutter.
- Respecter Riverpod, go_router et l'architecture feature-first.
- Toute évolution de schéma doit passer par une **nouvelle migration additive ou
  corrective** ; ne jamais réécrire une migration déjà appliquée.
- Avant chaque lot, tracer les références et dépendances de chaque suppression.
- Faire des lots petits et cohérents.
- Après chaque lot important : formatage Dart, analyse statique, tests Flutter,
  build web et contrôles Supabase/RLS concernés.
- Ne jamais fusionner une PR dont les contrôles requis sont rouges.

## Verrou de migrations

Le fichier `supabase/production_migrations.lock` reflète l'état vérifié de la
production : nombre de migrations, dernière version et empreinte de la liste des
versions.

Le workflow `migration_inventory.yml` compare périodiquement la production à ce
verrou. Après un déploiement de migrations vérifié, resynchroniser le lock via
la branche dédiée `ci/supabase-migration-drift-guard`, seule autorisée à le
modifier.
