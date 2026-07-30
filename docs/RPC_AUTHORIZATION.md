# Contrat d’autorisation des RPC

Ce document décrit les règles vérifiées sur le projet Supabase de production.
Il doit être mis à jour lorsqu’une RPC publique est ajoutée, renommée ou
supprimée.

## Principes

- Le rôle `anon` ne possède aucun droit `EXECUTE` sur les fonctions métier des
  schémas `public` et `private`.
- Les RPC exposées aux utilisateurs sont accordées explicitement au rôle
  `authenticated`.
- Les opérations personnelles doivent dériver l’identité de `auth.uid()` et ne
  jamais accepter un identifiant de propriétaire fourni par le client.
- Les opérations administratives doivent vérifier le rôle administrateur dans
  la fonction privilégiée appelée.
- Les wrappers publics du module sportif sont `SECURITY INVOKER` et délèguent
  aux fonctions du schéma `private`, où les contrôles métier et administrateur
  sont centralisés.
- Les fonctions de trigger, de maintenance, de recalcul et de distribution push
  ne sont pas exécutables par `authenticated`, sauf lorsqu’elles constituent
  volontairement une RPC utilisateur.

## Familles de RPC

### Utilisateur connecté

- `get_my_profile`
- `complete_password_change`
- `export_my_personal_data`
- `register_push_subscription`
- `update_my_app_preferences`
- `save_match_prediction`
- `get_my_match_availability`
- `set_my_match_availability`
- `get_match_motm_vote`
- `cast_match_motm_vote`
- lectures des compositions, résultats, statistiques et badges autorisées aux
  profils actifs

Ces fonctions utilisent `auth.uid()` directement ou délèguent à une fonction
privée qui résout l’utilisateur courant.

### Administrateur

Les RPC préfixées `admin_` et `staff_`, ainsi que les opérations de cycle de vie
des matchs et saisons, sont réservées aux administrateurs. Les wrappers publics
du module sportif délèguent aux fonctions privées ; les RPC historiques
`SECURITY DEFINER` conservent un contrôle administrateur dans leur corps.

### Service interne

Les fonctions préfixées `internal_`, les fonctions de recalcul, de seed, les
fonctions de trigger et les opérations de maintenance ne sont pas accordées au
rôle `authenticated`. Elles sont réservées au propriétaire, aux triggers ou au
`service_role` selon leur usage.

## Contrôle obligatoire en CI

Toute évolution doit échouer si :

1. une fonction métier devient exécutable par `anon` ;
2. une nouvelle fonction `SECURITY DEFINER` est accordée à `authenticated`
   sans test explicite d’autorisation ;
3. une RPC personnelle accepte un identifiant de profil à la place de
   `auth.uid()` ;
4. un helper interne est ajouté au schéma exposé sans révocation explicite ;
5. la liste des RPC de production diverge des migrations du dépôt.

## Nettoyage du 29 juillet 2026

Les fonctions orphelines suivantes ont été supprimées :

- `public.calculate_match_odds_v3(uuid, text)` ;
- `public.recalculate_upcoming_match_odds_v3()`.

Elles n’avaient aucune dépendance PostgreSQL et aucune référence applicative.
Les wrappers et triggers v4 restent actifs : leur nom est historique, mais ils
font encore partie du contrat de production et ne sont donc pas du code mort.
