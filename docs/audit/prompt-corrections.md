Tu travailles sur le dépôt `samihchaa-wq/AS-Grinta` : l'application web Flutter du club de football amateur AS La Grinta, avec Supabase pour la base de données et les fonctions serveur, et GitHub Pages pour la publication.

# Contexte

Un audit complet a été réalisé le 27 septembre 2026. Le dossier se trouve sur la branche `claude/site-complete-audit-bp8gk3`, dans `docs/audit/2026-09-27-audit-complet.md` ; lis-le en entier avant de commencer, en particulier son annexe technique, qui donne les fichiers et les lignes concernés.

```
git fetch origin claude/site-complete-audit-bp8gk3
git show origin/claude/site-complete-audit-bp8gk3:docs/audit/2026-09-27-audit-complet.md
```

La personne qui pilote le projet a validé la liste de changements ci-dessous, point par point. Tu dois réaliser **tout ce qui est listé ici, et rien d'autre**.

# Règles impératives

- Lis et respecte `CLAUDE.md` et `AGENTS.md` avant toute modification.
- Ne modifie, ne renomme et ne supprime jamais une migration déjà présente dans `supabase/migrations/`, ni le dossier `supabase/migrations_legacy_production/`.
- Tout changement de base passe par une **nouvelle** migration, dont l'horodatage est postérieur à `20260923230000` et à la dernière migration de `main`.
- N'écris jamais directement en production : pas d'`execute_sql` en écriture, pas d'`apply_migration` par un connecteur.
- La lecture seule de la production est autorisée pour vérifier, sans lire de données personnelles.
- Ne mets jamais la clé `service_role` dans l'application Flutter.
- En cas de doute sur une suppression, ne supprime pas et signale-le.
- Travaille en **une pull request par lot** (lots 1 à 7 ci-dessous), en suivant le modèle `.github/pull_request_template.md`.
- Avant chaque envoi, fais passer tous les contrôles : `dart format`, `flutter analyze` (0 avertissement) et `flutter test`.
- Pour les lots qui touchent la base ou les fonctions serveur, fais aussi passer : les tests pgTAP de `supabase/tests/database` sur une pile Supabase locale (comme `.github/workflows/supabase_business_tests.yml`), les tests Deno de `send-push` et `python3 supabase/tests/edge/verify_edge_security_contract.py`.
- Plusieurs tests lisent le code source comme du texte (par exemple `test/pwa_contract_test.dart`, qui lit `web/sw.js`) ; mets-les à jour quand tu modifies les fichiers qu'ils lisent.
- Communique avec la personne qui pilote le projet comme le demande `CLAUDE.md`, en français simple :
  - d'abord le problème et son effet pour les joueurs ;
  - pas de jargon ;
  - dire clairement ce qui a été vérifié et ce qui ne l'a pas été ;
  - séparer ce que tu as fait de ce qu'elle doit faire.

# Lot 1 — Base de données et sauvegardes (priorité maximale)

## 1.1 Recopier dans le code les 8 fonctions d'administration de la production

En production, 8 fonctions sont verrouillées dès l'ouverture du Live (15 minutes avant le coup d'envoi). Ce verrou a été appliqué hors migration : le code contient encore les anciennes versions, sans verrou.

Crée une migration qui redéfinit ces 8 fonctions **exactement** comme en production. La production fait foi : si tu y as accès en lecture, vérifie-le avec `pg_get_functiondef`. Sinon, utilise l'annexe A, relevée en production le 27 septembre 2026.

- Garde les mêmes signatures, types de retour et valeurs par défaut.
- Chaque fonction est `language plpgsql`, `security definer` et `set search_path to ''`.
- Droits : `revoke all ... from public, anon` puis `grant execute ... to authenticated, service_role`.

Ajoute un test pgTAP qui vérifie, pour chacune des 8 fonctions :
- qu'un non-administrateur est refusé ;
- qu'un administrateur est refusé après l'ouverture du Live (T-15) ;
- qu'un administrateur est accepté avant.

Si des tests existants échouent parce qu'ils supposaient l'absence de verrou, c'est la production qui fait foi : adapte ces tests et explique pourquoi dans la pull request.

