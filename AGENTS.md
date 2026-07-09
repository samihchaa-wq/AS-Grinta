# AS-Grinta — instructions obligatoires pour les agents

## Source de vérité

Le projet Supabase distant est la source de vérité pour le schéma de données. Les trois anciennes migrations présentes dans `supabase/migrations/` sont incomplètes et ne doivent jamais être utilisées pour conclure qu'une table n'existe pas.

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
