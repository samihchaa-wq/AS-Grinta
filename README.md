# AS Grinta

AS Grinta est l’application de pronostics et de gestion sportive de l’équipe. Elle est utilisée en production sous forme de PWA Flutter avec Supabase comme source de vérité métier.

## Source de vérité

Le fonctionnement réel de la production prévaut sur la documentation et sur les anciennes migrations.

Les migrations Supabase déjà appliquées restent dans le dépôt comme historique immuable. Elles peuvent donc décrire d’anciennes règles qui ne sont plus actives.

## Comptes et rôles

- Auto-inscription puis validation du compte.
- Trois rôles actuels : `pronostiqueur`, `admin` et `moderateur`.
- Les comptes inactifs ne peuvent pas utiliser les fonctions métier protégées.
- Les joueurs de l’effectif peuvent être liés à un compte.
- Les invités de match n’ont pas besoin de compte permanent.

## Cycle actuel d’un match

- **J-6 à 12 h, Europe/Paris** : le match entre dans la fenêtre « Prochain match » et les disponibilités s’ouvrent.
- **J-6 à 12 h → T-15** : pronostics, Effectif et Composition sont disponibles selon les droits de l’utilisateur.
- **T-15** : les pronostics ferment, Effectif/Composition sont gelés et le Live peut être ouvert.
- **Live** : chronomètre, événements, buts, remplacements et gestion de la composition réelle.
- Un joueur ou invité ajouté tardivement pendant le Live arrive directement sur le banc.
- La validation du récapitulatif Live finalise le match avant son passage normal en match passé.
- Le vote Homme du match ouvre après cette validation et reste ouvert **24 h**.

## Pronostics

- Pronostics de match ouverts dans la fenêtre active du match jusqu’à T-15.
- Les pronostics restent privés avant la validation du résultat.
- Le multiplicateur / portefeuille **×2 ne fait plus partie du produit actuel**.
- Les anciennes migrations et certaines signatures de compatibilité peuvent encore contenir des traces de ×2.
- Les pronostics de saison restent gérés séparément.

## Gestion sportive

Le module actuel comprend notamment :

- disponibilités ;
- liste d’attente et rotation ;
- convocations ;
- joueurs de l’effectif et invités ;
- composition tactique ;
- Live ;
- présence finale, buts et clean sheets ;
- statistiques ;
- vote collectif et anonyme de l’Homme du match.

## Notifications

Les notifications automatiques actuelles comprennent notamment :

- ouverture des disponibilités ;
- changements importants d’un match ;
- rappel de pronostic J-5 à 12 h si activé et nécessaire ;
- promotion depuis la liste d’attente vers les convoqués si activée ;
- ouverture du vote HDM si activée ;
- résultat du vote HDM sous le même réglage utilisateur.

Le contrat détaillé est dans `docs/NOTIFICATIONS_V2.md`.

## Statistiques, badges et profils

- Statistiques individuelles et collectives.
- Buts, clean sheets, matchs joués et Homme du match.
- Saison actuelle, saison précédente et historique toutes saisons.
- Badges automatiques et manuels.
- Photos de profil, de joueur et d’invité.

## Architecture

- Flutter, Riverpod et `go_router` ;
- Supabase Auth et PostgreSQL ;
- Supabase Storage et Realtime ;
- Edge Functions pour les opérations serveur nécessaires ;
- GitHub Actions pour les contrôles et déploiements ;
- GitHub Pages pour la version Web publique.

## Configuration locale

Les valeurs clientes publiques de production sont centralisées dans `config/production.json`.

```bash
flutter run \
  --dart-define-from-file=config/production.json \
  --dart-define=APP_VERSION=dev
```

## Qualité

Les changements applicatifs importants doivent passer au minimum :

- formatage Dart ;
- `flutter analyze` ;
- tests Flutter ;
- build Web ;
- contrôles Supabase/RLS concernés ;
- tests runtime / smoke tests applicables.

La CI Supabase construit un schéma isolé avec les migrations courantes nécessaires puis exécute l’ensemble des tests pgTAP/RLS découverts et le lint SQL. Un contrôle vert n’est toutefois pas une raison pour ignorer un écart observé directement en production.

## Documentation courante

Les documents à maintenir comme références actuelles sont :

- `docs/NOTIFICATIONS_V2.md` — contrat des notifications ;
- `docs/MATCH_WEATHER.md` — météo du prochain match ;
- `docs/business-security-matrix.md` — invariants de sécurité métier ;
- `docs/privacy-and-retention.md` — données personnelles et conservation ;
- `docs/database-release-process.md` — livraison Supabase et migrations ;
- `docs/production-operations.md` — exploitation et diagnostic de production ;
- `docs/observability.md` — références d’incident ;
- `docs/repository-protection.md` — protections GitHub ;
- `docs/ui-foundations.md` — fondations UI encore utilisées.

Les comptes rendus de lancement et anciennes spécifications restent consultables dans l’historique Git mais ne sont pas conservés comme documentation active.
