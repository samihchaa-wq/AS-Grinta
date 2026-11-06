# Protection du dépôt GitHub

## Branche `main`

La branche `main` doit être protégée dans les réglages GitHub avec les règles suivantes :

- exiger une pull request avant toute fusion ;
- exiger au moins une validation lorsque plusieurs mainteneurs sont disponibles ;
- annuler les validations lorsque de nouveaux commits sont ajoutés ;
- exiger la résolution de toutes les conversations ;
- interdire les mises à jour forcées et la suppression de la branche ;
- appliquer les règles également aux administrateurs ;
- exiger que la branche soit à jour avant la fusion.

## Contrôles obligatoires

Les noms exacts doivent être sélectionnés après leur première exécution :

- `Flutter CI / validate` ;
- `Supabase migration guard / validate-local-migrations` lorsqu’une migration est modifiée ;
- les éventuels tests Supabase locaux configurés dans la pull request.

Le déploiement GitHub Pages ne démarre plus directement sur un push. Il attend la réussite de `Flutter CI` sur `main`.

## Filet de sécurité supplémentaire

Le workflow Flutter vérifie qu’un commit poussé sur `main` est associé à une pull request fusionnée. Un push direct fait échouer la CI et ne peut donc pas déclencher le déploiement Pages.

Cette vérification complète la protection GitHub, mais ne la remplace pas : seule une règle de branche empêche réellement l’écriture directe avant qu’elle se produise.

## Branches

Le réglage GitHub « Automatically delete head branches » est activé depuis le
6 novembre 2026 : la branche d’une pull request fusionnée est supprimée
automatiquement.

Les branches restantes (pull requests fermées sans fusion, branches poussées
sans pull request) se retirent avec le workflow manuel **Ménage des branches**
(`.github/workflows/branch_cleanup.yml`, règles dans
`tool/branch_cleanup.py`) :

- mode « analyse » (par défaut) : liste ce qui serait fait, sans rien modifier ;
- mode « appliquer » : supprime les branches déjà fusionnées ou identiques à
  la tête d’une pull request (restaurables depuis la page de la pull request),
  et archive les autres sous `refs/archive/<nom>` avant de les retirer.

Ne sont jamais touchées : la branche par défaut, les pull requests ouvertes et
les branches modifiées depuis moins de trois jours. Pour ressortir une branche
archivée : `git fetch origin refs/archive/<nom>:refs/heads/<nom>`, puis la
republier.
