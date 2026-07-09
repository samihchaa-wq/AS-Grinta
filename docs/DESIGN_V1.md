# AS Grinta — Document de conception V1

Ce document synthétise le cahier des charges et l'ensemble des clarifications validées avec le porteur de projet. Il sert de référence unique pour l'implémentation. **Aucun code ne doit être écrit avant validation explicite de ce document.**

---

## 1. Récapitulatif des décisions et correctifs apportés au cahier des charges

Ces points **remplacent ou précisent** le document d'origine :

| # | Sujet | Décision |
|---|---|---|
| 1 | Rôle du compte | **Global et permanent**, indépendant des saisons. La "reprise des Admins actuels" à la création d'une saison (section 6) devient un no-op automatique puisque le rôle ne change jamais de lui-même. |
| 2 | Compte sans effectif | Un compte peut exister sans jamais faire partie de l'effectif (ex. un coach qui pronostique sans jouer). |
| 3 | But contre son camp adverse | Buteur et passeur **masqués** dans le formulaire (aucun joueur AS Grinta impliqué). |
| 4 | Normalisation classement général | Basée sur le **% du score maximum théorique atteignable** pour chaque composante (match / saison). |
| 5 | Normalisation par joueur arrivé en cours de saison | Relative aux **matchs disponibles pour ce joueur** depuis son arrivée, pas au total saison. |
| 6 | Conflit report / un match par jour | **Exception autorisée** : un report peut créer temporairement deux matchs le même jour. La règle "un seul match par jour" ne s'applique qu'à la **création** d'un nouveau match, pas au report. |
| 7 | Seuil d'évaluation des pronostics de saison | **Corrige la section 25** : l'évaluation démarre dès le **1er match joué** par le joueur concerné (pas 3). Si la saison se termine avec **moins de 3 matchs joués** au total pour ce joueur, la catégorie concernée est **exclue** des statistiques/classements finaux. |
| 8 | Contrôle du live | Seuls les **Admins** peuvent prendre/demander le contrôle en dehors de la reprise forcée. Le Modérateur n'intervient qu'en reprise forcée (section 15). |
| 9 | Cession volontaire du contrôle | Un Admin en contrôle peut **céder volontairement** la main à un autre Admin, sans attendre une déconnexion. |
| 10 | Notifications | **Hors périmètre V1.** Aucune notification push. |
| 11 | Multi-appareils | **Autorisé.** Un utilisateur peut être connecté sur plusieurs appareils simultanément. Impact : le verrou de contrôle du live doit être identifié par **session/connexion**, pas seulement par utilisateur. |
| 12 | Taille photo de profil | Pas de limite stricte côté cahier des charges ; la compression côté client suffit à maîtriser la taille finale stockée. |
| 13 | "Matchs réellement joués" (formule objectif ajusté, section 25) | Corresponds aux matchs auxquels **le joueur concerné a effectivement participé** (via `match_participants`), pas aux matchs de l'équipe en général. |
| 14 | Recalcul des pronostics de saison | **Progressif**, recalculé après chaque match terminé (classement évolutif en direct), conformément à la section 26. |
| 15 | Auto-création des pronostics de match | Une ligne `match_predictions` vide est **créée automatiquement par le système** pour **chaque compte actif** (tout rôle : Pronostiqueur, Admin, Modérateur — le pronostic de match n'est pas réservé aux joueurs de l'effectif) dès la création du match. Reste à 0-0 tant que non modifiée, comptée comme telle si la fenêtre se ferme sans saisie. Symétrique avec la logique retenue pour les pronostics de saison. |
| 16 | Barème des pronostics de match — remplacement complet par un système de cotes | Le barème fixe de la section 24 (25 pts score exact, 8 pts bon résultat, +4/+2/+2/+2 bonus) est **abandonné** au profit d'un système de cotes calculées dynamiquement par match (voir §1.F). |
| 17 | Autocomplétion adversaire (précision section 8) | Lors de la création d'un match, l'Admin tape les premières lettres et voit une liste filtrée des équipes déjà rencontrées (`opponents`) ; s'il ne trouve pas l'adversaire souhaité, une option explicite **« Nouvelle équipe »** permet de créer une nouvelle entrée dans `opponents` à la volée. |
| 18 | Import de l'historique des 5 dernières saisons | Les 156 matchs fournis (2021-2026) sont **importés en base comme matchs archivés** (`matches`, `opponents`) dès le Lot 0, avec score, date, adversaire, lieu. Objectif : que les **confrontations directes** (section 9) affichent l'historique réel dès le lancement, avec repli naturel si moins de 5 confrontations existent. Le champ "compétition" du fichier source **n'est pas conservé** dans le modèle de données (il ne sert qu'à l'import, pas de suivi futur). |
| 19 | Limite de l'import — statistiques individuelles | Le fichier fourni ne contient **ni buteurs, ni passeurs, ni homme du match** par rencontre. L'import alimente donc uniquement le niveau "match" (scores, confrontations, bilans d'équipe). **Les statistiques individuelles des joueurs (buts, passes, hommes du match, clean sheets) ne peuvent pas être reconstituées pour ces 156 matchs** et ne démarreront qu'avec les matchs saisis dans l'application après son lancement. |
| 20 | Pondération temporelle du modèle de cotes (V2.1) | Les saisons récentes pèsent plus dans le calcul des cotes : **N = 40 %, N-1 = 25 %, N-2 = 18 %, N-3 = 10 %, N-4 = 7 %** (plancher 7 % au-delà). Voir détail §1.F. |
| 21 | Suppression de la cote de score exact | Il n'y a plus de cote calculée par score individuel. Une seule cote par résultat (V/N/D) est calculée par match ; le score exact applique un multiplicateur **×1,5** sur cette cote. |
| 22 | Nul indépendant et réaliste (V2.1, remplace les versions antérieures) | Le nul a sa propre probabilité (30% équilibré, 25% léger favori, 21% favori net, 17% gros favori, jamais <15%), **indépendante** de la victoire/défaite. Marge bookmaker 5% appliquée après les probas. Cotes réalistes : nul entre 3,17 et 5,60, victoire cote min ~1,4. |
| 23 | Normalisation points match/saison pour classement général | Diviseur par 10 appliqué aux points de match : score exact = `cote × 15`, bon résultat = `cote × 10`. Avec 30 matchs par saison et ~20 prédictions saison (0-20 pts chacune), les matchs dominent ~65%, la saison ~35%. Classement général = somme directe (pas de 50/50). |

### F. Système de cotes pour les pronostics de match (VALIDÉ — remplace la section 24)

**Formule de points finalisée :**

```text
Pronostics de match :
  Score exact trouvé      → points = cote_résultat × 15
  Bon résultat seul trouvé (victoire / nul / défaite, sans le score exact)
                           → points = cote_résultat × 10
  Aucun des deux          → points = 0

Pronostics de saison (par prédiction) :
  précision = max(0, 1 − |valeur_réelle − objectif_ajusté| ÷ max(objectif_ajusté, 1))
  points     = arrondi(précision × 20)

Classement général :
  Score total = Σ(points matchs) + Σ(points saison)
```

La `cote_résultat` est la cote équitable (méthodologie V2.1 ci-dessous), comprise entre ~1,17 et ~5,60 — soit des gains par match de ~18 à ~84 points pour un score exact, ~12 à ~56 pour un bon résultat seul. Avec 30 matchs par saison et ~20 prédictions de saison, les matchs pèseront ~65%, la saison ~35% du classement total.

> **Simplification** : il n'existe plus de cote de score exact séparée. Une seule cote (par résultat : victoire / nul / défaite) est calculée par match, et le score exact applique un **multiplicateur ×1,5** sur cette cote de résultat (soit ×15 au final après division par 10).

**Calcul des cotes — méthodologie finale V2.1 "nul indépendant et réaliste" (VALIDÉ, calibrée et vérifiée sur les données réelles : 156 matchs, 24 adversaires, 5 saisons). Cette version remplace intégralement les V1 et V2 précédentes.**

1. **Pondération par ancienneté de saison** (appliquée à toutes les moyennes ci-dessous, globales et par adversaire) — poids en pourcentage du total :
   ```text
   Saison N (la plus récente) : 40 %
   Saison N-1 : 25 %
   Saison N-2 : 18 %
   Saison N-3 : 10 %
   Saison N-4 : 7 %
   Au-delà : poids maintenu à 7 %
   ```

2. **Indice d'écart de niveau entre équipes** (normalisé entre -1 et +1), basé sur les lambdas Poisson pondérés :
   ```text
   écart = (λ_for − λ_against) / (λ_for + λ_against + ε)
   où ε = 0,001 pour éviter division par zéro

   écart > 0,55 : AS Grinta très dominante
   écart 0,35-0,55 : AS Grinta favori net
   écart 0,15-0,35 : AS Grinta léger favori
   écart < 0,15 : match très équilibré
   (idem miroir pour écart < 0 : adversaire dominant)
   ```

3. **Probabilité du nul — déterministe et indépendante**, basée uniquement sur l'écart :
   ```text
   |écart| < 0,15 (très équilibré)     → P(nul) = 30 % (plage 27-32 %)
   |écart| 0,15-0,35 (léger favori)    → P(nul) = 25 % (plage 23-27 %)
   |écart| 0,35-0,55 (favori net)      → P(nul) = 21 % (plage 19-23 %)
   |écart| ≥ 0,55 (très gros favori)   → P(nul) = 17 % (plage 15-19 %), plafonné à min 15,5 % (pour éviter cote > 6,50)
   ```
   **Propriété fondamentale** : la probabilité du nul diminue progressivement avec l'écart, jamais < 15 % (sauf exception), reflétant l'incertitude inhérente du football.

4. **Répartition Victoire / Défaite** sur la probabilité restante (100 % - P(nul)), selon l'écart de niveau :
   ```text
   p_vic_share = 0,5 + min(0,32, |écart| / 2)

   Si écart > 0 (AS Grinta dominante) :
       P(victoire) = (1 − P(nul)) × p_vic_share

   Si écart ≤ 0 (adversaire dominant) :
       P(victoire) = (1 − P(nul)) × (1 − p_vic_share)
   ```
   **Plafond stricte** : P(victoire) ≤ 82 %, même en cas de domination écrasante, pour conserver une part irréductible d'incertitude (réalité du football).

5. **Marge bookmaker 5 %** (appliquée APRÈS le calcul des probabilités, de manière transparente) :
   ```text
   P(with margin) = P(fair) × 1,05
   cote décimale = 1 / P(with margin)
   ```
   Exemple : si P(victoire) équitable = 60 %, alors avec marge = 60 % × 1,05 = 63 %, cote = 1 / 0,63 ≈ 1,59.

6. **Conversions et vérifications finales** :
   - Somme des probabilités équitables = 100 % (avant marge) ✓
   - Somme des probabilités avec marge ≈ 105 % (captée par le margin) ✓
   - Cote nul ≤ 6,50 (toutes les cotes) ✓
   - Cote victoire min. 1,2 (pour dominateurs nets) ✓
   - Matchs équilibrés (P(nul) 27-32 %) ont cotes de nul 3,2-3,8 ✓
   - Gros favoris (P(nul) 15-17 %) ont cotes de nul 5,6-6,2 ✓

**Exemples vérifiés sur les données réelles (cotes finales V2.1)** :
- Très dominée (AS Hersoise à domicile) : P(V/N/D) = 54,8/21,0/24,2 %, cotes = 1,76 / 4,54 / 3,85
- Équilibrée (FOOT ÇA-ME-DIT à domicile) : P(V/N/D) = 43,6/30,0/26,4 %, cotes = 2,07 / 3,17 / 3,48
- Gros favori (Autobus Toulousain à domicile) : P(V/N/D) = 58,8/17,0/24,2 %, cotes = 1,48 / 5,60 / 5,16

Le tableau complet des 24 adversaires + "jamais affronté" (domicile et extérieur, 50 lignes) avec probabilités et cotes a été livré en fichier Excel (`AS_Grinta_Cotes_V2_Final.xlsx`).

**Évolution des cotes au fil de la saison (VALIDÉ)** : chaque nouveau match crée ses cotes à partir de l'historique complet à jour. Les résultats récents modifient l'indice d'écart de chaque adversaire dans les futures rencontres, d'où des cotes naturellement évolutives sans recalcul rétroactif des matchs déjà créés.

**Table complémentaire au modèle de données** (voir §2) : `match_odds` — cotes calculées et figées à la création du match : `id`, `match_id` (FK, unique), `odds_victoire_as_grinta`, `odds_nul`, `odds_victoire_adverse` (numeric, chacun ≥ 1), `computed_at` (timestamptz).

**Calibration** : réalisée sur le fichier historique fourni (156 matchs, 5 saisons). Le modèle se recalibre automatiquement chaque jour ou chaque saison à partir des nouveaux résultats.

### Points tranchés avec le porteur de projet (validés)

**A. Barème des pronostics de saison — formule proportionnelle (VALIDÉ)**

Par prédiction (couple joueur × catégorie) :

```text
précision = max(0, 1 − |valeur_réelle − objectif_ajusté| ÷ max(objectif_ajusté, 1))
points     = arrondi(précision × 20)
```

Le plancher `max(objectif_ajusté, 1)` au dénominateur garantit que sur les petits objectifs (0 ou 1), la moindre erreur d'une unité fait tomber la précision à 0 (comportement volontairement strict). Sur les objectifs plus élevés (ex. 15), un écart de 2 ne pénalise que légèrement (précision = 0,87 → 17 pts). Le cas `objectif_ajusté = 0` avec `réel = 0` donne une précision de 1 → 20 pts (prédiction correcte récompensée).

Score de saison normalisé (%) = somme des points obtenus ÷ (20 × nombre de prédictions attendues pour ce pronostiqueur).

**B. Exhaustivité des prédictions de saison (VALIDÉ)**

Une ligne `season_predictions` est **créée automatiquement par le système** pour chaque pronostiqueur, pour chaque joueur actif de l'effectif, dans les catégories qui le concernent (joueur de champ vs gardien), avec `predicted_value_20 = 0` par défaut. Le pronostiqueur peut modifier cette valeur. **S'il ne le fait pas, la case reste à 0 et est comptée comme telle dans le calcul** — c'est une prédiction valide de "0", qui rapporte 0 point selon le barème (pas d'exclusion, pas de traitement spécial). Ceci garantit un dénominateur de normalisation identique pour tous les pronostiqueurs, et offre la possibilité de parier à 0 (utile pour les joueurs dont on ne prédit aucune statistique).

