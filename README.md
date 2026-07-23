# Ma Petite Grinta (MPG)

L’application de pronostics **et de gestion sportive** de l’AS Grinta — un clin
d’œil à Mon Petit Prono. Application web (PWA) et mobile pour une équipe de
football amateur.

## Comptes et rôles

- Auto-inscription via un lien public, puis validation par l’administrateur
- Identifiants sans e-mail ; changement de mot de passe forcé à la première
  connexion quand l’admin le demande
- Deux rôles : **pronostiqueur** (joueur) et **administrateur**
- Saisons successives avec un effectif nommé par saison

## Pronostics

- **Pronostics de match** : la fenêtre s’ouvre à la création du match et se
  ferme à H-5. Un seul match est ouvert à la fois (le premier à venir). Les
  pronos restent privés jusqu’à la validation du résultat.
- **Multiplicateur ×2** : chaque joueur dispose d’un portefeuille de ×2 à
  poser sur le prono de son choix (score exact doublé).
- **Pronostics de saison** : révélés uniquement au verrouillage de la saison.
- **Cotes suggérées** : calculées depuis la forme récente (buts des 4 derniers
  matchs pondérés 40/30/20/10 %), cotes équitables sans marge, ajustables par
  l’admin avant enregistrement.
- **Classements** dépliables (pronos et statistiques), avec colonnes « bons
  paris » et « scores exacts ».

## Module de gestion sportive

- **Disponibilités** avant chaque match, avec rappels automatiques
- **Liste d’attente** et rotation de l’effectif
- **Convocations** et **invités réutilisables** (candidats à un match)
- **Composition tactique** positionnée sur le terrain, avec photos, couronne
  de l’homme du match 👑 et ballons de buts ⚽ — publication versionnée
- **Feuille de match / finalisation** : présence, buts et clean sheets ; le
  score AS Grinta se déduit automatiquement des buts saisis
- **Vote de l’homme du match** collectif et **anonyme**, ouvert après la
  validation du résultat et clôturé automatiquement (aucune intervention admin)
- Les invités ne créent aucun compte permanent et ne comptent pas dans les
  statistiques de carrière

## Statistiques, badges et profils

- Statistiques individuelles et collectives : buts, clean sheets, homme du
  match — saison actuelle, saison précédente et toutes saisons terminées
- **Badges** automatiques et manuels, **armoire** et titres de saison
- Photos de profil, de joueur et d’invité

## Notifications et PWA

- Notifications push (disponibilités, rappels, convocations, homme du match),
  avec préférences par catégorie
- Application installable (PWA), stratégie réseau-d’abord, mise à jour proposée
  explicitement à l’utilisateur

## Navigation

- Accueil (prochain match, dernier match, vote HDM)
- Matchs / Pronos
- Classements
- Statistiques
- Paramètres (profil, notifications) et Administration pour les admins

## Configuration

Les valeurs publiques de production sont centralisées dans
`config/production.json`. Le code Dart ne contient aucune valeur de production
par défaut.

Exemple de lancement local :

```bash
flutter run \
  --dart-define-from-file=config/production.json \
  --dart-define=APP_VERSION=dev
```

Le numéro de version officiel se trouve dans `pubspec.yaml` et les changements
sont documentés dans `CHANGELOG.md`.

## Éléments volontairement absents

- Aucun tableau du coach ni contrôle de match en direct
- Aucun chronomètre, aucun statut de match « en cours »
- Aucun événement en temps réel
- Aucun carton jaune ou rouge

## Stack

- Flutter (Riverpod, go_router, architecture feature-first)
- Supabase Auth
- PostgreSQL
- Supabase Storage
- GitHub Pages

## Qualité

Chaque modification exécute :

- l’analyse statique Flutter ;
- les tests automatisés ;
- le build Flutter Web en mode release ;
- un diagnostic du rendu Web.

Le déploiement GitHub Pages vérifie ensuite les fichiers publics essentiels, la
disponibilité de l’API Supabase et l’absence d’erreur console.
