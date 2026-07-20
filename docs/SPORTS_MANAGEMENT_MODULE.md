# AS Grinta — Architecture du module optionnel de gestion sportive

Statut : **proposition d’architecture — aucune mise en production**  
Date : **20 juillet 2026**  
Branche de travail : `agent/sports-management-module-design`

## 0. Décision et portée

Ce document définit le module optionnel de gestion sportive demandé pour AS Grinta. Il complète la V1 existante sans remplacer le parcours historique.

La règle structurante est la suivante :

- lorsque le feature flag global est désactivé, l’application conserve exactement le parcours post-match actuel ;
- lorsque le feature flag est activé, les disponibilités, convocations, compositions, invités réutilisables, présences finales et vote collectif deviennent disponibles ;
- la désactivation ne supprime aucune donnée et bloque réellement les fonctions du module côté interface, routes, base, Edge Functions et tâches programmées.

Ce document devient prioritaire sur `docs/DESIGN_V1.md` uniquement pour le périmètre du module de gestion sportive. En particulier, lorsque le module est activé :

- les notifications liées au module sont autorisées ;
- plusieurs hommes du match sont possibles en cas d’égalité ;
- un invité présent peut être candidat homme du match ;
- le choix manuel historique de l’homme du match est remplacé par le scrutin collectif.

Le comportement historique reste inchangé lorsque le module est désactivé.

## 1. Architecture fonctionnelle complète

### 1.1 Composants

Le module est découpé en six sous-domaines indépendants :

1. **Configuration et feature flag**
   - lecture publique authentifiée du statut du module ;
   - modification réservée aux administrateurs ;
   - journalisation de chaque activation et désactivation.

2. **Préparation du match**
   - calcul de l’ouverture à `kickoff_at - interval '144 hours'` ;
   - création de la population concernée ;
   - réponses Disponible / Absent ;
   - relances automatiques et manuelles.

3. **Convocation et composition**
   - décision Titulaire / Remplaçant / Non convoqué ;
   - brouillon et publication versionnée ;
   - terrain à coordonnées normalisées ;
   - avertissements non bloquants et règles bloquantes côté serveur.

4. **Invités**
   - catalogue réutilisable ;
   - rattachement à un match ;
   - participation à la composition, aux présences, aux statistiques de match et au résultat du vote.

5. **Finalisation post-match**
   - préremplissage depuis titulaires et remplaçants ;
   - correction obligatoire par le staff ;
   - écriture atomique de la présence définitive et des statistiques ;
   - ouverture du vote uniquement après validation des participants réels.

6. **Vote homme du match**
   - scrutin de 24 heures ;
   - vote unique, secret et non modifiable ;
   - interdiction du vote pour soi-même ;
   - résultats cachés avant clôture ;
   - égalités acceptées ;
   - audit de toutes les interventions administratives.

### 1.2 Réutilisation du socle existant

Le module doit réutiliser :

- `matches.kickoff_at` comme instant absolu du coup d’envoi ;
- `season_players` comme effectif de saison ;
- `season_players.profile_id` pour identifier les joueurs disposant d’un compte ;
- `match_attendance` comme source de vérité finale des présences des joueurs permanents ;
- `match_man_of_match` comme table de compatibilité pour les gagnants permanents ;
- le pipeline Web Push existant et l’Edge Function `send-push` ;
- les vues, statistiques et badges actuels ;
- les RPC atomiques existantes pour le parcours historique.

Le module ne doit pas détourner les disponibilités ou convocations pour alimenter directement les statistiques. Seule la présence finale validée est statistique.

### 1.3 Deux parcours isolés

#### Module désactivé

- aucune création de workflow sportif ;
- aucune écriture dans les tables du module ;
- aucune notification du module ;
- aucune route sportive accessible ;
- finalisation via le RPC historique ;
- choix manuel facultatif de l’homme du match.

#### Module activé

- création ou synchronisation d’un workflow pour chaque match à venir ;
- ouverture et relances ;
- composition versionnée ;
- finalisation des présences ;
- scrutin collectif ;
- synchronisation des résultats finaux avec les tables historiques.

## 2. Schéma de base de données proposé

Les noms ci-dessous sont proposés. Les migrations doivent être additives et non destructives.

### 2.1 Schéma privé de configuration

#### `private.app_feature_flags`

| Colonne | Type | Règle |
|---|---|---|
| `key` | text PK | ex. `sports_management` |
| `enabled` | boolean | défaut `false` |
| `config` | jsonb | paramètres versionnés |
| `updated_at` | timestamptz | serveur |
| `updated_by` | uuid nullable | profil administrateur |

