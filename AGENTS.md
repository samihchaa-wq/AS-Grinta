# AS-Grinta — instructions obligatoires pour les agents

## Source de vérité

Le projet Supabase distant est la source de vérité pour le schéma de données. Les trois anciennes migrations présentes dans `supabase/migrations/` sont incomplètes et ne doivent jamais être utilisées pour conclure qu'une table n'existe pas.

Le document fonctionnel prioritaire est `docs/DESIGN_V1.md`. En cas de contradiction avec un document antérieur, les décisions validées et les correctifs placés en tête de `docs/DESIGN_V1.md` prévalent.

Tables Supabase déjà existantes :

- profiles
- seasons
- season_players
- opponents
- matches
- match_participants
- live_sessions
- live_positions
- goals
- substitutions
- match_motm
- match_odds
- match_predictions
- season_predictions
- formations

## Décisions fonctionnelles prioritaires

- Le classement général utilise la somme directe des points de match et de saison, avec une pondération naturelle estimée à environ 65 % pour les matchs et 35 % pour les pronostics de saison. Il ne faut pas implémenter une normalisation 50/50.
- Les cotes de match suivent exclusivement le modèle V2.1 décrit dans `docs/DESIGN_V1.md`, avec pondération temporelle 40/25/18/10/7 %, nul indépendant et marge bookmaker de 5 % appliquée après les probabilités équitables.
- Seul un Admin peut prendre, demander ou céder volontairement le contrôle d'un Live.
- Le Modérateur ne peut intervenir dans le contrôle du Live que lors d'une reprise forcée conforme au délai de grâce prévu.
- Aucun joueur fictif, compte fictif ou identifiant codé en dur ne doit être utilisé dans l'application.
- Supabase reste l'unique source de vérité pour toutes les données métier. Aucun cache local, JSON, map en mémoire ou stockage embarqué ne doit devenir une source de vérité.
- Les notifications push sont hors périmètre V1 et ne doivent pas être développées.

## Règles impératives

- Ne jamais créer de stockage local ou JSON comme source de vérité pour le live.
- Utiliser Supabase pour les compositions, positions, buts, remplacements, cotes et pronostics.
- Ne jamais modifier le schéma Supabase sans demande explicite.
- Ne jamais utiliser la clé `service_role` dans Flutter.
- Respecter Riverpod, go_router et l'architecture feature-first.
- Avant chaque lot, analyser le code déjà présent et éviter de dupliquer les fonctionnalités.
- Exécuter `flutter analyze` et `flutter test` avant tout commit.
- Produire un seul commit par tâche.

## Point bloquant actuel

Les migrations GitHub doivent être resynchronisées ultérieurement avec le schéma Supabase réel. En attendant, toute implémentation Flutter doit se baser sur la liste de tables ci-dessus et sur les contrats déjà présents dans le code, jamais sur l'absence d'une migration locale.