## 1.2 Contrôler le contenu des fonctions, pas seulement leur liste

Le garde-fou actuel (`migration_inventory.yml`) compare seulement la liste des versions de migration entre le code et la production. Ajoute un contrôle automatique, planifié et en lecture seule :
- il reconstruit la base depuis le code ;
- il compare, fonction par fonction dans les schémas `public` et `private`, le corps (commentaires et espaces ignorés), `SECURITY DEFINER`, la configuration (`search_path`) et les droits avec la production ;
- il échoue en cas de différence réelle.

Les identifiants de production sont déjà dans les secrets du dépôt (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`) ; ne les expose jamais dans les journaux.

## 1.3 Réparer le test de restauration des sauvegardes

`.github/workflows/backup_restore_drill.yml` échoue depuis le 20 septembre, à l'étape « Restore database backup », avec l'erreur `relation "auth.mfa_recovery_code_sets" does not exist`. Le schéma `auth` de la pile locale (CLI Supabase 2.111.0) est plus ancien que celui de la production.

- Passe ce workflow à une version récente de la CLI Supabase dont le schéma `auth` contient cette table (vérifie-le en local).
- Documente dans `docs/production-operations.md` la version de la CLI à utiliser pour une restauration.
- Le workflow a un déclencheur manuel : demande à la personne qui pilote le projet de le lancer après fusion, et ne déclare le point réglé qu'une fois le run au vert.

## 1.4 Vider automatiquement le journal des tâches planifiées

`cron.job_run_details` n'est jamais vidé. En production, il pèse 70 Mo sur 99 Mo, avec 370 641 lignes et environ 7 600 nouvelles lignes par jour. La limite de l'offre gratuite est de 500 Mo.

Ajoute par migration une tâche `pg_cron` quotidienne, idempotente (déprogrammer puis reprogrammer si elle existe déjà), qui exécute `delete from cron.job_run_details where end_time < now() - interval '7 days'`. Suis le modèle de la migration existante `20260827234000_schedule_client_incident_log_purge.sql`.

## 1.5 Aligner les droits techniques sur la production

La base reconstruite depuis le code accorde `TRUNCATE`, `TRIGGER` et `REFERENCES` à `anon` et `authenticated` sur des tables de `public`, alors que la production ne les accorde pas. Ces différences sont les seules constatées sur les droits.

Ajoute une migration qui retire ces trois droits à `anon` et `authenticated` sur toutes les tables de `public`, et qui ajuste les privilèges par défaut pour les futures tables. Elle ne doit rien changer d'autre. Vérifie qu'elle est sans effet en production, où elle ne fait que confirmer l'existant.

# Lot 2 — Liens et notifications

## 2.1 Faire comprendre à l'application les deux formes d'adresse

`lib/app/router/initial_app_location_web.dart` ne lit que la partie après `#`. Les adresses en forme de chemin (`/AS-Grinta/matches/...`) démarrent donc sur la page d'accueil.

- Quand la partie `#` est vide, lis le chemin situé sous la base `/AS-Grinta/`, avec sa requête, comme route initiale.
- Réécris ensuite l'adresse du navigateur sous la forme `#/...` (`history.replaceState`).
- Remplace le lien d'inscription copié par l'administration (`admin_page.dart`, `_registerLink`) par `https://samihchaa-wq.github.io/AS-Grinta/#/auth/register`.

## 2.2 Faire ouvrir la bonne page par les notifications

Les notifications « vote pour l'homme du match » (`matches/<id>/vote`), « effectif / composition » (`.../lineup?section=effectif`) et « nouveau compte à valider » (`admin/administration`) ouvrent aujourd'hui le calendrier.

Dans `web/sw.js`, au clic sur une notification, convertis toute adresse relative de l'application en adresse `#/...`, puis ouvre ou mets au premier plan la fenêtre de l'application sur cette adresse. Grâce au point 2.1, les anciennes notifications déjà reçues fonctionneront aussi.

## 2.3 Attendre les réglages du club avant de rediriger

`lib/app/router/app_router.dart` (ligne 84) passe `sportsManagementEnabledProvider`, qui vaut `false` tant que les réglages chargent. `auth_redirect.dart` (lignes 88 à 95) renvoie alors `/matches/:id/lineup` vers `/prediction` et les autres pages sportives vers `/matches`, et la destination demandée est perdue. Reproduit 6 fois sur 6 : ouvrir ou rafraîchir la page Effectif d'un match mène aux pronos.

- Distingue « réglages en cours de chargement » de « gestion sportive désactivée ».
- Pendant le chargement, conserve la destination (par exemple via `/auth/loading?redirect=...`) et ne décide qu'une fois les réglages connus.
- Ajoute des tests du routeur pour ces cas.

# Lot 3 — Corrections de l'application

## 3.1 Rafraîchir les badges affichés à côté des prénoms

`statisticsBadgeEmblemsProvider` (utilisé par `NameWithBadges`) n'est jamais rafraîchi. Les trois invalidations existantes (`armoire_page.dart:32`, `badge_image_editor.dart:104`, `core/sync/shared_data_sync.dart:263`) visent `featuredBadgesProvider`, qui n'est jamais écouté.

Invalide `statisticsBadgeEmblemsProvider` à ces trois endroits. La suppression de l'ancien provider fait partie du lot 6.

## 3.2 Corriger la règle de mot de passe

Aujourd'hui, `[A-ZÀ-Ÿ]` et `[a-zà-ÿ]` font compter une lettre accentuée minuscule comme une majuscule : « aaaaaaaaaaé1 » est accepté. La règle se trouve dans `lib/core/security/password_policy.dart` et dans `supabase/functions/register-account/index.ts`.

Nouvelle règle, identique aux deux endroits :
- la majuscule exigée est une lettre A à Z non accentuée, la minuscule une lettre a à z, comme la règle de caractères de Supabase ;
- les lettres accentuées restent autorisées mais ne comptent pas ;
- les messages affichés sont adaptés (« Ajoute au moins une majuscule de A à Z »).

La fonction `register-account` n'est pas déployée par le workflow : ajoute une entrée `deploy_register_account` à `.github/workflows/deploy_sports_management.yml`, sur le modèle de `deploy_send_push`.

## 3.3 Messages d'erreur

- À l'inscription (`AuthRepository.registerAccount`) et pour les actions d'administration sur les comptes (`AdminRepository`, fonction `manage-user`), `functions_client` lève `FunctionsHttpException` avant le test du statut HTTP. Attrape cette exception, lis le champ `error` du corps JSON et affiche ce message quand il est en français ; sinon, garde le message générique.
- Remplace par un message simple les 5 messages techniques bruts affichés aux utilisateurs :
  - `internal_team_composition_view.dart`, lignes 325, 390 et 442 ;
  - `admin_page.dart`, ligne 67 ;
  - `match_live_pre_kickoff_page.dart`, ligne 123, où il faut aussi supprimer l'affichage de la trace de pile ;
  - utilise `humanizeError` et garde le détail dans les journaux via `AppLogger`.

## 3.4 Une action ratée ne doit plus masquer le calendrier

`MatchesController.cancelMatch`, `finishInternalMatch` et `createOpponent` écrivent `state.error`, ce qui remplace tout le calendrier par la carte « Matchs indisponibles ». Fais-leur renvoyer le message d'erreur, comme le fait déjà `deleteMatch`, et affiche-le dans un bandeau sur l'écran appelant.

## 3.5 Désinscrire l'appareil des notifications à la déconnexion

À la déconnexion, appelle la désinscription qui existe déjà dans `push_subscriptions_repository.dart` pour l'appareil courant. Fais-le au mieux : un échec ne doit jamais empêcher la déconnexion.

## 3.6 Confirmer la coupure générale des notifications

Dans `notifications_page.dart`, demande une confirmation avant d'activer « Désactiver toutes les notifications », qui coupe les envois pour tout le club.

## 3.7 Écran Effectif sur ordinateur (ajustement léger)

En largeur ordinateur (1 440 px), la colonne « Sans réponse » coupe les prénoms à 2 ou 3 lettres (« Th… » pour Thomas comme pour Théo), et son titre est lui-même coupé. Fais un ajustement léger pour que les prénoms restent lisibles, sans refondre l'écran : moins de colonnes ou une colonne plus large, par exemple.

## 3.8 Texte de l'entraîneur

Dans `players_registry_page.dart`, retire la mention « Hors effectif… » : depuis la migration `20260915093000_coach_is_a_regular_member`, l'entraîneur est un membre ordinaire.

# Lot 4 — Finitions

- Remplace « Envoyer un notif. » par « Envoyer une notif. » (`notifications_page.dart:309`).
- Remplace « Ouverture pronostique » par « Ouverture des pronos » (`notifications_page.dart:127`).
- Dans l'erreur de connexion, ne répète plus « Connexion impossible » dans le titre et dans le texte.
- Écris « Valider le compte rendu » en minuscules, comme les autres boutons.
- Masque les cartes « Effectif » et « Composition » d'un match à venir côté joueur tant que rien n'est publié.
- Trie la liste des utilisateurs (Administration > Utilisateurs) selon le nom affiché, surnom compris.
- Calcule les initiales des avatars à partir du nom affiché, pour qu'elles soient cohérentes partout (aujourd'hui « LB » pour « Le Mur »).
- Harmonise le compteur « Sans réponse » entre la vue administrateur (« 17 + coach ») et la vue joueur (« 18 »), en comptant l'entraîneur comme un membre ordinaire.
- Empêche les titres de la liste des matchs, côté administration, de se couper au milieu d'un nom d'équipe (espaces insécables dans les noms, par exemple).
- Fais disparaître le bandeau « Terminés » qui reste collé au-dessus de « À venir » quand on fait défiler le calendrier.
- Dans `supabase/functions/send-push/weather_refresh.ts`, demande d'abord la ville en France (paramètre `countryCode=FR` de l'API de géocodage Open-Meteo), puis sans filtre si rien n'est trouvé ; ajoute un test Deno.