Configuration recommandée :

```json
{
  "availability_open_hours_before": 144,
  "reminder_hours_before": [72, 24],
  "usual_squad_size": 14,
  "vote_duration_hours": 24,
  "timezone": "Europe/Paris"
}
```

La table reste dans un schéma non exposé. Flutter lit une projection via RPC.

### 2.2 Workflow par match

#### `public.match_sport_workflows`

| Colonne | Type | Règle |
|---|---|---|
| `match_id` | uuid PK FK matches | un workflow maximum par match |
| `availability_state` | enum | pending/open/closed |
| `availability_opens_at` | timestamptz | `kickoff_at - 144 h` |
| `availability_opened_at` | timestamptz nullable | ouverture réelle |
| `composition_state` | enum | none/draft/published/updated/closed |
| `composition_version` | integer | défaut 0 |
| `presence_state` | enum | pending/confirmed |
| `vote_state` | enum | unavailable/draft/open/closed/cancelled |
| `created_at` | timestamptz | serveur |
| `updated_at` | timestamptz | serveur |

Cette table est conservée lorsque le flag est désactivé. Elle ne contient pas de copie du flag global.

### 2.3 Participants du workflow

#### `public.match_sport_participants`

Une ligne représente une personne liée à un match dans le module.

| Colonne | Type | Règle |
|---|---|---|
| `id` | uuid PK | identifiant du participant du match |
| `match_id` | uuid FK | requis |
| `season_player_id` | uuid nullable FK | joueur permanent |
| `guest_player_id` | uuid nullable FK | invité du catalogue |
| `availability_status` | enum | no_response/available/absent/not_applicable |
| `availability_comment_private` | text nullable | non public par défaut |
| `availability_updated_at` | timestamptz nullable | dernière réponse |
| `availability_updated_by` | uuid nullable | joueur ou staff |
| `selection_status` | enum | undecided/starter/substitute/not_selected |
| `selection_updated_at` | timestamptz nullable | serveur |
| `selection_updated_by` | uuid nullable | staff |
| `final_presence_status` | enum | pending/present/actual_absent |
| `final_presence_confirmed_at` | timestamptz nullable | serveur |
| `final_presence_confirmed_by` | uuid nullable | staff |
| `created_at` | timestamptz | serveur |
| `updated_at` | timestamptz | serveur |

Contraintes :

- exactement une identité parmi `season_player_id` et `guest_player_id` ;
- unicité `(match_id, season_player_id)` quand non nul ;
- unicité `(match_id, guest_player_id)` quand non nul ;
- un invité a toujours `availability_status = not_applicable` ;
- un joueur `not_selected` ne peut pas être prérempli présent ;
- la présence définitive ne dépend jamais automatiquement du statut de disponibilité.

### 2.4 Historique des réponses et décisions

#### `public.match_sport_participant_events`

| Colonne | Type |
|---|---|
| `id` | bigint identity PK |
| `participant_id` | uuid FK |
| `event_type` | text |
| `old_value` | jsonb nullable |
| `new_value` | jsonb nullable |
| `actor_profile_id` | uuid nullable |
| `actor_kind` | text |
| `created_at` | timestamptz |

Cette table permet de détecter et afficher un changement après publication sans écraser l’historique.

### 2.5 Catalogue des invités

#### `public.guest_players`

| Colonne | Type | Règle |
|---|---|---|
| `id` | uuid PK | |
| `first_name` | text | seul champ obligatoire |
| `display_name` | text généré ou vue | `Prénom (Invité)` |
| `is_reusable` | boolean | défaut true |
| `archived_at` | timestamptz nullable | retrait de la liste |
| `created_by` | uuid | staff |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

La suppression fonctionnelle met `is_reusable = false` et renseigne `archived_at`. Aucun `DELETE` n’est exposé au client. Les références historiques sont préservées.

### 2.6 Composition courante

#### `public.match_compositions`

| Colonne | Type |
|---|---|
| `match_id` | uuid PK FK |
| `formation_code` | text nullable |
| `status` | enum draft/published/updated/closed |
| `version` | integer |
| `published_at` | timestamptz nullable |
| `published_by` | uuid nullable |
| `last_modified_at` | timestamptz |
| `last_modified_by` | uuid |
| `closed_at` | timestamptz nullable |

#### `public.match_composition_entries`

