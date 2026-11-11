# AS Grinta

Application du club de football AS La Grinta : organisation des matchs,
effectif, composition d’équipe, match en direct, statistiques et vie du club.
Elle conserve aussi les pronostics entre membres comme fonctionnalité
complémentaire.

L’application est une PWA (application web installable sur le téléphone)
écrite en Flutter, avec Supabase comme source de vérité pour toutes les données
du club.

## Ce que fait l’application

### Avant le match

- Calendrier de la saison, saisons archivées consultables en lecture seule,
  abonnement depuis son agenda (Apple, Google, Outlook), mis à jour tout seul.
- Disponibilités des joueurs, et indisponibilités déclarées à l’avance sur une
  période.
- Convocations, liste d’attente avec rotation, invités de match sans compte.
- Météo du prochain match.

### Composition

- Éditeur tactique : dispositifs, placement des joueurs, banc.
- Simulation d’un onze cohérent à partir des postes réellement occupés par
  chaque joueur au fil des saisons, avec rotation des remplaçants.

### Jour de match

- Live : chronomètre, buts et passes décisives, remplacements, composition
  réelle.
- Compte rendu validé en fin de match, qui alimente la fiche du match et les
  statistiques.

### Après le match

- Vote anonyme de l’Homme du match, clos 24 heures après le coup d’envoi.
- Statistiques individuelles et collectives, saison par saison et toutes
  saisons confondues.
- Badges automatiques et manuels, armoire à trophées, bilan de saison animé.

### Pour tout le club

- Pronostics de score et classement entre membres.
- Notifications sur le téléphone : ouverture des disponibilités, convocation,
  liste d’attente, rappels, vote de l’Homme du match.
- Comptes validés par un administrateur ; deux niveaux d’accès (Utilisateur et
  Admin), le coach pilotant le Live de sa saison.

Le fonctionnement détaillé de chaque module est décrit dans
`docs/regles-metier.md`.

## Architecture

- Application : Flutter (version web/PWA), Riverpod, `go_router`.
- Serveur : Supabase — PostgreSQL avec règles d’accès ligne par ligne (RLS),
  Auth, Storage et Realtime.
- Edge Functions (TypeScript) pour les opérations serveur : notifications,
  flux d’agenda, gestion des comptes, rappels.
- Hébergement : GitHub Pages ; contrôles et déploiements par GitHub Actions.

### Organisation du dépôt

```text
lib/
  app/        routeur et navigation principale
  core/       briques partagées : thème, widgets, réseau, journalisation…
  features/   une fonctionnalité par dossier, en trois couches :
              data (accès aux données), domain (règles), presentation (écrans)
test/         même arborescence que lib/, plus :
  architecture/  règles vérifiées sur l’ensemble du code
  web/           page d’accueil PWA et service worker
supabase/     migrations SQL, Edge Functions, tests de la base (pgTAP)
web/          coquille de la PWA, service worker, page d’abonnement agenda
tool/         scripts de maintenance et de contrôle
docs/         documentation de référence
config/       valeurs publiques de configuration de production
```

## Qualité et fiabilité

Chaque modification passe par une pull request et des contrôles automatiques
avant d’arriver en production :

- formatage, analyse statique stricte (aucun avertissement toléré), plus de
  1 000 tests Flutter, plancher de couverture de tests, build web et budget
  de poids de l’application ;
- base de données de test installée dans un environnement isolé (jamais la
  production), plus de 130 fichiers de tests pgTAP (règles métier et droits
  d’accès) et lint SQL ;
- essai de l’application compilée sur plusieurs tailles d’écran, liens
  profonds et rechargement hors ligne ;
- garde-fous sur la production : écart de migrations, définitions de fonctions
  modifiées hors migration, volume de requêtes anormal (contrôle quotidien) ;
- sauvegarde chiffrée hebdomadaire, suivie d’un exercice de restauration
  automatique ;
- actions GitHub épinglées par empreinte, dépendances surveillées
  (Dependabot, avis de sécurité Pub) ;
- références d’incident (« ASG-… ») affichées à l’utilisateur et journalisées
  sans le contenu sensible de l’erreur.

## Démarrer en local

Les valeurs clientes publiques de production sont centralisées dans
`config/production.json`.

```bash
flutter pub get --enforce-lockfile
flutter run \
  --dart-define-from-file=config/production.json \
  --dart-define=APP_VERSION=dev
```

Contrôles à lancer avant de proposer un changement :

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-warnings --fatal-infos
flutter test
```

## Travailler sur le projet

### Source de vérité

Le fonctionnement réel de la production prévaut sur la documentation et sur
les anciennes migrations.

Les migrations Supabase déjà appliquées restent dans le dépôt comme historique
immuable. Elles peuvent donc décrire d’anciennes règles qui ne sont plus
actives. Les règles de travail détaillées (agents compris) sont dans
`AGENTS.md`.

### Qualité attendue

Les changements applicatifs importants doivent passer au minimum :

- formatage Dart ;
- `flutter analyze` ;
- tests Flutter ;
- build Web ;
- contrôles Supabase/RLS concernés ;
- tests runtime / smoke tests applicables.

La CI Supabase construit un schéma isolé avec les migrations courantes
nécessaires puis exécute l’ensemble des tests pgTAP/RLS découverts et le lint
SQL. Un contrôle vert n’est toutefois pas une raison pour ignorer un écart
observé directement en production.

## Documentation courante

Les documents à maintenir comme références actuelles sont :

- `docs/regles-metier.md` — fonctionnement détaillé de chaque module ;
- `docs/NOTIFICATIONS_V2.md` — contrat des notifications ;
- `docs/MATCH_WEATHER.md` — météo du prochain match ;
- `docs/business-security-matrix.md` — invariants de sécurité métier ;
- `docs/privacy-and-retention.md` — données personnelles et conservation ;
- `docs/database-release-process.md` — livraison Supabase et migrations ;
- `docs/dependency-upgrade-plan.md` — politique de mise à jour Pub et migrations majeures ;
- `docs/production-operations.md` — exploitation et diagnostic de production ;
- `docs/observability.md` — références d’incident ;
- `docs/repository-protection.md` — protections GitHub ;
- `docs/ui-foundations.md` — fondations UI encore utilisées.

`docs/changes/` rassemble les notes de décision et de correctif rédigées au
fil des évolutions marquantes ; `CHANGELOG.md` retrace les versions.

Les comptes rendus de lancement et anciennes spécifications restent consultables dans l’historique Git mais ne sont pas conservés comme documentation active.
