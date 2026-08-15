# Plan de mise à jour des dépendances Flutter

## Politique

- Les versions compatibles avec les contraintes actuelles sont mises à jour via `flutter pub upgrade`, puis validées par la CI complète.
- Dependabot surveille Pub chaque semaine.
- Les mises à jour `minor` et `patch` sont regroupées.
- Chaque saut `major` reste isolé dans sa propre PR : aucun lot transversal de migrations majeures.
- Une dépendance abandonnée, retirée ou touchée par un avis de sécurité doit faire échouer la CI existante et être traitée prioritairement.

## État après rafraîchissement compatible

Le lockfile a été régénéré avec Flutter stable 3.47.0 sans modifier les contraintes de `pubspec.yaml`.

Mises à jour directes appliquées :

- `image` : 4.8.0 → 4.9.1 ;
- `shared_preferences` : 2.5.3 → 2.5.5 ;
- `supabase_flutter` : 2.15.4 → 2.17.2.

Leur graphe transitif a été recalculé par Pub dans le même rafraîchissement.

## Migrations majeures à traiter séparément

### connectivity_plus 6 → 7

- vérifier les changements d'API et de plateforme ;
- rejouer les tests de connectivité et les chemins hors-ligne ;
- ne pas modifier en même temps la stratégie de retry réseau.

### flutter_riverpod 2 → 3

- migration dédiée car Riverpod traverse toute l'application ;
- corriger d'abord les API dépréciées et les changements de cycle de vie/provider ;
- exécuter toute la suite Flutter, avec attention particulière à Auth, feature flags, navigation et écrans `autoDispose`.

### go_router 14 → 17

- PR dédiée ;
- vérifier redirections Auth, deep links, navigation Web/PWA et retour navigateur ;
- valider le runtime multi-viewport et le fallback SPA.

### share_plus 10 → 13

- PR dédiée ;
- vérifier les appels de partage et leur comportement Web/mobile ;
- conserver un fallback utilisateur clair si le partage système n'est pas disponible.

### flutter_lints 5 → 6

- traiter séparément des migrations fonctionnelles ;
- appliquer les nouveaux lints sans désactiver globalement une règle uniquement pour faire passer la CI.

## Règle de merge

Une mise à jour de dépendance n'est fusionnée que si formatage, analyse, tests, couverture, build Web et runtime applicables restent verts. Les migrations majeures doivent également avoir des tests ciblés sur le comportement qu'elles peuvent casser.