| Colonne | Type | Règle |
|---|---|---|
| `composition_match_id` | uuid FK | |
| `participant_id` | uuid FK | unique par composition |
| `zone` | enum | available/field/bench/not_selected |
| `x` | numeric nullable | 0 à 1 |
| `y` | numeric nullable | 0 à 1 |
| `slot_label` | text nullable | ex. GK, DC, BU |
| `sort_order` | integer | banc et listes |

Les coordonnées normalisées rendent le placement indépendant de la taille d’écran.

### 2.7 Versions publiées

#### `public.match_composition_publications`

| Colonne | Type |
|---|---|
| `id` | uuid PK |
| `match_id` | uuid FK |
| `version` | integer |
| `formation_code` | text nullable |
| `snapshot` | jsonb |
| `published_at` | timestamptz |
| `published_by` | uuid |
| `publication_kind` | enum initial/update |

Un snapshot immuable est écrit à chaque publication. Le brouillon courant reste normalisé dans les tables de composition.

### 2.8 Notifications et tâches

#### `public.sport_notification_jobs`

| Colonne | Type | Règle |
|---|---|---|
| `id` | uuid PK | |
| `match_id` | uuid FK | |
| `recipient_profile_id` | uuid nullable | nul pour une expansion serveur |
| `kind` | enum | availability_open/reminder_j3/reminder_j1/manual_reminder/composition_published/composition_updated/availability_changed_after_publish/not_selected/vote_opened/match_changed |
| `due_at` | timestamptz | |
| `status` | enum pending/claimed/sent/skipped/cancelled/failed |
| `dedupe_key` | text unique | idempotence |
| `payload` | jsonb | contenu non sensible |
| `attempt_count` | integer | |
| `last_error` | text nullable | |
| `created_at` | timestamptz | |
| `processed_at` | timestamptz nullable | |

Le cron ne planifie pas une entrée `pg_cron` par notification. Un seul job périodique revendique atomiquement les lignes dues avec `FOR UPDATE SKIP LOCKED`.

### 2.9 Scrutin homme du match

#### `public.match_motm_ballots`

| Colonne | Type |
|---|---|
| `id` | uuid PK |
| `match_id` | uuid unique FK |
| `status` | enum draft/open/closed/cancelled |
| `opens_at` | timestamptz nullable |
| `closes_at` | timestamptz nullable |
| `closed_at` | timestamptz nullable |
| `opened_by` | uuid nullable |
| `closed_by` | uuid nullable |
| `version` | integer |

#### `public.match_motm_votes`

| Colonne | Type | Règle |
|---|---|---|
| `id` | uuid PK | |
| `ballot_id` | uuid FK | |
| `voter_participant_id` | uuid FK | présent permanent avec compte |
| `candidate_participant_id` | uuid FK | autre participant présent |
| `created_at` | timestamptz | serveur |
| `invalidated_at` | timestamptz nullable | admin uniquement |
| `invalidated_by` | uuid nullable | |
| `invalidation_reason` | text nullable | obligatoire si invalidé |

Contraintes :

- unicité `(ballot_id, voter_participant_id)` ;
- candidat différent du votant ;
- votant et candidat rattachés au même match ;
- présence finale `present` pour les deux ;
- votant permanent avec `profile_id` égal à `auth.uid()` ;
- scrutin ouvert et non expiré ;
- le vote ne peut jamais être mis à jour par le joueur.

#### `public.match_motm_results`

| Colonne | Type |
|---|---|
| `ballot_id` | uuid FK |
| `participant_id` | uuid FK |
| `vote_count` | integer |
| `is_winner` | boolean |
| `computed_at` | timestamptz |

Les résultats sont matérialisés à la clôture dans la même transaction. Les gagnants permanents sont synchronisés dans `match_man_of_match` afin de préserver les statistiques et badges existants. Les gagnants invités restent dans `match_motm_results` et leurs statistiques de match.

### 2.10 Audit administratif

#### `public.sport_admin_audit_log`

| Colonne | Type |
|---|---|
| `id` | bigint identity PK |
| `match_id` | uuid nullable |
| `action` | text |
| `actor_profile_id` | uuid |
| `reason` | text nullable |
| `metadata` | jsonb |
| `created_at` | timestamptz |

Actions minimales : toggle flag, override availability, publish/update composition, exceptional 15th call-up, confirm attendance, open/close/cancel/reopen ballot, invalidate vote.

## 3. Statuts et transitions

### 3.1 Disponibilité

