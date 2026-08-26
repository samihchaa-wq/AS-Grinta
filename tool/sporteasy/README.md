# Extraction SportEasy

Relevé de l'historique du club tel qu'il existe dans SportEasy (équipe
« AS La Grinta », identifiant 48346). Sert de **source de travail** pour un
import historique. Rien ici n'écrit dans Supabase.

## Contenu

- `client.py` — connexion et lecture de l'API SportEasy.
- `fetch_events.py` — relève tous les événements du club, toutes saisons.
- `extract_all.py` — pour chaque match passé : présents, absents, buteurs,
  passeurs, cartons, Homme(s) du match et composition.
- `data/matches_full.json` — le résultat, relevé le 2026-08-26.

## Utilisation

```sh
export SE_EMAIL='...'
export SE_PASS='...'
python3 fetch_events.py   # produit events.json
python3 extract_all.py    # produit data/matches_full.json
```

Les deux scripts reprennent là où ils se sont arrêtés si on les relance.
Aucun identifiant n'est écrit sur disque en dehors du cookie de session
(`cookies.txt`), qui ne doit pas être versionné.

## Ce que contient le relevé du 2026-08-26

505 matchs passés, de 2014-04-24 à 2026-06-22, sur 13 saisons.

| Donnée | Couverture sur les 391 matchs joués |
| --- | --- |
| Saison, date, heure | 100 % |
| Adresse | 99 % |
| Type de match et journée de championnat | 100 % |
| Effectif présent | 100 % |
| Score | 81 % (74 matchs n'ont jamais eu de score saisi) |
| Buteurs | 75 % |
| Homme du match | 60 % |
| Composition | 49 % |

Les 114 matchs annulés sont conservés dans le fichier, marqués `annule`.

## Heures : +30 minutes obligatoires

**Le champ `heure` de ce relevé est l'heure de rendez-vous du club, pas le coup
d'envoi.** Les événements SportEasy étaient créés à l'heure de convocation. Le
coup d'envoi réel a lieu **30 minutes plus tard**.

L'import en production applique donc un décalage de +30 minutes (migration
`20260826163813`). Toute reprise de ce relevé doit faire de même, sinon les
heures affichées reculent d'une demi-heure.

Le champ `meeting_at` de l'API SportEasy, lui, n'a pas été retenu : il porte
un rendez-vous calculé automatiquement (15 ou 30 minutes avant l'événement)
qui ne reflète pas la pratique du club.

## Limites connues, à trancher avant tout import

- **147 joueurs différents** apparaissent, alors que l'application n'en connaît
  que 42. Parmi les 105 autres, 43 sont des invités d'un soir (leur nom
  contient « Pote »). Un import direct créerait une fiche pour chacun.
- **74 matchs joués sans score.** `historical_match_scores` exige un score, et
  `HistoricalMatchResult` le déclare non nul côté Flutter. Décision du club au
  2026-08-26 : ces matchs restent hors de l'application.
- **27 matchs** où la somme des buts attribués ne correspond pas au score. Écart
  de saisie d'origine, assumé par le club.
- **38 matchs comptent plusieurs Hommes du match** : égalité au vote, tous les
  joueurs à égalité sont élus. C'est la règle du club.
- **2 tournois** n'ont pas d'équivalent parmi `amical`, `championnat` et
  `entre_nous`.
- Le champ `composition` est nul quand SportEasy refuse la compo : soit
  aucune n'a été enregistrée, soit elle n'a jamais été publiée aux joueurs.

## Précision de lecture

Dans l'API, le bloc de composition est rangé sous `opponent_left` même quand
l'équipe joue à l'extérieur. Se fier aux identifiants de joueurs, jamais au
côté annoncé.
