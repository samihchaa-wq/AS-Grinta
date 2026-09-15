# Le coach redevient un membre du club comme les autres

Décision produit du 15 septembre 2026.

Avant ce changement, cocher « Coach » retirait silencieusement des
fonctionnalités : plus aucune notification de disponibilité, absence du tableau
des disponibilités et de l'effectif, aucun bulletin de vote Homme du match. Le
coach pouvait répondre « présent » depuis l'application, mais sa réponse
n'apparaissait nulle part.

La case « Coach » ne retire plus rien. Elle dit seulement deux choses : le coach
pilote le Live des matchs de sa saison, et il n'est pas un joueur de rotation.

## Ce que le coach a désormais, comme tout le monde

- Toutes les notifications : ouverture des disponibilités, relances automatiques
  et manuelles, changement ou report de match, publication de la composition,
  ouverture du vote Homme du match.
- Sa disponibilité, visible dans le tableau des disponibilités et dans l'écran
  Effectif de l'administrateur, où un admin peut aussi la corriger et le
  relancer.
- Son bulletin de vote Homme du match dès qu'il est convoqué.
- Les pronostics et les « Statistiques Pronos », inchangés.

## Les trois seules différences qui restent

1. **Effectif oui, composition non.** Dès qu'il se dit présent, le coach entre
   dans l'effectif du match. Il n'y consomme aucune place : le nombre de
   joueurs convoqués et la limite d'effectif ne comptent que les joueurs. Il
   n'apparaît jamais dans la composition d'équipe, ni sur le terrain, ni sur le
   banc, ni en ajout tardif pendant le Live.
2. **Pas de rotation.** Il n'entre pas dans la liste d'attente, ne consomme
   aucun tour, et son absence ne fait monter personne. Il n'y a donc aucune
   décision d'effectif à prendre pour lui : sa seule réponse décide.
3. **Pas une ligne de joueur.** Il n'apparaît ni dans les « Statistiques
   Joueurs », ni parmi les candidats à l'Homme du match, ni parmi les cibles du
   pari de saison (buteurs / clean sheets).

## Comment c'est tenu côté serveur

Le drapeau `match_sport_participants.is_eligible` garde son sens : « joueur de
rotation ». Le coach reste à `false`, ce qui le tient hors de la liste
d'attente, du quota, de la composition, de l'alignement du Live et des
statistiques sans qu'aucune de ces règles ait à le connaître. Chaque
fonctionnalité qui doit l'inclure le nomme explicitement.

Deux fonctions portent la règle pour éviter qu'elle se disperse :

- `private.participant_is_coach(uuid)` ;
- `private.match_motm_voter_participant(uuid, uuid)`, qui désigne les mêmes
  votants pour la lecture du vote, le dépôt du vote et la notification.

Un garde-fou a été ajouté au passage : l'ajout d'un joueur en cours de Live
forçait `is_eligible = true` sur le participant ajouté. Un coach ajouté par
erreur serait donc devenu un joueur de rotation et aurait faussé ses
statistiques. Il n'est plus proposé dans la liste, et l'ajout est refusé s'il
est quand même demandé.

## Migration et vérification

- Migration canonique : `20260915093000_coach_is_a_regular_member.sql`.
- Rattrapage : sur les matchs à venir, la réponse déjà donnée par un coach est
  reprise telle quelle et le pose dans l'effectif sans qu'il ait à recliquer.
  Les matchs passés ne sont pas touchés.
- Test : `supabase/tests/database/coach_is_a_regular_member.test.sql`.
