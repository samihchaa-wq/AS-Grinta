# Matrice de sécurité métier

Cette matrice décrit les invariants de sécurité actuels. **PostgreSQL, Storage et les Edge Functions font autorité ; l’interface Flutter n’est jamais une barrière de sécurité.** Les tests automatisés vérifient la surface réelle afin d’éviter de maintenir des listes manuelles de fonctions qui deviennent rapidement obsolètes.

## Rôles

| Rôle | Définition | Accès métier actuel |
|---|---|---|
| `anon` | Requête sans session Supabase Auth | Aucun accès aux tables, vues ou RPC applicatives |
| Compte en attente | JWT valide, profil non actif | Aucun accès métier utile tant que le profil n’est pas actif |
| `pronostiqueur` actif | Joueur connecté | Lectures collectives autorisées et écritures limitées par les politiques/RPC |
| `admin` actif | Staff | Accès aux opérations de gestion après contrôles serveur |
| `moderateur` actif | Staff | Satisfait actuellement les mêmes helpers serveur `is_admin()` / `is_match_staff()` que `admin` |
| `service_role` | Services serveur uniquement | Maintenance, notifications et opérations internes explicitement accordées |

Le nom d’une route ou d’une RPC (`admin_*`, `staff_*`, etc.) n’accorde aucun droit par lui-même : chaque opération sensible doit être protégée côté base ou Edge Function.

## Tables et vues PostgreSQL

Toutes les tables applicatives du schéma `public` ont la RLS activée et `anon` ne possède aucun droit de données direct.

Les tables métier ordinaires possèdent la politique restrictive `active_authenticated_profile_only`. Les politiques permissives définissent ensuite les droits précis d’un profil actif : lecture collective, ligne propriétaire ou action staff.

`public.shared_data_change_signals` est une exception technique volontaire :

- RLS activée ;
- aucun droit pour `anon` ;
- `authenticated` possède uniquement `SELECT` ;
- la policy `shared_data_change_signals_active_read` exige `private.is_active_profile()` ;
- aucune écriture client n’est accordée.

Cette table ne contient pas de donnée métier : elle transporte uniquement une révision Realtime qui demande aux clients de recharger leurs données autoritaires.

Certaines tables internes possèdent en plus une policy restrictive `deny_client_access`. La liste exacte est vérifiée par les tests SQL ; ne pas dupliquer cette liste dans une documentation manuelle.

Les vues publiques doivent utiliser `security_invoker = true` afin de conserver les restrictions de l’appelant.

## Fonctions et RPC

- Aucun `EXECUTE` applicatif ne doit être accordé à `PUBLIC` ou `anon` dans `public` ou `private`.
- Les RPC client sont accordées explicitement à `authenticated`.
- Les opérations serveur sont accordées explicitement aux rôles qui en ont besoin.
- Une fonction `SECURITY DEFINER` accessible à un client doit appliquer elle-même le contrôle d’identité, d’activité et/ou de rôle approprié.
- Les fonctions trigger ne doivent pas devenir des API publiques par un oubli de privilèges.
- Les anciens adaptateurs de compatibilité ne sont retirés qu’après preuve qu’aucun client encore utilisé ne les appelle.

Le nombre et la liste des fonctions privilégiées évoluent avec les migrations. Les tests inspectent donc les ACL PostgreSQL réelles au lieu de considérer une liste Markdown comme une preuve.

## Storage

### `profile-photos`

- lecture prévue par l’application ;
- taille maximale : 5 Mo ;
- formats autorisés : JPEG, PNG et WebP ;
- un joueur actif écrit uniquement dans son périmètre autorisé ;
- un joueur ne modifie ni ne supprime la photo d’un autre compte ;
- les opérations de support restent contrôlées côté serveur/policies.

### `badge-images`

- lecture prévue par l’application ;
- taille maximale : 5 Mo ;
- formats autorisés : JPEG, PNG et WebP ;
- écriture, remplacement et suppression réservés au staff autorisé.

### `app-assets`

Bucket public en lecture pour les ressources de l’application. Aucune écriture client ne doit être accordée.

## Edge Functions

| Fonction | Contrat actuel |
|---|---|
| `manage-user` | JWT et contrôles serveur du staff avant les opérations de compte |
| `register-account` | Endpoint public volontaire avec validation et protections applicatives |
| `send-push` | Endpoint interne sans JWT utilisateur ; transport protégé par le secret serveur prévu |
| `claim-account` | Endpoint retiré conservé temporairement pour compatibilité, réponse `410 Gone` |
| `send-prediction-reminders` | Endpoint retiré conservé temporairement pour compatibilité, réponse `410 Gone` |

Les endpoints `410` ne sont pas des fonctionnalités actives et ne doivent pas être réintroduits. Leur suppression physique exige une preuve d’absence d’appels externes/anciens clients.

## Preuves automatisées

Les contrats sont principalement vérifiés par :

- `supabase/tests/database/security_surface_contract.test.sql` ;
- `supabase/tests/database/role_access_matrix_complete.test.sql` ;
- `supabase/tests/database/storage_access_matrix.test.sql` ;
- les autres tests pgTAP/RLS découverts automatiquement sous `supabase/tests/database/` ;
- `supabase/tests/edge/verify_edge_security_contract.py` ;
- `supabase/functions/send-push/delivery_policy_test.ts`.

La CI construit le schéma de test avec les migrations actuelles nécessaires avant d’exécuter ces contrats. Toute évolution de la surface Supabase doit maintenir l’installation du schéma, tous les tests et le lint SQL au vert.
