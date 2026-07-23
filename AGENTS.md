# AS-Grinta — instructions obligatoires pour les agents

## Source de vérité

Le projet Supabase distant est la source de vérité pour le schéma de données.
Les migrations présentes dans `supabase/migrations/` peuvent être incomplètes et
ne doivent jamais servir à conclure qu'une table ou une fonction n'existe pas :
vérifier toujours le schéma distant.

Le document fonctionnel prioritaire est `docs/DESIGN_V1.md`. En cas de
contradiction avec un document antérieur, les décisions validées et les
correctifs placés en tête de `docs/DESIGN_V1.md` prévalent.

Domaines couverts par le schéma actuel : comptes et profils, saisons et
effectif, adversaires et matchs, cotes, pronostics de match et de saison,
portefeuille ×2, disponibilités, listes d'attente, convocations, invités,
compositions versionnées, finalisation de match, vote collectif de l'homme du
match, statistiques, badges et titres, notifications push.

> Historique : le « tableau du coach » et toute l'infrastructure temps réel
> (sessions Live, positions live, remplacements en direct, rôle « Modérateur »)
> ont été retirés. Ne pas s'appuyer sur ces notions ni sur les tables associées.

## Décisions fonctionnelles prioritaires

- Le classement général utilise uniquement la somme directe : `total = somme(points matchs) + somme(points saison)`.
- Les pourcentages du maximum théorique et la répartition indicative d'environ 65 % matchs / 35 % saison sont des indicateurs d'affichage uniquement. Ils ne recalculent, ne normalisent et ne pondèrent jamais le total.
- Tout `match_predictions.is_filled = false` rapporte toujours 0 point, y compris si le résultat réel est 0-0.
- Tout `season_predictions.is_filled = false` rapporte toujours 0 point, y compris si la valeur réelle est 0.
- Les cotes suggérées reflètent la forme du moment : buts marqués/encaissés des 4 derniers matchs pondérés 40/30/20/10 %, nul indépendant, sans marge bookmaker (cotes équitables 1 / probabilité, arrondies à une décimale), ajustables par l'admin avant enregistrement.
- L'homme du match est désigné par un **vote collectif anonyme**, ouvert après la validation du résultat et clôturé automatiquement (sans intervention admin). Il peut y avoir des co-vainqueurs en cas d'égalité.
- Nom affiché partout : surnom s'il est renseigné, sinon prénom (repli prénom + nom), résolu côté serveur et affiché sans troncature.
- Un Admin peut annuler ou archiver un match non archivé, et le supprimer définitivement.
- Aucun joueur fictif, compte fictif ou identifiant codé en dur ne doit être utilisé dans l'application.
- Supabase reste l'unique source de vérité pour toutes les données métier.
- Un cache local temporaire est autorisé uniquement pour l'interface. Il doit être reconstructible intégralement depuis Supabase et ne doit jamais devenir une source de vérité.
- Les notifications push existent (infrastructure en place). Ne pas étendre le périmètre notifications sans demande explicite.

## Règles impératives

- Utiliser Supabase pour les compositions, buts, cotes, pronostics, présences, convocations et vote HDM.
- Ne jamais modifier le schéma Supabase sans demande explicite.
- Ne jamais utiliser la clé `service_role` dans Flutter.
- Respecter Riverpod, go_router et l'architecture feature-first.
- Avant chaque lot, analyser le code déjà présent et éviter de dupliquer les fonctionnalités.
- Exécuter `flutter analyze` et `flutter test` avant tout commit lorsque l'environnement d'exécution le permet.
- Produire un seul commit par tâche lorsque l'outil GitHub utilisé le permet.

## Verrou de migrations

Le fichier `supabase/production_migrations.lock` reflète l'état de la production
(nombre de migrations, dernière version, empreinte). Le garde-fou nocturne
`migration_inventory.yml` compare la prod à ce verrou. Après avoir appliqué de
nouvelles migrations en production, resynchroniser le verrou via la branche
dédiée `ci/supabase-migration-drift-guard` (seule autorisée à le modifier).