- `no_response -> available`
- `no_response -> absent`
- `available <-> absent` jusqu’au coup d’envoi
- modification par le staff autorisée avec audit
- aucune modification après le coup d’envoi, sauf procédure administrative explicitement journalisée si un besoin futur est validé

Après publication, tout changement d’un joueur convoqué génère une alerte staff importante, mais la transition reste autorisée.

### 3.2 Décision du coach

- `undecided -> starter`
- `undecided -> substitute`
- `undecided -> not_selected`
- `starter <-> substitute`
- `starter/substitute -> not_selected`
- `not_selected -> starter/substitute` tant que la composition n’est pas clôturée

Le serveur avertit au 15e convoqué, puis exige un paramètre explicite `allow_squad_size_exception = true` pour continuer. L’exception est inscrite dans l’audit du match.

### 3.3 Composition

- `none -> draft`
- `draft -> published`
- `published -> updated` lors d’une republication
- `updated -> updated` pour les republications suivantes
- `published/updated -> closed` après le match

Une publication ne peut contenir plus de 11 titulaires. Moins de 11 est permis. L’absence de gardien produit un avertissement serveur dans la réponse, pas une erreur bloquante.

### 3.4 Présence finale

- `pending -> present`
- `pending -> actual_absent`
- corrections staff autorisées tant que la finalisation n’est pas verrouillée ;
- après finalisation, corrections via RPC dédiée avec audit et recalcul atomique des statistiques/badges concernés.

### 3.5 Scrutin

- `draft -> open`
- `open -> closed`
- `open -> cancelled`
- `closed -> open` uniquement par réouverture administrative journalisée ; une nouvelle version de scrutin est créée ou la version est incrémentée ;
- `cancelled -> open` uniquement avec justification.

Lors d’une réouverture, le comportement recommandé est de conserver les votes valides existants et d’indiquer clairement la nouvelle échéance. Une option de remise à zéro ne doit exister que comme action distincte, justifiée et auditée.

## 4. Permissions et RLS

### 4.1 Principes

- RLS activée sur chaque table `public` ;
- aucun droit métier fondé sur `user_metadata` ;
- droits staff déterminés par une fonction privée basée sur les données serveur ;
- toutes les écritures sensibles passent par des RPC atomiques ;
- aucun accès direct d’écriture aux tables de composition, présence, vote, notification ou audit ;
- fonctions `SECURITY DEFINER` placées dans un schéma privé lorsque possible, `search_path = ''`, contrôles `auth.uid()` internes, `REVOKE EXECUTE FROM PUBLIC`, grants nominatifs ;
- vues exposées créées avec `security_invoker = true`.

### 4.2 Lecture joueur

Un joueur authentifié peut lire :

- le flag global actif/inactif ;
- sa propre réponse et son historique utile ;
- la composition uniquement si elle est publiée ;
- les catégories publiques titulaire, remplaçant et non convoqué ;
- l’état du scrutin et sa propre capacité à voter ;
- les résultats uniquement après clôture.

Il ne peut pas lire :

- les commentaires privés d’absence d’un autre joueur ;
- les brouillons ;
- l’identité des votants ;
- les résultats provisoires ;
- les logs de notification ou d’audit.

### 4.3 Écriture joueur

RPC proposées :

- `set_my_match_availability(match_id, status, private_comment)` ;
- `cast_my_motm_vote(ballot_id, candidate_participant_id)`.

Chaque RPC vérifie le feature flag en premier, puis l’identité, l’éligibilité, la fenêtre temporelle et l’état du match.

### 4.4 Administration

RPC proposées :

- `admin_set_sports_management_enabled(enabled, reason)` ;
- `admin_override_availability(...)` ;
- `admin_send_availability_reminder(...)` ;
- `admin_save_composition_draft(...)` ;
- `admin_publish_composition(...)` ;
- `admin_add_or_reuse_guest(...)` ;
- `admin_archive_guest(...)` ;
- `admin_confirm_match_presence(...)` ;
- `admin_open_motm_ballot(...)` ;
- `admin_close_motm_ballot(...)` ;
- `admin_cancel_motm_ballot(...)` ;
- `admin_reopen_motm_ballot(...)` ;
- `admin_invalidate_motm_vote(...)`.

### 4.5 Feature flag comme barrière serveur

Chaque RPC du module appelle une fonction privée du type :

```sql
private.require_sports_management_enabled();
```

Le simple masquage Flutter n’est jamais considéré comme une protection.

## 5. Notifications

### 5.1 Planification

Pour chaque match à venir :

- ouverture : `kickoff_at - 144 hours` ;
- rappel J−3 : `kickoff_at - 72 hours` ;
- rappel J−1 : `kickoff_at - 24 hours`.

