# Matrice de sécurité métier

Cette matrice décrit les droits réellement imposés par PostgreSQL, Storage et les Edge Functions. L’interface Flutter ne constitue jamais une barrière de sécurité.

## Rôles

| Rôle | Définition | Accès métier |
|---|---|---|
| `anon` | Requête sans session Supabase Auth | Aucun accès aux tables, vues ou RPC applicatives |
| Compte en attente | JWT valide, profil `status = pending` | Aucun accès aux données métier ; connexion refusée jusqu’à validation |
| Joueur actif | JWT valide, profil actif `pronostiqueur` | Lectures collectives autorisées et écritures limitées à ses propres données |
| Administrateur actif | JWT valide, profil actif `admin` | Actions de gestion après contrôles internes des RPC et politiques RLS |
| `service_role` | Services serveur uniquement | Maintenance, notifications et opérations internes explicitement accordées |

## Données PostgreSQL

Toutes les tables du schéma `public` :

- ont la RLS activée ;
- possèdent une politique restrictive `active_authenticated_profile_only` ;
- refusent donc toutes les opérations d’un JWT rattaché à un profil en attente ou archivé ;
- ne donnent aucun privilège direct à `anon`.

Les politiques permissives existantes définissent ensuite les droits précis d’un profil actif : lecture collective, ligne propriétaire ou action staff. Une politique permissive ne peut jamais contourner la politique restrictive globale.

Les vues publiques utilisent `security_invoker = true` : elles conservent les restrictions RLS de l’appelant au lieu d’utiliser les droits du propriétaire de la vue.

## Fonctions RPC

- Aucun `EXECUTE` n’est accordé à `PUBLIC` ou `anon` dans les schémas `public` et `private`.
- Les RPC client sont accordées explicitement à `authenticated`.
- Les RPC internes sont accordées explicitement à `service_role`.
- Les opérations administrateur contrôlent toujours le profil actif et le rôle côté serveur ; le nom `admin_*` n’est pas considéré comme une protection.
- Les fonctions trigger ne sont jamais appelables comme API publique.

La CI inspecte les ACL réelles de PostgreSQL afin de détecter un futur oubli du `REVOKE EXECUTE FROM PUBLIC` lors de la création d’une fonction.

## Storage

### `profile-photos`

- lecture publique par URL, nécessaire à l’affichage des avatars ;
- taille maximale : 5 Mo ;
- formats : JPEG, PNG et WebP ;
- un joueur actif écrit uniquement dans le dossier portant son UUID ;
- `owner_id` doit correspondre au JWT ;
- un joueur ne modifie ni ne supprime la photo d’un autre compte ;
- un administrateur actif peut gérer les photos pour les opérations de support et de suppression.

### `badge-images`

- lecture publique par URL ;
- taille maximale : 5 Mo ;
- formats : JPEG, PNG et WebP ;
- écriture, remplacement et suppression réservés au staff actif.

### `app-assets`

Bucket public en lecture pour les ressources de l’application. Aucune politique d’écriture client n’est accordée.

## Edge Functions

| Fonction | Protection |
|---|---|
| `manage-user` | JWT obligatoire, validation Auth serveur, profil actif et rôle admin, limite du corps |
| `register-account` | Endpoint public volontaire, POST uniquement, limite du corps, limitation de débit, validation des noms et du mot de passe, nettoyage Auth en cas d’échec |
| `send-push` | Endpoint interne volontairement sans JWT, secret `x-push-token` vérifié avant le traitement et la distribution |
| `claim-account` | JWT obligatoire et endpoint neutralisé par réponse `410 Gone` |
| `send-prediction-reminders` | JWT obligatoire et endpoint neutralisé par réponse `410 Gone` |

Le script `supabase/tests/edge/verify_edge_security_contract.py` bloque la CI si une de ces garanties disparaît.

## Preuves automatisées

- `security_surface_contract.test.sql` : ACL, RLS, vues, RPC et configuration des buckets ;
- `role_access_matrix_complete.test.sql` : visiteur, compte en attente, joueur et administrateur ;
- `storage_access_matrix.test.sql` : propriétaire, usurpation, compte en attente et staff ;
- `verify_edge_security_contract.py` : configuration et gardes des Edge Functions.

Toute modification de la surface Supabase doit maintenir ces tests au vert avant fusion.
