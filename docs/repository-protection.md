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