# Lot 5 — Documentation, tests et contrôles

- Corrige `AGENTS.md` (ligne 24) : il n'existe plus que deux rôles, `pronostiqueur` et `admin`.
- Mets à jour `docs/business-security-matrix.md` et `.agents/memory/players-claim-flow.md`, qui parlent encore du rôle « modérateur » et de l'ancienne procédure de rattachement de compte.
- Dans `.github/workflows/full_schema_replay_diagnostic.yml` (ligne 43), remplace le nombre figé « 427 versions » par un nombre calculé ou une formulation sans chiffre.
- Ajoute des tests de widgets, avec de faux dépôts de données comme dans les tests existants, pour les écrans de statistiques, de profil et d'administration, qui n'en ont presque pas.
- Remplace peu à peu les 17 fichiers de tests qui lisent le code source comme du texte (`readAsString` sur des fichiers de `lib/`) par de vrais tests de comportement.
  - Commence par ceux qui touchent aux zones modifiées dans ce travail.
  - Ne supprime jamais une vérification sans la remplacer.
  - Le test `test/internal_match_atomic_update_contract_test.dart` ne vérifie que du code mort : il est supprimé au lot 6.
- Rends utile l'étape « Lint database functions » de `supabase_business_tests.yml` : elle doit échouer sur une vraie erreur.
  - Limite l'analyse aux schémas `public` et `private`.
  - Ignore explicitement, avec un commentaire, les faux positifs connus des fonctions qui créent des tables `pg_temp` à l'exécution : `private.create_postmatch_composition`, `finalize_match_sport_postgame`, `publish_match_effectif`, `resequence_sport_waitlist`, `save_match_composition`, `save_match_live_lineup`, `update_postmatch_composition` et `submit_match_sport_report`.