Si le match est créé à moins de 144 heures :

- le workflow est ouvert dans la transaction de création/synchronisation ;
- les emplois de notification initiale sont dus immédiatement ;
- J−3 et J−1 ne sont créés que s’ils sont encore dans le futur, sinon ils sont marqués `skipped`.

### 5.2 Ciblage

Population initiale :

- `season_players.is_active = true` ;
- même saison que le match ;
- `profile_id is not null` ;
- compte actif ;
- gardiens inclus ;
- staff non joueur exclu naturellement car sans ligne `season_players` liée.

Les rappels J−3/J−1 ciblent uniquement `availability_status = no_response` au moment de l’envoi, pas au moment de la planification.

### 5.3 Modification ou annulation du match

Un changement de `kickoff_at` :

- conserve les réponses ;
- recalcule `availability_opens_at` ;
- annule les jobs pending de l’ancien horaire ;
- recrée les jobs futurs avec de nouvelles clés d’idempotence ;
- peut générer une notification `match_changed`.

Un match annulé, archivé ou supprimé :

- annule tous les jobs pending du module ;
- empêche toute nouvelle revendication ;
- ne supprime aucune réponse ou composition historique.

### 5.4 Désactivation globale

L’action atomique de désactivation :

1. met le flag à false ;
2. passe les jobs pending/claimed non envoyés à `cancelled` lorsque c’est sûr ;
3. inscrit l’action dans l’audit ;
4. laisse les données métier intactes.

Le worker et l’Edge Function vérifient également le flag juste avant l’envoi. Une notification déjà revendiquée mais pas encore envoyée est donc ignorée.

### 5.5 Pipeline

Le pipeline recommandé conserve le cron existant mais généralise le modèle :

- `pg_cron` appelle toutes les minutes une fonction de traitement ;
- la fonction revendique un lot avec `FOR UPDATE SKIP LOCKED` ;
- elle filtre à nouveau les destinataires ;
- elle invoque l’Edge Function Web Push ;
- l’Edge Function journalise chaque livraison et traite les abonnements expirés ;
- les clés de déduplication empêchent les doubles envois.

## 6. Fonctionnement du feature flag

### 6.1 Lecture Flutter

Un provider Riverpod charge `get_public_feature_flags()` au démarrage et écoute les changements. L’état doit être rafraîchi :

- après authentification ;
- au retour au premier plan ;
- après changement par un administrateur ;
- lors d’une erreur d’autorisation serveur indiquant que le flag a changé.

Le cache local est uniquement visuel. En cas d’échec de lecture, la valeur sûre est `false` pour les fonctions du module.

### 6.2 Routes

Routes proposées :

- `/matches/:matchId/availability`
- `/matches/:matchId/lineup`
- `/matches/:matchId/vote`
- `/admin/matches/:matchId/sport-management`

Le redirecteur `go_router` vérifie :

- utilisateur authentifié ;
- flag actif ;
- rôle staff pour les routes admin ;
- statut publié pour la composition joueur.

Même si la route est atteinte, les données restent protégées par RLS/RPC.

### 6.3 Réactivation

La réactivation ne ressuscite pas automatiquement les notifications annulées. Une routine de synchronisation :

- traite uniquement les matchs futurs ;
- ouvre immédiatement ceux déjà dans la fenêtre ;
- recrée seulement les jobs encore pertinents ;
- conserve tous les anciens workflows.

## 7. Écrans joueur

### 7.1 Carte du prochain match

Quand le flag est actif et les disponibilités ouvertes :

- statut actuel ;
- boutons Disponible et Absent ;
- échéance ;
- confirmation après réponse ;
- motif facultatif pour Absent.

Quand le flag est désactivé, aucun espace vide ni libellé du module n’est affiché.

### 7.2 Page disponibilité

- adversaire, date, heure et lieu ;
- état personnel ;
- date de dernière modification ;
- possibilité de changer jusqu’au coup d’envoi ;
- message renforcé si la composition est déjà publiée.

### 7.3 Composition publiée

- terrain responsive ;
- titulaires ;
- banc ;
- non-convoqués ;
- invités marqués `(Invité)` ;
- date/version de publication ;
- aucun commentaire privé ou métadonnée d’administration.

### 7.4 Vote

- compteur de temps restant ;
- liste des candidats présents hors soi-même ;
- confirmation irréversible ;
- état « vote enregistré » ;
- aucun résultat provisoire ;
- résultats et éventuels co-gagnants uniquement après clôture.

