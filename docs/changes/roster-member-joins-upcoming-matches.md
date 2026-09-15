# Un membre ajouté à l'effectif rejoint les matchs déjà programmés

Correctif du 15 septembre 2026.

## Le problème, vu par un joueur

La liste des participants d'un match est construite une seule fois, au moment
où l'administrateur configure le match, à partir de l'effectif de cet
instant-là. Ensuite, plus rien ne la complète.

Résultat : quelqu'un inscrit dans l'effectif après la programmation d'un match
n'existait pas pour ce match. Pas « exclu » : invisible. Il ne recevait pas la
demande de disponibilité, ne pouvait pas répondre présent, n'était pas relancé,
n'était pas convocable, et n'apparaissait pas dans l'effectif.

Rien ne le signalait. Ni à lui, ni aux administrateurs. Le seul rattrapage
existant était involontaire : rouvrir le match en modification et re-régler
l'ouverture des disponibilités reconstruisait la liste au passage.

Constaté en production sur le coach arrivé dans l'effectif le 31 août : il
manquait sur les deux matchs programmés avant son arrivée. Ses deux lignes
manquantes ont été créées à la main le 15 septembre ; ce correctif traite la
cause.

## Ce qui change

Entrer dans l'effectif rattache automatiquement aux matchs à venir.

- **Arrivée dans l'effectif** : la personne reçoit immédiatement sa ligne de
  participation sur tous les matchs à venir déjà programmés.
- **Retour dans l'effectif** après une absence : elle récupère les lignes des
  matchs programmés pendant son absence.

Le sens de « joueur de rotation » reste celui fixé le 15 septembre 2026 par le
changement du rôle Coach : un coach reçoit bien sa ligne de participation, hors
rotation, donc il est notifié et il répond, sans consommer de place.

## Ce qui ne change pas

Le correctif est volontairement étroit : il ne fait que créer des lignes
manquantes. Il n'en modifie ni n'en supprime aucune.

- **Sortir de l'effectif ne touche à rien.** Un membre désactivé reste dans
  l'instantané des matchs où il figurait déjà, avec la réponse qu'il avait
  donnée. C'est une garantie existante du produit : un joueur désactivé après
  coup reste finalisable sur son match. Retirer quelqu'un de la rotation reste
  le geste explicite d'un administrateur qui resynchronise le match.
- **Les matchs passés ne sont jamais touchés.** Leur liste de participants
  reste exactement telle qu'elle a été jouée et validée.
- **Les matchs d'une autre saison** ne sont jamais complétés par l'effectif
  d'une saison voisine.
- **Un match sans module sportif configuré** ne reçoit aucune liste : on ne
  crée jamais une liste d'un seul membre là où il n'y en avait aucune.
- Le quota de convoqués, la liste d'attente et la composition sont inchangés.
  Une arrivée démarre sans réponse, donc elle ne convoque personne toute seule.

## Rattrapage à l'installation

La migration complète les matchs à venir déjà programmés, par création
uniquement. L'opération est sans effet sur une base déjà cohérente : au moment
de l'écriture de ce document, la production n'avait plus rien à rattraper.

## Vérifications faites

Le comportement a été rejoué sur le schéma réel de production, dans des
transactions annulées, sans rien y laisser :

- une arrivée non-coach reçoit ses lignes sur les trois matchs à venir, dans la
  rotation ;
- une arrivée coach reçoit les mêmes lignes, hors rotation ;
- aucune ligne n'est créée sur les matchs passés ;
- une désactivation ne modifie ni la rotation ni la réponse déjà donnée ;
- un retour dans l'effectif recrée la ligne manquante d'un match programmé
  pendant l'absence ;
- le rattrapage ne crée aucune ligne sur une base déjà cohérente.

Le scénario complet, y compris la notification d'ouverture des disponibilités
qui atteint enfin l'arrivée tardive, est couvert par
`supabase/tests/database/roster_member_joins_upcoming_matches.test.sql`, exécuté
par la CI sur une base reconstruite depuis l'historique canonique.

## Effet sur un décor de test existant

`supabase/tests/database/live_prekickoff_lineup_swap.test.sql` construisait son
décor dans cet ordre : match, workflow, puis effectif, puis participants aux
identifiants choisis à la main. Ces participants existent désormais déjà quand
le décor tente de les insérer. L'effectif y est donc constitué avant le match,
ce qui rend les identifiants choisis de nouveau libres. Aucune assertion du
test n'a été modifiée.
