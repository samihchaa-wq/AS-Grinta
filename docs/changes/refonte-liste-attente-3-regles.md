# Refonte de la liste d'attente — contrat métier (novembre 2026)

> Branche de travail. **Aucune migration sur la production ni activation du nouveau moteur sans tests.**

## Les seules règles métier

1. **Priorité des convocations** — Pour un match et un quota X, les convoqués sont exactement les `min(X, présents)` joueurs déclarés présents ayant les positions les plus basses (numéros les plus élevés) dans la liste d'attente.
2. **Passages en attente** — Chaque joueur ayant figuré au moins une fois en attente entre **J−1 à 12 h, heure de Paris**, et le coup d'envoi acquiert **un seul +1** pour ce match, même s'il redevient convoqué ou absent avant le coup d'envoi. Le +1 est comptabilisé au coup d'envoi. Aucun +1 en cas d'annulation, de report, ou lorsque le quota a été ajusté pour accueillir tous les présents.
3. **Ordre de la liste** — Tri ascendant par (a) total des passages en attente, (b) matchs joués lors de la saison précédente, (c) ordre alphabétique du nom, puis prénom. Un identifiant stable départage une homonymie parfaite.

## Contrôle de l'administrateur (décisions du 8 novembre 2026)

- **Liste d'attente — boutons +/−** : l'administrateur peut ajouter ou retirer un +1 à un joueur (inscrit au journal d'audit). Le classement est recalculé aussitôt selon la règle 3 et les convocations des prochains matchs suivent. L'écran montre le nouvel ordre quand on tire la liste vers le bas ou qu'on revient sur la page. Pas de glisser-déposer ni de bouton « Enregistrer », « Recalculer » ou « Actualiser ».
- **Effectif — choix par match** : comme avant la refonte, l'administrateur peut glisser un joueur dans « Convoqués » ou « En attente » pour un match. Ce choix est conservé par les recalculs : un joueur forcé convoqué prend une place, un joueur forcé en attente en libère une ; les autres suivent la règle 1. Le choix s'efface si la disponibilité du joueur change (il répond, se désiste, revient, ou l'admin le déclare absent). Un joueur forcé en attente pendant le créneau de la règle 2 gagne son +1, comme tout joueur en attente.
- **Retri automatique de la liste** : à chaque +1 attribué au coup d'envoi, annulé (match annulé, reporté, quota élargi) ou corrigé à la main.
- **Mise en ligne sans effet rétroactif** : l'ordre actuel de la liste et les compteurs sont conservés tels quels. Ils servent de point de départ pour la saison en cours : le classement se fait d'abord sur les +1 gagnés depuis la mise en ligne, puis sur l'ordre de départ, puis sur les critères de la règle 3. Les compteurs affichés restent les totaux de la saison. Aucun +1 n'est crédité pour un match joué avant la mise en ligne.
- Une liste toute neuve (nouvelle saison) est triée selon la règle 3, sans point de départ. Un joueur ajouté en cours de saison passe après les joueurs du point de départ à nombre de +1 égal.
- **Matchs « entre nous »** : inchangés, tous les présents sont convoqués.

## Invariants techniques obligatoires

- En amont du verrouillage, aucune dérogation individuelle ni ancien état de promotion ne peut déroger à la règle 1 ; l'administrateur agit uniquement sur l'ordre de la liste et les compteurs.
- L'effectif déjà verrouillé à l'ouverture du Live (T−15) ne se recompose pas lorsque les +1 sont attribués au coup d'envoi.
- Les transitions de l'état `not_convoked` sont enregistrées **en tant qu'événement**, indépendamment du statut final du joueur.
- L'attribution d'un +1 est **transactionnelle et idempotente**, avec une unicité `(match_id, season_player_id)`.
- Le compteur affiché et celui utilisé pour classer les joueurs doivent être la même donnée (pour la saison en cours, le classement en retire la valeur mémorisée à la mise en ligne).
- Les notifications de promotion/rétrogradation conservent leur fonctionnement uniquement sur un changement réel du statut calculé.
- Les données et statistiques de production sont conservées; aucun effacement sans migration justifiée et sauvegarde.

## Problèmes du moteur actuel observés

- `private.finalize_match_waitlist_turns_internal` déplace les joueurs vers la dernière position, sans incrémenter `manual_waitlist_count`, pourtant utilisé par l'interface pour « Recalculer ».
- `private.recompute_match_convocations_internal` sanctuarise `convocation_manual_override`, qui peut faire passer une décision arbitraire avant la priorité de la liste.
- `private.handle_convoked_withdrawal` et `private.restore_returning_convoked_player` opèrent des promotions et des retours particuliers au lieu de s'appuyer systématiquement sur le même calcul.
- Le RPC `private.get_sport_waitlist` ne renvoie pas le champ `current_season_waitlist_count`, alors que le modèle Dart attend ce champ.
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
- Examiner les invités. Les matchs « entre nous » gardent volontairement leur exception : tous les présents sont convoqués.