## 8. Écrans administrateur

### 8.1 Paramètre global

- interrupteur Activé/Désactivé ;
- avertissement avant désactivation ;
- motif facultatif recommandé ;
- rappel que les données sont conservées ;
- état de la dernière modification.

### 8.2 Tableau disponibilités

- compteurs Disponible / Absent / Sans réponse ;
- listes filtrables ;
- dernière réponse ;
- indicateur de changement après publication ;
- modification manuelle ;
- relance des sans réponse par défaut ;
- option explicite pour une autre catégorie.

### 8.3 Convocation et composition

Quatre zones minimales :

1. disponibles/non décidés ;
2. terrain ;
3. banc ;
4. non convoqués.

Actions :

- choisir une formation ;
- déplacer un joueur ;
- ajouter/réutiliser un invité ;
- sauvegarder le brouillon ;
- publier/republier ;
- autoriser exceptionnellement le 15e convoqué.

### 8.4 Présences finales

- préremplissage des titulaires et remplaçants ;
- cases modifiables ;
- ajout de dernière minute ;
- correction des invités ;
- validation atomique avec score et statistiques ;
- ouverture du vote après validation.

### 8.5 Administration du vote

- nombre d’électeurs éligibles ;
- nombre de votes reçus, sans exposer publiquement les identités ;
- échéance ;
- fermeture anticipée ;
- annulation/réouverture ;
- invalidation motivée d’un vote ;
- historique complet des actions.

## 9. Terrain en glisser-déposer

### 9.1 Modèle UI

Flutter :

- `LongPressDraggable` ou contrôleur équivalent sur mobile ;
- `DragTarget` pour terrain, banc et non-convoqués ;
- coordonnées stockées entre 0 et 1 ;
- conversion locale vers les pixels disponibles ;
- grille magnétique facultative ;
- sauvegarde optimiste du brouillon avec retour d’erreur serveur.

### 9.2 Accessibilité et alternative au drag

Chaque joueur propose aussi une action accessible :

- Placer titulaire ;
- Mettre sur le banc ;
- Ne pas convoquer ;
- Choisir un poste.

Le drag-and-drop n’est donc pas le seul moyen de composer l’équipe.

### 9.3 Validations

Serveur :

- 11 titulaires maximum ;
- pas de doublon ;
- participant du même match ;
- cohérence zone/décision ;
- limite habituelle de 14 avec autorisation d’exception explicite ;
- publication autorisée avec moins de 11 ;
- gardien absent = avertissement.

## 10. Joueurs invités

### 10.1 Création et réutilisation

- recherche dans `guest_players` actifs ;
- création avec prénom obligatoire ;
- ajout au match via `match_sport_participants` ;
- affichage `Prénom (Invité)` calculé côté présentation ou vue.

### 10.2 Archivage

- retrait de la liste réutilisable par archivage ;
- aucune suppression de références historiques ;
- restauration possible par le staff si nécessaire.

### 10.3 Capacités

Un invité peut être :

- titulaire ;
- remplaçant ;
- présent ;
- buteur ;
- candidat et gagnant homme du match.

Il ne peut pas :

- répondre à une disponibilité ;
- recevoir une push sans compte ;
- voter.

## 11. Vote homme du match

### 11.1 Ouverture

Le vote est ouvert après validation atomique :

- du score ;
- des présences finales ;
- des participants réels.

S’il y a moins de deux candidats présents, le scrutin est clôturé sans vote et sans gagnant.

### 11.2 Vote atomique

`cast_my_motm_vote` exécute dans une transaction :

1. verrouillage de la ligne du scrutin ;
2. vérification du flag ;
3. vérification de la fenêtre ;
4. résolution du participant du votant depuis `auth.uid()` ;
5. vérification de sa présence ;
6. vérification du candidat ;
7. interdiction du vote pour soi ;
8. insertion avec contrainte unique.

Aucun `UPDATE` ni `DELETE` joueur n’est accordé.

### 11.3 Clôture

La clôture :

- exclut les votes invalidés ;
- compte un point par vote ;
- calcule le maximum ;
- produit zéro gagnant si zéro vote ;
- produit tous les ex æquo au maximum ;
- synchronise les gagnants permanents dans `match_man_of_match` ;
- déclenche le recalcul des badges/statistiques dans la même transaction ou via une routine idempotente immédiatement consécutive ;
- rend les résultats lisibles.

### 11.4 Confidentialité

