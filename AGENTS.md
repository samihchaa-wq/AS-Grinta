# AS-Grinta — instructions obligatoires pour les agents

## Source de vérité

Le projet Supabase distant est la source de vérité pour le schéma de données. Les anciennes migrations présentes dans `supabase/migrations/` sont incomplètes et ne doivent jamais être utilisées pour conclure qu'une table n'existe pas.

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

- Le classement général utilise uniquement la somme directe : `total = somme(points matchs) + somme(points saison)`.
- Les pourcentages du maximum théorique et la répartition indicative d'environ 65 % matchs / 35 % saison sont des indicateurs d'affichage uniquement. Ils ne recalculent, ne normalisent et ne pondèrent jamais le total.
- Tout `match_predictions.is_filled = false` rapporte toujours 0 point, y compris si le résultat réel est 0-0.
- Tout `season_predictions.is_filled = false` rapporte toujours 0 point, y compris si la valeur réelle est 0.
- Les cotes suggérées reflètent la forme du moment : buts marqués/encaissés des 4 derniers matchs pondérés 40/30/20/10 %, nul indépendant, sans marge bookmaker (cotes équitables 1 / probabilité, arrondies à une décimale), ajustables par l'admin avant enregistrement.
- Un match possède exactement un seul homme du match.
- Un Admin peut annuler ou archiver un match non archivé. Seul le Modérateur peut supprimer définitivement un match.
- Seul un Admin peut prendre, demander ou céder volontairement le contrôle d'un Live.
- Le Modérateur ne peut intervenir dans le contrôle du Live que lors d'une reprise forcée conforme au délai de grâce prévu.
- Aucun joueur fictif, compte fictif ou identifiant codé en dur ne doit être utilisé dans l'application.
- Supabase reste l'unique source de vérité pour toutes les données métier.
- Un cache local temporaire est autorisé uniquement pour l'interface et la reprise visuelle. Il doit être reconstructible intégralement depuis Supabase et ne doit jamais devenir une source de vérité.
- Les notifications push sont hors périmètre V1 et ne doivent pas être développées.

## Règles impératives

- Utiliser Supabase pour les compositions, positions, buts, remplacements, cotes et pronostics.
- Ne jamais modifier le schéma Supabase sans demande explicite.
- Ne jamais utiliser la clé `service_role` dans Flutter.
- Respecter Riverpod, go_router et l'architecture feature-first.
- Avant chaque lot, analyser le code déjà présent et éviter de dupliquer les fonctionnalités.
- Exécuter `flutter analyze` et `flutter test` avant tout commit lorsque l'environnement d'exécution le permet.
- Produire un seul commit par tâche lorsque l'outil GitHub utilisé le permet.

## Point bloquant actuel

Les migrations GitHub doivent être resynchronisées ultérieurement avec le schéma Supabase réel. En attendant, toute implémentation Flutter doit se baser sur le schéma Supabase distant et sur `docs/DESIGN_V1.md`, jamais sur l'absence d'une migration locale.
