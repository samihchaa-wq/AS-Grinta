# AS Grinta — Document de conception V1

Ce document est la référence fonctionnelle prioritaire du projet AS Grinta. Il remplace les formulations antérieures contradictoires.

---

## 1. Décisions fonctionnelles validées

1. Le rôle d'un compte est global et permanent, indépendant des saisons.
2. Un compte peut exister sans appartenir à un effectif.
3. Pour un CSC adverse, aucun joueur AS Grinta n'est impliqué : buteur et passeur sont masqués et enregistrés à `null`.
4. Le classement général utilise uniquement la somme directe :

```text
total = somme(points matchs) + somme(points saison)
```

Les pourcentages du maximum théorique et la répartition indicative d'environ 65 % matchs / 35 % saison sont uniquement des indicateurs d'affichage. Ils ne servent jamais à recalculer, normaliser ou pondérer le total.
5. Pour un joueur arrivé en cours de saison, les indicateurs sont relatifs aux matchs disponibles depuis son arrivée.
6. La règle « un seul match par jour » s'applique uniquement à la création initiale. Un report peut créer deux matchs le même jour.
7. L'évaluation des pronostics de saison démarre dès le premier match joué par le joueur concerné. Si le joueur termine la saison avec moins de trois matchs joués, la catégorie concernée est exclue des statistiques et classements finaux.
8. Seul un Admin peut prendre, demander ou céder volontairement le contrôle d'un Live.
9. Le Modérateur n'intervient dans le contrôle du Live qu'en reprise forcée après le délai de grâce prévu.
10. Les notifications push sont hors périmètre V1.
11. Le multi-appareils est autorisé. Le contrôleur est identifié par `controller_session_id`, pas seulement par `profile_id`.
12. La photo de profil est compressée côté client, sans limite métier stricte supplémentaire.
13. Les « matchs réellement joués » sont ceux auxquels le joueur a effectivement participé via `match_participants`.
14. Les pronostics de saison sont recalculés progressivement après chaque match terminé.
15. Une ligne `match_predictions` est créée automatiquement pour chaque compte actif lors de la création d'un match.
16. Tout pronostic de match avec `is_filled = false` rapporte toujours 0 point, y compris si le résultat réel est 0-0.
17. Une ligne `season_predictions` est créée automatiquement pour chaque pronostiqueur, chaque joueur actif et chaque catégorie applicable.
18. Toute prédiction de saison avec `is_filled = false` rapporte toujours 0 point, y compris si la valeur réelle est 0.
19. Les prédictions de saison sont publiques dès leur saisie.
20. Un match possède exactement un seul homme du match.
21. Un Admin peut annuler ou archiver un match non archivé. Seul le Modérateur peut supprimer définitivement un match.
22. Un cache local temporaire est autorisé uniquement pour l'interface et la reprise visuelle. Il doit être entièrement reconstructible depuis Supabase et ne doit jamais devenir une source de vérité.
23. Aucun joueur, compte ou identifiant fictif n'est autorisé dans l'application.

---

## 2. Système de cotes et points

### 2.1 Points de pronostic de match

```text
Score exact trouvé : cote_résultat × 15
Bon résultat seul : cote_résultat × 10
Aucun des deux : 0
is_filled = false : 0, sans exception
```

Il n'existe pas de cote de score exact distincte. Le score exact applique un multiplicateur ×1,5 à la récompense du bon résultat.

### 2.2 Points de pronostic de saison

```text
précision = max(0, 1 − |valeur_réelle − objectif_ajusté| ÷ max(objectif_ajusté, 1))
points = arrondi(précision × 20)
```

`is_filled = false` rapporte toujours 0 point, même si la valeur réelle est 0.

### 2.3 Modèle de cotes V2.1

Le modèle inclut obligatoirement une marge bookmaker de 5 %.

Pondération temporelle :

```text
Saison N : 40 %
N-1 : 25 %
N-2 : 18 %
N-3 : 10 %
N-4 et au-delà : 7 %
```

Indice d'écart :

```text
écart = (λ_for − λ_against) / (λ_for + λ_against + 0,001)
```

Probabilité du nul :