- les joueurs ne peuvent jamais sélectionner les lignes de votes ;
- un RPC joueur renvoie uniquement `has_voted` ;
- un RPC public après clôture renvoie les totaux par candidat ;
- le staff utilise une vue/RPC dédiée et chaque consultation sensible peut être auditée si nécessaire.

## 12. Cas limites

1. Match créé à moins de J−6 : ouverture et notification immédiates.
2. Match déplacé après réponses : réponses conservées, jobs recalculés.
3. Match déplacé dans le passé : aucune nouvelle notification, disponibilité fermée.
4. Match annulé : jobs annulés, données conservées.
5. Flag désactivé pendant un envoi : seconde vérification avant livraison, envoi ignoré.
6. Flag désactivé pendant un scrutin : vote bloqué ; scrutin conservé mais invisible. À la réactivation, décision admin requise pour reprendre ou annuler.
7. Joueur devient inactif après réponse : conservé dans l’historique ; staff décide s’il reste convoqué.
8. Compte dissocié d’un joueur : aucune nouvelle push ni vote, données historiques conservées.
9. Réponse après publication : autorisée, alerte staff idempotente.
10. 15e convoqué : erreur fonctionnelle exigeant confirmation explicite.
11. Plus de 11 titulaires : refus serveur.
12. Aucun gardien : avertissement, publication permise.
13. Moins de 11 joueurs : publication permise.
14. Disponible non convoqué : notification dédiée et aucune pénalité d’assiduité.
15. Convoqué absent réel : non présent dans `match_attendance`.
16. Joueur venu sans convocation : ajout possible à la présence finale.
17. Invité archivé réutilisé dans un ancien match : historique intact.
18. Vote simultané sur deux appareils : contrainte unique, un seul succès.
19. Vote exactement à l’échéance : serveur compare `now()` et `closes_at` ; l’heure client n’est pas utilisée.
20. Auto-vote indirect via mauvais identifiant : vérification d’identité du participant côté serveur.
21. Candidat retiré après ouverture : correction de présence invalide ou annule les votes concernés avec audit, puis recalcul à la clôture.
22. Zéro vote : aucun homme du match.
23. Égalité : tous les premiers gagnent.
24. Un seul présent : aucun vote possible.
25. Réouverture : version et nouvelle échéance visibles, action auditée.
26. Double exécution du cron : revendication atomique et `dedupe_key` empêchent les doublons.
27. Passage heure d’été/hiver : calcul depuis `kickoff_at` en instant absolu ; affichage en `Europe/Paris`.

## 13. Tests automatisés nécessaires

### 13.1 Base de données

- feature flag lu par tous les authentifiés, modifiable seulement par admin ;
- toutes les RPC du module refusent lorsque le flag est false ;
- joueur ne modifie que sa disponibilité ;
- staff peut faire un override auditée ;
- staff non joueur n’est pas ciblé ;
- gardien ciblé normalement ;
- ouverture à exactement 144 heures ;
- création tardive ouvre immédiatement ;
- recalcul après changement de date ;
- rappel uniquement sans réponse ;
- limite 11 titulaires ;
- exception 15e explicite et limitée au match ;
- non convoqué exclu des présences et du vote ;
- présence finale seule alimente `match_attendance` ;
- vote unique sous concurrence ;
- auto-vote refusé ;
- absent ne vote pas ;
- candidat absent refusé ;
- vote expiré refusé ;
- résultat caché avant clôture ;
- zéro/un/plusieurs gagnants ;
- invalidation exige une justification ;
- audit immuable ;
- aucune suppression lors de la désactivation.

### 13.2 Fuseau horaire

Cas explicites Europe/Paris :

- match avant/après changement d’heure de mars ;
- match avant/après changement d’heure d’octobre ;
- ouverture six jours plus tôt au même instant relatif ;
- affichage correct en heure locale ;
- aucune dépendance au fuseau du téléphone pour les règles serveur.

### 13.3 Edge Function et notifications

- signature/authentification interne ;
- flag false avant dispatch ;
- destinataire sans abonnement ;
- abonnement expiré 404/410 ;
- idempotence ;
- relance sans réponse uniquement ;
- job annulé après déplacement/annulation ;
- retry borné et journalisé.

### 13.4 Flutter

- provider de flag false par défaut en erreur ;
- routes redirigées lorsque désactivé ;
- composants absents, pas seulement grisés ;
- réponse disponible/absent ;
- changement après publication ;
- drag-and-drop et alternative accessible ;
- limite de 11 ;
- modal du 15e ;
- rendu terrain responsive ;
- invité marqué ;
- vote irréversible ;
- résultats cachés avant clôture ;
- parcours historique inchangé flag false.