**C. Confidentialité des pronostics de saison (VALIDÉ)**

Contrairement aux pronostics de match, les prédictions de saison sont **publiques dès leur saisie** — aucune confidentialité, aucune révélation différée. Tout utilisateur peut consulter les prédictions de tous, pendant toute la saison.

**D. Formations prédéfinies (proposition, non bloquante)**

Liste initiale proposée : 4-4-2, 4-3-3, 3-5-2, 4-2-3-1, 5-3-2. Table de référence statique, modifiable facilement en V2.

**E. Gestion technique du multi-appareils pour le contrôle du live**

Le contrôleur du live est identifié par un `controller_session_id` (identifiant de connexion/socket), pas seulement par `profile_id`. Ainsi, si un Admin est connecté sur deux appareils, seule la session qui a pris le contrôle est reconnue comme contrôleur ; l'autre appareil du même Admin est traité comme spectateur en lecture seule.

---

## 2. Modèle de données complet (PostgreSQL / Supabase)

Conventions : UUID pour toutes les clés primaires, dates/heures stockées en UTC, affichage en Europe/Paris. Toutes les tables ont `created_at timestamptz default now()` sauf mention contraire.

### 2.1 `profiles`
Lié à `auth.users` (Supabase Auth) via `id`.

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK, = auth.users.id |
| first_name | text | not null |
| last_name | text | not null |
| email | text | not null, unique |
| photo_url | text | nullable (Supabase Storage) |
| role | text | not null, check in ('pronostiqueur','admin','moderateur'), default 'pronostiqueur' |
| is_goalkeeper | boolean | not null, default false — statut gardien global actuel |
| status | text | not null, check in ('active','archived'), default 'active' — unifie archivage compte + effectif |
| created_at | timestamptz | not null, default now() |
| updated_at | timestamptz | not null, default now() |