```text
|écart| < 0,15 : 30 %
0,15 à 0,35 : 25 %
0,35 à 0,55 : 21 %
≥ 0,55 : 17 %, jamais sous 15,5 %
```

Répartition victoire/défaite :

```text
p_vic_share = 0,5 + min(0,32, |écart| / 2)
```

La probabilité de victoire est plafonnée à 82 %.

Application de la marge :

```text
P_avec_marge = P_équitable × 1,05
cote = 1 / P_avec_marge
```

Les cotes sont calculées et figées lors de la création du match. Elles ne sont jamais recalculées rétroactivement.

---

## 3. Modèle de données canonique

### `profiles`
- `id uuid` PK, lié à `auth.users.id`
- `first_name text not null`
- `last_name text not null`
- `email text not null unique`
- `photo_url text null`
- `role text not null` parmi `pronostiqueur`, `admin`, `moderateur`
- `is_goalkeeper boolean not null default false`
- `status text not null` parmi `active`, `archived`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

### `seasons`
- `id uuid` PK
- `name text not null unique`
- `status text not null` parmi `open`, `archived`
- une seule saison `open`
- `created_at timestamptz not null default now()`

### `season_players`
- `id uuid` PK
- `season_id uuid` FK
- `profile_id uuid` FK
- `is_goalkeeper_snapshot boolean not null`
- `joined_at timestamptz not null default now()`
- unique `(season_id, profile_id)`

### `opponents`
- `id uuid` PK
- `name text not null unique`
- `created_at timestamptz not null default now()`

### `matches`
- `id uuid` PK
- `season_id uuid` FK
- `opponent_id uuid` FK
- `match_date date not null`
- `match_time time not null`
- `location text not null` parmi `domicile`, `exterieur`
- `planned_duration_minutes int not null check > 0`
- `status text not null` parmi `a_venir`, `en_cours`, `termine`, `archive`
- `score_as_grinta int null check 0..99`
- `score_adverse int null check 0..99`
- `created_by uuid` FK not null
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

La contrainte d'un match par jour est applicative et limitée à la création initiale.

### `match_participants`
- `id uuid` PK
- `match_id uuid` FK
- `profile_id uuid` FK
- unique `(match_id, profile_id)`

### `live_sessions`
- `id uuid` PK
- `match_id uuid` FK unique
- `status text` parmi `not_started`, `running`, `paused`, `halftime`, `finished`
- `controller_profile_id uuid` FK null
- `controller_session_id text` null
- `controller_disconnected_at timestamptz` null
- `elapsed_seconds int not null default 0`
- `clock_started_at timestamptz` null, fourni par le serveur
- `formation text` null
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

### `live_positions`
- `id uuid` PK
- `live_session_id uuid` FK
- `profile_id uuid` FK
- `slot_code text` null ; `null` représente le banc
- unique `(live_session_id, profile_id)`
- unique `(live_session_id, slot_code)` lorsque `slot_code` n'est pas null
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

### `goals`
- `id uuid` PK
- `match_id uuid` FK
- `team text` parmi `as_grinta`, `adverse`
- `minute int` entre 0 et 100
- `goal_type text` parmi `jeu`, `penalty`, `coup_franc`, `csc_adverse`
- `scorer_profile_id uuid` FK null
- `assist_type text` parmi `connu`, `sans_passe`, `inconnu`
- `assist_profile_id uuid` FK null
- `created_order bigserial`
- `created_at timestamptz not null default now()`

Pour un but adverse ou un `csc_adverse`, buteur et passeur AS Grinta sont absents.

### `substitutions`
- `id uuid` PK
- `live_session_id uuid` FK
- `profile_id uuid` FK
- `action text` parmi `in`, `out`
- `minute int` entre 0 et 100
- `created_at timestamptz not null default now()`

### `match_motm`
- `id uuid` PK
- `match_id uuid` FK unique
- `profile_id uuid` FK
- `created_by uuid` FK not null
- `created_at timestamptz not null default now()`

Il ne peut exister qu'un seul homme du match par match.

