# Phase 1 — durcissement Supabase sans impact visuel

## Statut

Les changements de cette branche sont préparés uniquement. Ils ne doivent pas
être appliqués directement au projet Supabase de production tant qu'un dump
PostgreSQL chiffré ou une branche Supabase isolée n'a pas été créé et restauré
en test.

Aucune migration de cette branche n'a été appliquée de manière persistante lors
de sa préparation. Toutes les validations SQL ont été exécutées dans des
transactions terminées par `ROLLBACK`.

## Changements préparés

1. Retrait du droit `EXECUTE` anonyme sur quatre fonctions
   `SECURITY DEFINER` ; les rôles `authenticated` et `service_role` conservent
   leur accès.
2. Passage de `v_statistics_players` à `security_invoker=true`, sans accès
   anonyme et avec lecture authentifiée conservée.
3. Ajout de trois index de soutien de clés étrangères, sans modification de
   lignes métier.

Chaque migration possède un script `.down.sql` sous `supabase/rollbacks/`.

## Validation transactionnelle effectuée

- `featured_badges()`, `profile_badge_stars(uuid)`,
  `staff_list_historical_players()` et
  `staff_set_historical_profile(uuid,bigint)` : accès anonyme supprimé,
  accès authentifié et service conservé.
- Statistiques avec un utilisateur actif : 57 lignes avant et après,
  condensat identique `14067aaf0cab509659364f421124eb1d`.
- Statistiques avec l'administrateur actif : 57 lignes, même condensat.
- Les trois index ont été créés avec succès dans une transaction annulée.

## Porte de mise en production

Avant toute application persistante :

- créer un dump PostgreSQL chiffré ou une branche Supabase de développement ;
- tester la restauration ;
- appliquer les migrations dans l'ordre ;
- exécuter `supabase/tests/phase1_security_hardening.sql` ainsi que les autres
  tests SQL ;
- refaire les parcours badges et statistiques avec un utilisateur normal et un
  administrateur ;
- vérifier les conseillers de sécurité et de performance Supabase.
