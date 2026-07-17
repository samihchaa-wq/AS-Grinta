# Phase 2 — validation isolée du durcissement Supabase

## Résumé

Les trois migrations de la PR #246 ont été validées sans déploiement et sans
modification de la base de production.

La création d'une branche Supabase temporaire a été tentée après confirmation
du coût de **0,01344 USD par heure**, mais l'API Supabase a renvoyé :

`PaymentRequiredException: Branching is supported only on the Pro plan or above`

Le projet `AS-Grinta` est actuellement sur le forfait Free. La liste des
branches a ensuite été vérifiée : seule la branche `main` existe. Aucun coût de
branche n'a donc été engagé et aucune branche temporaire ne restait à supprimer.

Pour ne pas toucher à la production, les migrations ont été testées dans une
instance locale isolée **PostgreSQL 17.10**, avec les rôles `anon`,
`authenticated`, `service_role`, un utilisateur normal, un administrateur et un
jeu de données représentatif.

## Migrations testées

1. `20260719010000_harden_public_rpc_execute_privileges.sql`
2. `20260719011000_statistics_view_security_invoker.sql`
3. `20260719012000_add_fk_supporting_indexes.sql`

Les fichiers exacts de la PR ont été appliqués dans cet ordre.

## Résultats de sécurité

- le test `supabase/tests/phase1_security_hardening.sql` passe intégralement ;
- un appel réel de `featured_badges()` avec le rôle `anon` échoue avec
  `permission denied` ;
- un utilisateur authentifié et l'administrateur peuvent toujours exécuter le
  RPC et obtiennent chacun les deux lignes attendues du jeu de test ;
- `v_statistics_players` possède `security_invoker=true` ;
- `anon` ne peut pas lire la vue ;
- les rôles authentifiés conservent la lecture.

## Non-régression des données

Les condensats sont strictement identiques avant et après migration :

| Domaine | Avant | Après |
| --- | --- | --- |
| Profils | `34c4dbe5b81b12a70ce4c1a2396fb5db` | `34c4dbe5b81b12a70ce4c1a2396fb5db` |
| Badges | `9831267ef4b3214399b60d583de3e803` | `9831267ef4b3214399b60d583de3e803` |
| Badges attribués | `da0031843f7df6ba4b35edd99538c6fb` | `da0031843f7df6ba4b35edd99538c6fb` |
| Statistiques utilisateur | `b1fe64085d7c479bb1877b486f86c209` | `b1fe64085d7c479bb1877b486f86c209` |
| Statistiques administrateur | `b1fe64085d7c479bb1877b486f86c209` | `b1fe64085d7c479bb1877b486f86c209` |
| Définition de la vue | `3547f6456607f80a84f991a17a5cf313` | `3547f6456607f80a84f991a17a5cf313` |

La migration ne modifie donc ni les profils, ni les badges, ni les classements,
ni les statistiques dans le scénario testé.

## Index

Les trois index sont créés et le planificateur PostgreSQL les utilise lorsque
la requête correspondante est exécutée :

- `profile_badges_awarded_by_idx` ;
- `profile_badges_badge_id_idx` ;
- `season_awards_profile_id_idx`.

L'application répétée des migrations est également validée ; les clauses
`if not exists` évitent les erreurs sur les index.

## Retours arrière

Les trois scripts `.down.sql` ont été appliqués dans l'ordre inverse :

- les anciens droits RPC ont été restaurés ;
- l'option `security_invoker` de la vue a été retirée ;
- les trois index ont été supprimés ;
- les données et les statistiques sont restées identiques.

Les migrations ont ensuite été réappliquées avec succès sur l'environnement
local.

## Conseillers Supabase — état de production en lecture seule

Les conseillers ont été exécutés sur la production uniquement en lecture :

- **Security Advisor** confirme l'alerte `security_definer_view` sur
  `v_statistics_players` et les quatre alertes d'exécution anonyme des RPC que
  cette PR corrige ;
- **Performance Advisor** confirme exactement les trois clés étrangères non
  indexées que cette PR corrige ;
- restent hors du périmètre de cette PR : la protection contre les mots de passe
  compromis, les avertissements généraux sur les RPC authentifiés et deux tables
  RLS sans politique explicite.

Les conseillers n'ont pas pu être exécutés après migration sur une branche
Supabase, puisque le forfait Free interdit la création de cette branche.

## Intégrité de la production

Deux instantanés en lecture seule pris avant et après les tests sont identiques :

| Domaine | Lignes | MD5 |
| --- | ---: | --- |
| Profils | 3 | `164975bf331743d144eb068695d1e75c` |
| Badges | 70 | `9d21b2499215c83ef610c7911aef8a2e` |
| Badges attribués | 3 | `16d838359bb97c82f1412cee9b4a48f2` |
| Statistiques | 57 | `3b777ec4ab61cdc361f0f7253e1f8fe2` |
| Pronostics saison | 38 | `2330ebdf6d3f7c3df0f6f16b63046985` |
| Matchs | 156 | `dd74b2c3f511d811be65fe587bc502c0` |

Aucune migration, fonction ou donnée n'a été modifiée en production.

## CI Flutter et GitHub

Sur le commit de la PR avant ajout de ce rapport :

- `Supabase migration guard` : succès ;
- `Flutter CI` : succès ;
- étapes `Analyze`, `Test` et `Build web` : succès ;
- `Runtime diagnostic` : succès.

L'ajout de ce rapport déclenche une nouvelle exécution des workflows sur le
nouveau commit de la PR.

## Verdict

**Les trois migrations sont techniquement sûres et réversibles dans les tests
isolés effectués.** Elles ne modifient aucune ligne métier et corrigent
exactement les alertes ciblées par les conseillers Supabase.

Cependant, la validation complète sur une vraie branche Supabase n'a pas pu
être réalisée à cause du forfait Free. La PR doit rester en brouillon et ne doit
pas être fusionnée ni appliquée en production tant qu'une des deux garanties
suivantes n'est pas disponible :

1. passage temporaire au forfait Pro et validation sur une branche Supabase ; ou
2. sauvegarde PostgreSQL complète restaurée dans un projet de test séparé.