### 13.5 Régression

- pronostics de match ;
- pronostics joueurs/saison ;
- classements ;
- badges ;
- multiplicateur ×2 ;
- création/modification de match ;
- finalisation historique ;
- statistiques existantes.

## 14. Plan d’implémentation en petites PR

Aucune PR n’est fusionnée automatiquement.

### PR 0 — Architecture

- ce document ;
- aucune migration ;
- aucune modification runtime.

### PR 1 — Feature flag et audit de base

- table privée ;
- RPC lecture et toggle ;
- audit ;
- tests RLS ;
- flag initial `false`.

### PR 2 — Workflow et participants

- enums/tables ;
- synchronisation des joueurs de saison ;
- calcul J−6 ;
- tests fuseau et création tardive.

### PR 3 — Disponibilités serveur

- RPC joueur/staff ;
- historique ;
- vues de lecture ;
- RLS et tests de concurrence.

### PR 4 — Notifications/outbox

- jobs ;
- worker cron ;
- extension du pipeline push ;
- annulation/idempotence ;
- aucun déploiement production avant validation sur branche Supabase.

### PR 5 — Interfaces disponibilités

- provider flag ;
- écran joueur ;
- tableau admin ;
- relance manuelle ;
- guards routes.

### PR 6 — Catalogue invités

- tables/RPC ;
- archivage non destructif ;
- sélecteur Flutter ;
- tests historiques.

### PR 7 — Composition serveur

- brouillon ;
- entrées ;
- validations 11/14/15e ;
- publications et snapshots ;
- notifications de publication.

### PR 8 — Composition Flutter

- quatre zones ;
- formations ;
- drag-and-drop ;
- placement libre ;
- alternative accessible ;
- lecture publique publiée.

### PR 9 — Présences et finalisation

- préremplissage ;
- nouveau RPC activé ;
- conservation du RPC historique ;
- invités et stats de match ;
- tests badges/statistiques.

### PR 10 — Scrutin serveur

- ballots/votes/results ;
- RPC de vote ;
- clôture et ex æquo ;
- confidentialité et audit.

### PR 11 — Interfaces de vote

- écran joueur ;
- administration du scrutin ;
- notifications ;
- résultats clôturés.

### PR 12 — Durcissement et préparation au lancement

- tests E2E ;
- advisors sécurité/performance ;
- documentation d’exploitation ;
- métriques ;
- test complet flag off/on/off ;
- plan de déploiement séparé soumis à validation.

## 15. Plan de retour arrière

### 15.1 Retour arrière fonctionnel immédiat

1. désactiver `sports_management` via RPC admin ;
2. annuler les jobs pending ;
3. vérifier que les routes et composants disparaissent ;
4. utiliser le parcours historique de finalisation ;
5. conserver toutes les tables et données.

Cette action est le rollback principal et doit fonctionner sans déploiement Flutter supplémentaire.

### 15.2 Retour arrière applicatif

- rétablir la version Flutter précédente ;
- le serveur continue de refuser les écritures si le flag est false ;
- les nouvelles tables restent sans effet sur l’application historique.

### 15.3 Retour arrière des migrations

Les migrations initiales sont additives. Il n’est pas recommandé de supprimer les tables en urgence. En cas de défaut :

- désactiver le flag ;
- révoquer les grants des nouvelles RPC si nécessaire ;
- désactiver le cron du module ;
- corriger par une migration suivante ;
- ne jamais supprimer les données historiques.

### 15.4 Critères avant activation production

- branche Supabase de développement validée ;
- migrations GitHub alignées avec le schéma distant ;
- advisors sécurité et performance sans alerte bloquante ;
- tests SQL, Flutter, Edge Function et E2E réussis ;
- vérification du parcours historique flag false ;
- vérification de l’arrêt des notifications ;
- revue manuelle des politiques RLS ;
- PR finale encore en brouillon jusqu’à validation humaine explicite.

## 16. Décision de lancement recommandée

Le développement peut commencer, mais le déploiement production ne doit pas commencer à ce stade.

Ordre recommandé :

1. valider cette architecture dans la PR brouillon ;
2. créer une branche Supabase de développement après confirmation de son coût ;
3. réaliser PR 1 avec le flag à `false` ;
4. tester le mode désactivé avant d’ajouter les fonctions métier ;
5. ne fusionner et ne déployer aucune PR sans validation explicite.