# Lot 6 — Nettoyage (sans effet sur l'application)

Avant chaque suppression, revérifie qu'il n'y a aucune référence : graphe des imports depuis `lib/main.dart`, puis recherche dans `lib/`, `test/`, `web/`, `tool/`, `.github/` et `supabase/`.

Code et tests à supprimer :
- 9 fichiers jamais chargés (784 lignes) :
  - `lib/core/calendar/ics_calendar_export.dart`, `ics_calendar_export_stub.dart` et `ics_calendar_export_web.dart` ;
  - `lib/core/widgets/match_scorers_card.dart` ;
  - `lib/features/admin/presentation/admin_sports_management_section.dart` ;
  - `lib/features/matches/data/match_finalization_repository.dart` (à ne pas confondre avec `sport_match_finalization_repository.dart`, qui est utilisé) ;
  - `lib/features/matches/domain/calendar_export.dart` ;
  - `lib/features/sports_management/domain/internal_team_simulation.dart` ;
  - `lib/features/sports_management/presentation/widgets/internal_team_pitch.dart`.
- Leurs tests : `test/match_scorers_card_test.dart`, `test/admin_sports_management_section_test.dart` et `test/calendar_export_test.dart`.
- `lib/features/predictions/presentation/pronos_hub_history_section.dart` (fichier entier, 410 lignes), sa directive `part` dans `pronos_hub_page.dart` et `_LoadingCard` dans `pronos_hub_components.dart`.
- Dans `matches_controller.dart`, les méthodes jamais appelées (lignes 210 à 441) : `createMatch`, `updateMatch`, `createInternalMatch`, `updateInternalMatch` et `_validOdds`.
- Dans `matches_repository.dart`, les méthodes jamais appelées : `createMatch`, `createInternalMatch`, `updateInternalMatch`, `updateMatch`, `fetchMatchOdds`, `fetchMatchPredictions` et `setMatchAddress`, ainsi que le test `test/internal_match_atomic_update_contract_test.dart`.
- Dans `featured_badges_repository.dart` : la classe `FeaturedBadge`, `fetchAll` et `featuredBadgesProvider`, après le point 3.1.
- Les restes du bonus ×2 : `_X2Badge` dans `match_details_page.dart`, le champ `usedX2` (toujours `false`) et la colonne vide de 30 px qu'il réserve dans les lignes de pronos.
- Le mode « aperçu » du bilan de saison, devenu inaccessible (environ 100 lignes) :
  - la branche `preview` de `season_wrapped_page.dart`, `season_wrapped_button.dart` et `wrapped_slides.dart` ;
  - `demoSeasonWrapped` : remplace son usage dans `test/season_wrapped_music_test.dart` par une donnée de test locale ;
  - le paramètre `apercu` du routeur ;
  - garde la règle de `auth_redirect.dart` qui bloque `apercu=1`, ou retire-la si plus rien ne produit ce paramètre.

