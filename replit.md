# AS Grinta

Application mobile Flutter pour l'équipe de football amateur AS Grinta, avec une cible web pour Replit.

## Stack

- **Flutter 3.32.0** (installé via Nix, `stable-25_05`)
- **Supabase** — Auth, PostgreSQL, Realtime, Storage
- **Riverpod** — gestion d'état
- **go_router** — navigation
- **Architecture feature-first** (`lib/features/`)

## How to run

The workflow `Start application` builds and serves the Flutter web app on port 5000:

```
flutter build web --release && python3 -m http.server 5000 --directory build/web
```

The app is served at `http://localhost:5000` (Replit preview pane).

## Supabase credentials

The app ships with hardcoded default values in `lib/core/config/supabase_config.dart` (read from `--dart-define` at build time). No secrets need to be set for the Replit preview to work.

## Project structure

```
lib/
  app/          # Router, shell, root widget
  core/         # Config, theme, providers, network
  features/     # auth, admin, home, live, matches, predictions, profile, statistics
  shared/       # Shared widgets
web/            # Flutter web entry point (index.html, manifest.json)
supabase/       # Edge functions and migrations (reference only — remote DB is source of truth)
docs/           # DESIGN_V1.md — functional specification
```

## Key rules (from AGENTS.md)

- Supabase remote is the source of truth for schema — never conclude a table is missing from local migrations.
- Never modify the Supabase schema without explicit request.
- Never use `service_role` key in Flutter.
- Run `flutter analyze` and `flutter test` before committing.
- No hardcoded players, fictional accounts, or IDs.

## GitHub deployment

The repo has a `.github/workflows/deploy_pages.yml` workflow that deploys to GitHub Pages at `/AS-Grinta/`. The `web/index.html` source uses relative paths (`flutter_bootstrap.js`, `manifest.json`) so both the Replit server (base `/`) and GitHub Pages build (`--base-href /AS-Grinta/`) work correctly.

## User preferences

- Fix all compilation errors without simplifying or removing features.
- Keep existing architecture (feature-first, Riverpod, go_router).