> Un profil sans aucune ligne dans `season_players` n'a simplement jamais fait partie de l'effectif (cas du coach/pronostiqueur pur).

### 2.2 `seasons`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| name | text | not null, unique — format auto-généré `2026-2027` |
| status | text | not null, check in ('open','archived'), default 'open' |
| created_at | timestamptz | not null, default now() |

> Contrainte : **une seule saison `open` à la fois** → index unique partiel `unique (status) where status = 'open'`.

### 2.3 `season_players`
Snapshot de l'effectif pour une saison donnée.

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| season_id | uuid | FK → seasons, not null |
| profile_id | uuid | FK → profiles, not null |
| is_goalkeeper_snapshot | boolean | not null — copié au moment de la création/adhésion |
| joined_at | timestamptz | not null, default now() |

> Contrainte unique : `(season_id, profile_id)`.

### 2.4 `opponents`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| name | text | not null, unique |
| created_at | timestamptz | not null, default now() |

### 2.5 `matches`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| season_id | uuid | FK → seasons, not null |
| opponent_id | uuid | FK → opponents, not null |
| match_date | date | not null |
| match_time | time | not null |
| location | text | not null, check in ('domicile','exterieur') |
| planned_duration_minutes | int | not null, check > 0 |
| status | text | not null, check in ('a_venir','en_cours','termine','archive'), default 'a_venir' |
| score_as_grinta | int | nullable, check between 0 and 99 |
| score_adverse | int | nullable, check between 0 and 99 |
| created_by | uuid | FK → profiles, not null |
| updated_at | timestamptz | not null, default now() |