### `match_predictions`
- `id uuid` PK
- `match_id uuid` FK
- `profile_id uuid` FK
- scores prédits entre 0 et 99, par défaut 0-0
- `is_filled boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- unique `(match_id, profile_id)`

### `season_predictions`
- `id uuid` PK
- `season_id uuid` FK
- `predictor_profile_id uuid` FK
- `player_profile_id uuid` FK
- `category text` parmi `buts`, `passes`, `hommes_du_match`, `clean_sheets`
- `predicted_value_20 int not null default 0`
- `is_filled boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- unique `(season_id, predictor_profile_id, player_profile_id, category)`

`clean_sheets` concerne uniquement les gardiens. Les trois autres catégories concernent uniquement les joueurs de champ.

### `match_odds`
- `id uuid` PK
- `match_id uuid` FK unique
- trois cotes de résultat, chacune ≥ 1
- `computed_at timestamptz not null default now()`

Les valeurs stockées incluent la marge de 5 % du modèle V2.1.

### `formations`
- `code text` PK
- `label text not null`
- `slots jsonb not null`
- `created_at timestamptz not null default now()`

Formations initiales : 4-4-2, 4-3-3, 3-5-2, 4-2-3-1, 5-3-2.

---

## 4. Données dérivées

Les faits bruts restent la source de vérité. Les statistiques et classements sont dérivés :

- `v_player_season_stats`
- `v_player_career_stats`
- `v_match_prediction_points`
- `v_season_prediction_points`
- `v_classement_general`

`v_classement_general` additionne directement les points de match et de saison. Les pourcentages affichés sont informatifs uniquement.

---

## 5. Sécurité et RLS

- `profiles` : lecture authentifiée ; modification personnelle limitée au prénom, nom et photo ; rôle, statut et statut gardien gérés selon les droits métier.
- `seasons` et `season_players` : lecture authentifiée ; écriture réservée au Modérateur ou au service autorisé.
- `matches` : lecture authentifiée ; Admin autorisé à créer, modifier, annuler ou archiver un match non archivé ; Modérateur autorisé à corriger et supprimer définitivement.
- données Live : lecture authentifiée ; écriture réservée à la session Admin contrôleur ; Modérateur uniquement en reprise forcée.
- `match_predictions` : lecture de son propre pronostic avant révélation, lecture publique après la fin ; écriture uniquement par le propriétaire et pendant la fenêtre autorisée.
- `season_predictions` : lecture publique ; écriture uniquement par le pronostiqueur propriétaire.
- aucune clé `service_role` dans Flutter.

---

## 6. Architecture Flutter

- Flutter, architecture feature-first.
- Riverpod pour l'état.
- go_router pour la navigation et les gardes de rôle.
- Supabase Auth, Database, Storage et Realtime.
- affichage des dates en Europe/Paris, stockage UTC.
- aucune donnée fictive.
- cache local seulement temporaire, visuel et reconstructible.
- gestion explicite des pertes réseau et action « Réessayer ».

Fonctionnalités :

- Authentification et profils
- Saisons et effectifs
- Matchs, adversaires, reports et participants
- Live, contrôle, composition, buts, remplacements et finalisation
- Statistiques saison et carrière
- Pronostics de match et de saison
- Classement général
- Accueil et profil

---

## 7. Lots de développement

| Lot | Contenu |
|---|---|
| 0 | Supabase, Flutter, CI, import des 156 matchs, calibration des cotes |
| 1 | Comptes, rôles, profils |
| 2 | Saisons et effectif |
| 3 | Matchs, adversaires, confrontations, participants |
| 4 | Live : chrono serveur, contrôle, cession, reprise forcée |
| 5 | Composition, terrain, buts, remplacements, temps de jeu |
| 6 | Fin de match, correction, homme du match, archivage |
| 7 | Statistiques et agrégations |
| 8 | Pronostics de match, fenêtre, confidentialité, points |
| 9 | Pronostics de saison, objectifs ajustés, recalcul progressif |
| 10 | Classement général par somme directe, égalités et évolution |
| 11 | Écrans finaux et expérience utilisateur |
| 12 | Tests fonctionnels et validation V1 |

---

## 8. État de validation

Toutes les décisions fonctionnelles de ce document sont validées. La liste des formations reste modifiable sans impact structurel majeur.