Serveur :
- Supprime `supabase/functions/claim-account` et `supabase/functions/send-prediction-reminders`, leurs entrées dans `supabase/config.toml`, leurs mentions dans `supabase/tests/edge/verify_edge_security_contract.py` (lignes 50, 53 et 241), `docs/production-operations.md` et `docs/business-security-matrix.md`.
- Supprime `supabase/tests/critical_invariants.sql`, `season_scoring_nx3.sql` et `statistics_module_history.sql`, que rien ne lance.

Fichiers :
- Supprime le dossier `logo-pack/` : 4 copies exactes des icônes de `web/` et 3 images non utilisées.
- Supprime les images inutilisées `assets/images/mpg_logo.png`, `mpg_logo_bar.png`, `sporteasy_grinta_logo.png` et `sporteasy_grinta_icon.png`.
- Supprime le dossier `assets/images/module_backgrounds/` (2 fichiers `.b64` jamais affichés) et sa ligne dans `pubspec.yaml`.
- Supprime les 8 fichiers de déclenchement d'une ligne : `.github/pr171-main-trigger.txt`, `pr172-main-trigger.txt`, `pr172-main-trigger-2.txt`, `redeploy-pronos-tabs-20260713`, `reorder-head-to-head-trigger`, `style-season-median-trigger`, `.github/agent/format.trigger` et `format.trigger.2`.
- Supprime `web/deploy_marker_prono_joueurs.txt`, publié sur le site.
- Supprime la configuration Replit (`.replit`, `replit.nix`, `replit.md`) et ses mentions dans la documentation.
- Supprime le dossier `supabase/migrations_legacy_synthetic/` (408 fichiers, ancienne tentative de reconstruction), ainsi que l'étape « Validate reconstructed production inventory » de `.github/workflows/migration_inventory.yml`, qui ne dépend que de son fichier repère vide.

