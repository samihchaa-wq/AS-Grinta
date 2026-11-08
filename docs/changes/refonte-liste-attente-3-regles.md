# Refonte de la liste d'attente — contrat métier (novembre 2026)

> Branche de travail. **Aucune migration sur la production ni activation du nouveau moteur sans tests.**

## Les seules règles métier

1. **Priorité des convocations** — Pour un match et un quota X, les convoqués sont exactement les `min(X, présents)` joueurs déclarés présents ayant les positions les plus basses (numéros les plus élevés) dans la liste d'attente.
2. **Passages en attente** — Chaque joueur ayant figuré au moins une fois en attente entre **J−1 à 12 h, heure de Paris**, et le coup d'envoi acquiert **un seul +1** pour ce match, même s'il redevient convoqué ou absent avant le coup d'envoi. Le +1 est comptabilisé au coup d'envoi. Aucun +1 en cas d'annulation, de report, ou lorsque le quota a été ajusté pour accueillir tous les présents.
3. **Ordre de la liste** — Tri ascendant par (a) total des passages en attente, (b) matchs joués lors de la saison précédente, (c) ordre alphabétique du nom, puis prénom. Un identifiant stable départage une homonymie parfaite.

## Invariants techniques obligatoires

- En amont du verrouillage, aucune intervention administrative ni ancien état de promotion ne peut déroger à la règle 1.
- L'effectif déjà verrouillé à l'ouverture du Live (T−15) ne se recompose pas lorsque les +1 sont attribués au coup d'envoi.
- Les transitions de l'état `not_convoked` sont enregistrées **en tant qu'événement**, indépendamment du statut final du joueur.
- L'attribution d'un +1 est **transactionnelle et idempotente**, avec une unicité `(match_id, season_player_id)`.
- Le compteur affiché et celui utilisé pour classer les joueurs doivent être la même donnée.
- Les notifications de promotion/rétrogradation conservent leur fonctionnement uniquement sur un changement réel du statut calculé.
- Les données et statistiques de production sont conservées; aucun effacement sans migration justifiée et sauvegarde.

## Problèmes du moteur actuel observés

- `private.finalize_match_waitlist_turns_internal` déplace les joueurs vers la dernière position, sans incrémenter `manual_waitlist_count`, pourtant utilisé par l'interface pour « Recalculer ».
- `private.recompute_match_convocations_internal` sanctuarise `convocation_manual_override`, qui peut faire passer une décision arbitraire avant la priorité de la liste.
- `private.handle_convoked_withdrawal` et `private.restore_returning_convoked_player` opèrent des promotions et des retours particuliers au lieu de s'appuyer systématiquement sur le même calcul.
- Le RPC `private.get_sport_waitlist` ne renvoie pas le champ `current_season_waitlist_count`, alors que le modèle Dart attend ce champ.
- L'interface d'administration autorise un ordre manuel par glisser-déposer; ce comportement contredit le classement strict et doit être retiré ou remplacé par un recalcul.
- Les opérations d'administration peuvent conserver des dérogations; elles devront être redéfinies pour modifier uniquement les entrées des règles, pas les résultats.

## Points d'intégration à préserver

- Comptes joueurs, saison, coach (hors quota comme actuellement), invités, composition, Live, disponibilités, notification des mouvements, historique.
- Les signatures des RPC publiques jusqu'à migration du client; les anciennes API de dérogation devront retourner un refus explicite plutôt que créer des états incohérents.
- Les règles 1 et 2 utilisent la période du match en heure locale `Europe/Paris`, même lors des changements d'heure d'été.

## Plan d'exécution

1. Construire le nouvel historique d'éligibilité aux +1, puis la comptabilisation au coup d'envoi.
2. Remplacer le moteur de sélection par un seul recalcul déterministe et supprimer les dérogations manuelles.
3. Remplacer le déplacement arbitraire de la liste par un tri à partir des compteurs.
4. Adapter l'interface d'administration sans toucher aux autres écrans.
5. Tester (changements de disponibilité, promotion puis retrait, T−15, J−1 midi, report, annulation, quota, double exécution, égalité, notifications), auditer les migrations et ne déployer qu'après validation.

## Contrôles bloquants avant fusion

- Exécuter les tests SQL et Flutter, y compris les anciens tests métier qui peuvent nécessiter une adaptation explicite.
- Tester sur une base isolée copie de la structure de production, jamais sur la production.
- Vérifier `EXPLAIN`, la concurrence, les index et les droits des fonctions `SECURITY DEFINER`.
- Réconcilier les anciens compteurs avec l'historique avant migration.
- Examiner les invités et toute spécificité « entre nous » pour ne pas introduire d'exception implicite à la règle 1.
