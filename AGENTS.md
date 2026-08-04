# AS-Grinta — instructions obligatoires pour les agents

## Source de vérité

La **production actuelle** est la référence fonctionnelle de AS Grinta.

Pour toute conclusion sur une fonctionnalité :

1. vérifier ce qui fonctionne réellement en production ;
2. vérifier le schéma et les objets Supabase distants ;
3. vérifier que le code GitHub actuel est réellement appelé ;
4. utiliser l’historique Git/PR uniquement pour comprendre pourquoi un élément existe.

Ne jamais conclure qu’une fonctionnalité existe simplement parce que son code est présent dans le dépôt.

Les migrations dans `supabase/migrations/` sont un historique immuable. Une migration appliquée ne doit jamais être modifiée, renommée ou supprimée, même si son comportement a depuis été remplacé.

**L’historique des fichiers GitHub et le registre de migrations Supabase ne sont pas historiquement 1:1.** Ne jamais tenter de les réaligner pendant un simple nettoyage en supprimant, renommant, rejouant ou marquant arbitrairement d’anciennes migrations. Avant tout déploiement SQL, inspecter l’état distant et traiter tout écart comme un sujet dédié.

La documentation explique le contrat attendu mais ne remplace jamais une vérification de production. Les documents courants de référence sont listés dans `README.md`.

## État fonctionnel actuel à préserver

- Rôles actifs : `pronostiqueur`, `admin` et `moderateur`.
- Le module `sports_management` est en production.
- Le module **Live** est actuel et utilisé : sessions, chronomètre, événements, remplacements et validation du récapitulatif font partie du produit.
- Un match entre dans « Prochain match » à **J-6 à 12 h**, heure Europe/Paris.
- Les disponibilités ouvrent à **J-6 à 12 h**.
- Les pronostics ferment à **T-15**.
- Le Live ouvre à **T-15**.
- Effectif et Composition sont gelés à **T-15**.
- Un match Live doit être validé avant son passage normal en match passé.
- Le vote Homme du match ouvre après la validation du compte rendu et reste ouvert **24 heures**.
- Un joueur ajouté tardivement au Live est ajouté directement sur le banc.
- Le réglage utilisateur HDM couvre l’ouverture du vote **et** son résultat.
- Le portefeuille / multiplicateur **×2 a été retiré du produit actuel**. Des migrations ou signatures de compatibilité peuvent encore en garder la trace.

Les valeurs opérationnelles comme les feature flags, le coupe-circuit des notifications, les crons ou les déploiements Edge peuvent changer : toujours les lire en production avant d’en conclure l’état.

## Classification de nettoyage

- **A — actuel et utilisé** : ne pas toucher ;
- **B — historique nécessaire** : conserver ;
- **C — code mort confirmé** : suppression possible ;
- **D — ancienne implémentation remplacée** : suppression possible après preuve d’absence de dépendance ;
- **E — doublon** : conserver l’implémentation actuelle ;
- **F — documentation/commentaire obsolète** : corriger ou supprimer ;
- **G — incertain** : ne rien supprimer.

**En cas de doute, ne pas supprimer.** Un nom `legacy`, `old`, `v2`, `v3`, une date ancienne ou un compteur d’utilisation nul ne constitue pas une preuve. Tenir compte des anciens clients, deep-links et contrats de compatibilité avant de retirer une RPC, une route ou une Edge Function.

## Règles techniques

- Supabase reste l’unique source de vérité pour les données métier.
- Ne jamais utiliser la clé `service_role` dans Flutter.
- Respecter Riverpod, `go_router` et l’architecture feature-first.
- Toute évolution de schéma passe par une **nouvelle migration additive ou corrective** ; ne jamais réécrire une migration appliquée.
- Avant chaque suppression, tracer références et dépendances.
- Faire des lots petits et cohérents.
- Après un lot Flutter : formatage, analyse, tests et build Web.
- Après un lot Supabase : installation du schéma isolé, tous les pgTAP/RLS et lint SQL.
- Ne jamais fusionner une PR dont les contrôles requis sont rouges.

## Verrou de migrations

`supabase/production_migrations.lock` représente l’état distant vérifié au moment de sa synchronisation : nombre de migrations, dernière version et empreinte.

Le workflow de garde contrôle ce verrou selon les événements configurés. Après un déploiement vérifié, la resynchronisation passe par le mécanisme dédié du dépôt ; une PR fonctionnelle ne doit jamais modifier le lock pour masquer une dérive.
