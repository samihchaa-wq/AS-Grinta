# Phase 2 — suivi local totalement isolé

## Garde-fous respectés

Cette validation n’a effectué **aucune écriture sur les deux projets Supabase existants**.

- aucun projet Supabase lié au CLI ;
- aucun projet restauré, renommé, mis en pause ou supprimé ;
- aucune migration distante appliquée ;
- aucune donnée réelle copiée ;
- aucune fusion et aucun déploiement.

## Tentative Supabase local avec Docker

Le moteur Docker a pu être installé et son démon a démarré localement. Le noyau du bac à sable interdit toutefois la création de conteneurs et renvoie :

```text
unshare: operation not permitted
```

La pile Supabase Docker complète n’a donc pas pu être démarrée dans cet environnement. Cette limite est propre au bac à sable d’exécution et ne concerne pas le dépôt ni les applications.

## Validation de repli sur PostgreSQL 17

Les fichiers exacts de la PR #246 ont été validés dans une instance PostgreSQL **17.10** locale, temporaire et supprimée à la fin des tests.

Le jeu de données était entièrement synthétique :

- 57 profils ;
- 4 badges ;
- 12 000 badges attribués ;
- 8 000 récompenses de saison ;
- 57 lignes de statistiques et de classement pour l’utilisateur normal ;
- 57 lignes pour l’administrateur.

## Résultats

- le test `supabase/tests/phase1_security_hardening.sql` passe intégralement ;
- `anon` reçoit bien `permission denied` sur `featured_badges()` ;
- `anon` reçoit bien `permission denied` sur `v_statistics_players` ;
- l’utilisateur normal et l’administrateur conservent l’accès et obtiennent chacun 12 badges mis en avant ;
- les condensats des profils, badges, attributions, récompenses, statistiques et classements sont strictement identiques avant et après migration ;
- `profile_badges_awarded_by_idx`, `profile_badges_badge_id_idx` et `season_awards_profile_id_idx` sont présents ;
- `EXPLAIN` confirme que PostgreSQL choisit réellement chacun des trois index ;
- une deuxième application des migrations réussit ;
- les trois scripts `.down.sql` réussissent dans l’ordre inverse ;
- les droits, l’option de vue et l’absence des index sont correctement restaurés par les rollbacks ;
- les migrations sont ensuite réappliquées et le test SQL repasse ;
- l’environnement PostgreSQL temporaire a été arrêté et supprimé.

## Verdict

Les migrations ciblées sont **cohérentes, idempotentes et réversibles** dans PostgreSQL 17 avec des rôles et données représentatifs.

La seule vérification non réalisable dans ce bac à sable est le démarrage de la pile Supabase Docker complète. La PR reste donc en brouillon et ne doit pas être fusionnée ou déployée automatiquement.
