# AS Grinta — Replit

Le dépôt conserve une configuration Replit pour lancer une prévisualisation Flutter Web locale. Replit n’est pas la source de vérité fonctionnelle ni le mécanisme de déploiement de production.

## Lancement

Le bouton **Project** exécute le workflow `Start application` défini dans `.replit` :

```bash
flutter build web \
  --release \
  --dart-define-from-file=config/production.json \
  --dart-define=APP_VERSION=dev
python3 -m http.server 5000 --directory build/web
```

La prévisualisation est servie sur le port 5000.

`config/production.json` contient uniquement la configuration cliente publique nécessaire au build (URL Supabase, clé publique/publishable et URL de l’application). Les secrets serveur et la clé `service_role` ne doivent jamais être ajoutés au client ou à Replit.

## Architecture

- Flutter avec Riverpod et `go_router` ;
- architecture feature-first sous `lib/features/` ;
- configuration cliente sous `lib/core/config/app_config.dart` ;
- Supabase pour Auth, PostgreSQL, Realtime, Storage et Edge Functions ;
- production Flutter Web déployée par GitHub Pages.

## Règles de travail

`AGENTS.md` contient les règles obligatoires du dépôt. En particulier :

- la production distante est la référence de ce qui fonctionne réellement ;
- une ancienne migration Supabase est un historique immuable, pas du code mort ;
- ne jamais utiliser `service_role` dans Flutter ;
- ne jamais conclure qu’une fonctionnalité est active uniquement parce que son code existe ;
- après un changement Flutter, exécuter formatage, analyse, tests et build ;
- après un changement Supabase, conserver les tests métier/RLS et le lint SQL au vert.

Les documents fonctionnels courants sont référencés depuis le `README.md`. Les anciennes spécifications restent consultables dans l’historique Git uniquement.

## Déploiement

`.github/workflows/deploy_pages.yml` publie Flutter Web sur GitHub Pages après validation de `Flutter CI` sur `main`, puis exécute les contrôles publics prévus. La prévisualisation Replit ne remplace pas ce pipeline.