À garder absolument :
- `supabase/migrations_legacy_production/` ;
- toutes les migrations de `supabase/migrations/` ;
- `supabase/rollbacks/` et `supabase/diagnostics/` ;
- l'archive `tool/sporteasy/`.

# Lot 7 — Répondre « Présent » ou « Absent » depuis la notification

Ajoute deux boutons, « Présent » et « Absent », aux notifications d'ouverture et de relance des disponibilités (`availability_open`, `availability_j3`, `availability_j1`, `availability_manual`), pour qu'un joueur réponde sans ouvrir l'application.

Contraintes :
- **Affichage :** passe les boutons par `actions` dans `showNotification` de `web/sw.js`. Un appui hors bouton garde le comportement actuel : ouvrir la page du match, avec le lot 2.
- **iPhone :** Safari n'affiche pas les boutons des notifications web. Sur iPhone, la notification continue simplement d'ouvrir la page : dis-le clairement à la personne qui pilote le projet.
- **Session :** le service worker n'a pas la session de l'utilisateur. Crée un jeton de réponse propre à chaque joueur et à chaque match :
  - aléatoire, d'au moins 32 octets ;
  - stocké uniquement sous forme d'empreinte SHA-256 dans une table du schéma `private` ;
  - valable jusqu'à la fermeture des réponses de ce match ;
  - inclus dans la charge utile de la notification envoyée à ce seul joueur.
  Aujourd'hui, `send-push` envoie la même charge utile à tous : adapte le dispatch pour produire une charge par destinataire.
- **Enregistrement :** crée une fonction serveur `respond-availability` (POST, `verify_jwt = false` dans `supabase/config.toml`). Elle :
  - vérifie le jeton en comparaison à temps constant ;
  - limite la taille des requêtes et le débit ;
  - enregistre la réponse en réutilisant **la même logique serveur que l'application** (fenêtre ouverte, indisponibilités, liste d'attente, notifications aux administrateurs) : jamais d'écriture directe qui contournerait ces règles ;
  - n'expose aucune donnée.
- **Retour au joueur :** après un appui, le service worker affiche une courte notification (« Réponse enregistrée : Présent »). En cas d'échec (jeton expiré, réponses fermées), il ouvre la page du match.
- **Sécurité :** mets à jour `verify_edge_security_contract.py` pour la nouvelle fonction.
- **Tests :**
  - pgTAP pour la création, la validation et l'expiration des jetons, et pour le respect des règles ;
  - Deno pour la fonction ;
  - mise à jour des tests qui lisent `web/sw.js`.
- **Déploiement :** ajoute les entrées `deploy_respond_availability` et, si nécessaire, `deploy_send_push` à `.github/workflows/deploy_sports_management.yml`.

# À ne pas faire (refusé par la personne qui pilote le projet)

- Ajouter un texte « Enregistrement… » ou un indicateur de chargement sur les boutons : les indicateurs restent invisibles.
- Ajouter une légende ou des intitulés complets aux colonnes de statistiques.
- Afficher les cotes des pronos en points.
- Afficher les buteurs et l'homme du match sous le score d'un match terminé.
- Plafonner les cotes.
- Modifier le découpage des lignes de l'agenda synchronisé.
- Rendre facultative la raison des indisponibilités.
- Changer la numérotation des journées.
- Supprimer l'archive SportEasy.

# Ce que tu dois rendre

Pour chaque lot :
- une pull request dont le résumé est écrit pour une personne non développeuse, comme le demande `CLAUDE.md` : ce qui change pour les joueurs et les administrateurs, ce qui a été vérifié et comment, ce qui n'a pas pu l'être et pourquoi ;
- en fin de résumé, la liste des actions que seule la personne qui pilote le projet peut faire.

Ne déclare jamais un point réglé sans l'avoir vérifié.