> Règle "un seul match par jour" : appliquée **côté service applicatif à la création uniquement** (pas de contrainte unique DB stricte sur `match_date`, pour permettre l'exception au report — décision #6).

### 2.6 `match_participants`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| match_id | uuid | FK → matches, not null |
| profile_id | uuid | FK → profiles, not null |

> Contrainte unique : `(match_id, profile_id)`.

### 2.7 `live_sessions`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| match_id | uuid | FK → matches, not null, unique |
| status | text | not null, check in ('not_started','running','paused','halftime','finished'), default 'not_started' |
| controller_profile_id | uuid | FK → profiles, nullable |
| controller_session_id | text | nullable — identifiant de connexion (multi-appareils) |
| controller_disconnected_at | timestamptz | nullable — début du délai de grâce 60s |
| elapsed_seconds | int | not null, default 0 |
| clock_started_at | timestamptz | nullable — référence serveur pour le calcul en direct |
| formation | text | nullable, FK logique → formations.code |
| updated_at | timestamptz | not null, default now() |

### 2.8 `live_positions`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| live_session_id | uuid | FK → live_sessions, not null |
| profile_id | uuid | FK → profiles, not null |
| slot_code | text | nullable — null = banc ; sinon code d'emplacement (ex. 'GK','DC1'...) |
| updated_at | timestamptz | not null, default now() |

> Contraintes : unique `(live_session_id, profile_id)` (un emplacement par joueur) ; unique `(live_session_id, slot_code) where slot_code is not null` (un joueur par emplacement).

### 2.9 `goals`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| match_id | uuid | FK → matches, not null |
| team | text | not null, check in ('as_grinta','adverse') |
| minute | int | not null, check between 0 and 100 |
| goal_type | text | nullable, check in ('jeu','penalty','coup_franc','csc_adverse') — requis si team = 'as_grinta' |
| scorer_profile_id | uuid | FK → profiles, nullable — masqué si goal_type = 'csc_adverse' ou team = 'adverse' |
| assist_type | text | nullable, check in ('connu','sans_passe','inconnu') |
| assist_profile_id | uuid | FK → profiles, nullable — uniquement si assist_type = 'connu' ; masqué si goal_type = 'csc_adverse' |
| created_order | bigserial | — pour le tri "minute puis ordre de création" |

### 2.10 `substitutions`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| live_session_id | uuid | FK → live_sessions, not null |
| profile_id | uuid | FK → profiles, not null |
| action | text | not null, check in ('in','out') |
| minute | int | not null, check between 0 and 100 |

### 2.11 `match_motm`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| match_id | uuid | FK → matches, not null |
| profile_id | uuid | FK → profiles, not null |
| created_by | uuid | FK → profiles, not null |

> Contrainte unique : `(match_id, profile_id)`.

### 2.12 `match_predictions`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| match_id | uuid | FK → matches, not null |
| profile_id | uuid | FK → profiles, not null |
| predicted_score_as_grinta | int | not null, check between 0 and 99, default 0 |
| predicted_score_adverse | int | not null, check between 0 and 99, default 0 |
| is_filled | boolean | not null, default false — passe à true dès la première modification par le joueur |
| updated_at | timestamptz | not null, default now() |

> Contrainte unique : `(match_id, profile_id)`. **Création automatique** par le système (trigger ou service) pour **chaque compte actif** dès la création du match — pas seulement les membres de l'effectif, puisque tout Pronostiqueur/Admin/Modérateur actif peut parier sur le score, qu'il joue ou non. **Point d'attention** : le score par défaut est 0-0 ; si le match se termine réellement 0-0, une ligne `is_filled = false` ne doit **pas** être comptée comme "score exact" — elle doit rapporter 0 point comme un pronostic vide (règle section 24), d'où la nécessité du champ `is_filled` distinct des valeurs de score.

### 2.13 `season_predictions`

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| season_id | uuid | FK → seasons, not null |
| predictor_profile_id | uuid | FK → profiles, not null — celui qui prédit |
| player_profile_id | uuid | FK → profiles, not null — le joueur concerné |
| category | text | not null, check in ('buts','passes','hommes_du_match','clean_sheets') |
| predicted_value_20 | int | not null, check >= 0, default 0 — prédiction normalisée pour 20 matchs |
| is_filled | boolean | not null, default false — passe à true dès la première modification par le pronostiqueur |
| updated_at | timestamptz | not null, default now() |

> Contrainte unique : `(season_id, predictor_profile_id, player_profile_id, category)`. Validation applicative : `clean_sheets` uniquement si `player_profile_id` est gardien ; les 3 autres catégories uniquement pour les joueurs de champ. **Création automatique** par le système (trigger ou service) pour chaque pronostiqueur × chaque joueur actif × catégories applicables, dès l'ouverture de la saison ou l'arrivée du pronostiqueur/du joueur ; `predicted_value_20` reste à 0 tant que non modifié. **Point d'attention** (même logique que pour les pronostics de match) : si la valeur réelle d'un joueur est aussi 0, une ligne `is_filled = false` ne doit pas être comptée comme une prédiction exacte — elle doit rapporter 0 point, d'où le champ `is_filled`.

### 2.14bis `match_odds`

Cotes calculées et figées à la création du match, servant de base au calcul des points des pronostics (§1.F). **Uniquement les cotes équitables de résultat** — pas de cote par score individuel (le score exact applique un multiplicateur ×1,5 sur la cote du résultat, voir §1.F).

| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK |
| match_id | uuid | FK → matches, not null, unique |
| odds_victoire_as_grinta | numeric | not null, check >= 1 |
| odds_nul | numeric | not null, check >= 1 |
| odds_victoire_adverse | numeric | not null, check >= 1 |
| computed_at | timestamptz | not null, default now() |

> Calculées une seule fois à la création du match (méthodologie V2 §1.F : Poisson pondéré 40/25/18/10/7 % + shrinkage + compression 82 % + cotes équitables sans marge), jamais recalculées ensuite — garantit que la valeur d'un pronostic déjà saisi ne change pas rétroactivement. Une cote est ≥ 1 par construction (probabilité ≤ 100 %) ; le plafond de compression borne en pratique la cote minimale à ~1,22 et les valeurs observées à ~14, sans contrainte dure supérieure en base.

### 2.14 `formations` (table de référence statique, seedée)

| Colonne | Type | Contraintes |
|---|---|---|
| code | text | PK — ex. '4-4-2' |
| label | text | not null |
| slots | jsonb | not null — liste des emplacements `{code, x, y, label}` |

### 2.15 Données dérivées (vues / cache recalculable, pas de source de vérité)

Conformément au principe "faits bruts comme source de vérité, statistiques et classements dérivés" (section 32) :

- `v_player_season_stats` — matchs joués, buts, passes, hommes du match, clean sheets, par saison, calculée depuis `match_participants`, `goals`, `match_motm`, `live_sessions`.
- `v_player_career_stats` — même chose, agrégée toutes saisons.
- `v_match_prediction_points` — points par pronostic de match, calculés depuis `match_predictions` + `match_odds` + `matches.score_*` selon le système de cotes (§1.F, remplace l'ancien barème section 24).
- `v_season_prediction_points` — points par prédiction de saison, calculés selon le barème proposé (§1.A).
- `v_classement_general` — combinaison normalisée 50/50 des deux vues précédentes, par pronostiqueur.

> Ces vues sont recalculées à la lecture ou via triggers de rafraîchissement (matérialisation optionnelle), jamais stockées comme données sources.

---

## 3. Sécurité — Politiques RLS (principes, à détailler en implémentation)

- `profiles` : lecture publique (authentifiés) ; écriture de son propre profil (prénom, nom, photo) ; `role`, `status`, `is_goalkeeper` réservés à Admin/Modérateur selon droit.
- `seasons` : lecture publique ; écriture réservée au Modérateur.
- `season_players` : lecture publique ; écriture système (création de saison) + corrections Modérateur.
- `matches` : lecture publique ; écriture Admin sur matchs non archivés ; Modérateur sur tout, y compris archivés.
- `match_participants`, `live_sessions`, `live_positions`, `goals`, `substitutions`, `match_motm` : lecture publique (lecture seule pour Pronostiqueurs pendant le live) ; écriture réservée au contrôleur actuel (Admin) + Modérateur en reprise.
- `match_predictions` : lecture restreinte à son propre pronostic avant fin du match ; lecture publique après ; écriture strictement limitée à `auth.uid() = profile_id` (règle absolue section 4).
- `season_predictions` : lecture **publique** (aucune confidentialité, contrairement aux pronostics de match — décision §1.C) ; écriture strictement limitée à `auth.uid() = predictor_profile_id`.
- Suppression définitive (joueur, match) : réservée au Modérateur uniquement.

---

## 4. Architecture technique (Flutter, feature-first)

```text
lib/
  core/
    theme/                 → thème sombre + accents verts, textstyles, spacing
    constants/
    utils/                 → formatters dates (UTC → Europe/Paris), validators
    errors/                → mapping erreurs techniques → messages utilisateur
    network/
      connectivity_service.dart   → détection perte de connexion, "Réessayer"
    supabase/
      supabase_client.dart
      realtime_service.dart       → abstraction WebSocket (Supabase Realtime)
    routing/
      app_router.dart             → go_router, garde d'accès par rôle

  features/
    auth/
      data/ (datasource, repository)
      domain/ (entities, usecases : login, invite, reset password)
      presentation/ (screens, providers/controllers)

    profile/
      → profil, photo (compression avant upload Storage), changement mdp

    seasons/
      → saison ouverte, historique saisons, création (Modérateur)

    squad/                 (effectif)
      → liste joueurs actifs/archivés, statut gardien, archivage/réactivation

    matches/
      → CRUD match, autocomplétion adversaire, confrontations directes,
        report / changement adversaire / annulation, sélection participants

    live_match/
      → chrono (horodatage serveur), contrôle unique + cession + reprise Modérateur,
        composition (terrain + banc, drag&drop), buts, remplacements,
        fin de match, correction post-match

    statistics/
      → vues saison/carrière, classements, fiches joueurs

    predictions/
      → pronostics de match (boutons +/-, fenêtre J-6, confidentialité, révélation)
      → pronostics de saison (formulaire par joueur/catégorie)
      → classement général (50/50, égalités)

    home/
      → agrégation des blocs (prochain match, action pronostic, live, etc.)

    shared/
      → widgets communs (cartes, boutons grande zone tactile, avatars,
        bannière offline/"Réessayer", indicateurs de sauvegarde auto)
```

**Décisions techniques complémentaires proposées** (non spécifiées dans le cahier des charges, à valider) :

- Gestion d'état : **Riverpod** (adapté au temps réel Supabase, testable, feature-first).
- Navigation : **go_router** avec redirections basées sur le rôle et l'état de session.
- Persistance locale légère pour reprise après coupure (ex. `live_session` en cours) : simple cache mémoire/Isar léger, à confirmer si nécessaire lors du lot "live".

---

## 5. Découpage en lots de développement (proposé)

Chaque lot est livré et validé avant de passer au suivant.

| Lot | Contenu |
|---|---|
| 0 | Setup Supabase (projet, migrations, RLS squelette), setup Flutter (thème, navigation, connectivité), CI GitHub, **import de l'historique des 156 matchs** (`opponents`, `matches` archivés) et **calibration du modèle de cotes** (Poisson + mélange pondéré) sur ces données |
| 1 | Comptes & rôles : invitation, connexion, réinitialisation mdp, profils, gestion des rôles (Modérateur) |
| 2 | Saisons & Effectif : création/archivage saison, copie effectif, statut gardien, archivage/réactivation joueur |
| 3 | Matchs : CRUD, autocomplétion adversaire, confrontations directes, report/changement adversaire/annulation, sélection participants |
| 4 | Live — socle : chrono serveur, contrôle unique + cession + reprise 60s/Modérateur, synchronisation temps réel |
| 5 | Live — composition & jeu : terrain/banc, formations, drag&drop, buts, remplacements, temps de jeu |
| 6 | Fin de match & archivage : révélation pronostics, correction score/événements, homme du match, verrouillage |
| 7 | Statistiques : agrégations saison/carrière, classements, recalculs automatiques |
| 8 | Pronostics de match : fenêtre J-6/12h, saisie, confidentialité, barème, recalcul |
| 9 | Pronostics de saison : formulaire par joueur/catégorie, objectif ajusté, barème proposé, recalcul progressif |
| 10 | Classement général : normalisation 50/50, égalités, évolution en cours de saison |
| 11 | Écrans finaux (Accueil, Matchs, Statistiques, Pronostics, Profil) & polish UX (offline, alertes de sortie, animations) |
| 12 | Tests fonctionnels complets (section 39) + vérification des critères de validation V1 (section 40) |

---

## 6. État de validation

Tous les points de conception sont désormais **validés** (§1.A, §1.B, §1.C). Seul reste ouvert, sans caractère bloquant :

1. Liste des formations prédéfinies (§1.D) — proposée, librement modifiable en cours de projet sans impact sur le modèle de données (table de référence statique).

**Le document est prêt pour le démarrage du Lot 0**, sous réserve de votre accord final.