Actions que seule la personne qui pilote le projet peut faire (à lui rappeler au bon moment) :
1. Relire et fusionner les pull requests.
2. Après fusion des lots 1 et 7, lancer « Deploy Supabase production » avec `apply_migrations` après un premier passage à blanc, puis cocher le déploiement des fonctions concernées (`send-push`, `register-account`, `respond-availability`).
3. Lancer à la main « Production backup restore drill » après le lot 1, et vérifier qu'il passe au vert.
4. Supprimer dans le tableau de bord Supabase les fonctions `claim-account` et `send-prediction-reminders`, encore déployées.
5. Nettoyer l'onglet Actions de GitHub : désactiver les quelque 400 anciennes automatisations ponctuelles qui n'ont plus de fichier, et ne garder que les 14 du dossier `.github/workflows`.

# Annexe A — Les 8 fonctions telles qu'elles sont en production (relevé du 27 septembre 2026)

```sql
create or replace function public.admin_add_or_reuse_match_guest(
  p_match_id uuid,
  p_guest_player_id uuid default null,
  p_first_name text default null,
  p_last_name text default null,
  p_is_goalkeeper boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);

  if p_guest_player_id is null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        lower(btrim(coalesce(p_first_name, ''))) || '|' ||
        lower(btrim(coalesce(p_last_name, ''))) || '|' ||
        coalesce(p_is_goalkeeper, false)::text,
        0
      )
    );
  end if;

  return private.add_or_reuse_match_guest(
    p_match_id, p_guest_player_id, p_first_name, p_last_name,
    p_is_goalkeeper, p_reason
  );
end;
$function$;

create or replace function public.admin_configure_match_sport_workflow(
  p_match_id uuid,
  p_squad_size_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.configure_match_sport_workflow(p_match_id, p_squad_size_limit);
end;
$function$;

create or replace function public.admin_override_match_availability(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_private_comment text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.override_match_availability(
    p_match_id, p_season_player_id, p_status, p_private_comment, p_reason
  );
end;
$function$;

create or replace function public.admin_publish_match_convocations(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.publish_match_convocations(p_match_id, p_reason);
end;
$function$;

create or replace function public.admin_recompute_match_convocations(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.recompute_match_convocations_internal(p_match_id, p_reset_overrides);
end;
$function$;

create or replace function public.admin_save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return public.admin_publish_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
end;
$function$;

create or replace function public.admin_set_match_convocation(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_turn_should_consume boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.set_match_convocation(
    p_match_id, p_season_player_id, p_status, p_turn_should_consume, p_reason
  );
end;
$function$;

create or replace function public.admin_sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  perform private.assert_match_admin_edit_open(p_match_id);
  return private.sync_match_sport_workflow(p_match_id);
end;
$function$;

revoke all on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text) from public, anon;
grant execute on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text) to authenticated, service_role;
revoke all on function public.admin_configure_match_sport_workflow(uuid, integer) from public, anon;
grant execute on function public.admin_configure_match_sport_workflow(uuid, integer) to authenticated, service_role;
revoke all on function public.admin_override_match_availability(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.admin_override_match_availability(uuid, uuid, text, text, text) to authenticated, service_role;
revoke all on function public.admin_publish_match_convocations(uuid, text) from public, anon;
grant execute on function public.admin_publish_match_convocations(uuid, text) to authenticated, service_role;
revoke all on function public.admin_recompute_match_convocations(uuid, boolean) from public, anon;
grant execute on function public.admin_recompute_match_convocations(uuid, boolean) to authenticated, service_role;
revoke all on function public.admin_save_match_effectif(uuid, integer, jsonb, text) from public, anon;
grant execute on function public.admin_save_match_effectif(uuid, integer, jsonb, text) to authenticated, service_role;
revoke all on function public.admin_set_match_convocation(uuid, uuid, text, boolean, text) from public, anon;
grant execute on function public.admin_set_match_convocation(uuid, uuid, text, boolean, text) to authenticated, service_role;
revoke all on function public.admin_sync_match_sport_workflow(uuid) from public, anon;
grant execute on function public.admin_sync_match_sport_workflow(uuid) to authenticated, service_role;
```
