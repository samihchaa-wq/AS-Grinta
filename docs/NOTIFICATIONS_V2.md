# Notifications V2

Ce document décrit le contrat fonctionnel des notifications AS Grinta.

## Notifications essentielles

Ces notifications ne disposent d'aucun réglage de désactivation dans l'application. Elles nécessitent toutefois que le navigateur ou le système ait autorisé le Web Push.

- **Ouverture des disponibilités** : J-6 à 12 h, heure Europe/Paris.
- **Match annulé** : si l'annulation intervient entre J-6 à 12 h et le coup d'envoi.
- **Date du match modifiée** : dans la même fenêtre. Les disponibilités sont remises à `no_response` et doivent être renseignées à nouveau.
- **Heure du match modifiée** : dans la même fenêtre. Les disponibilités existantes sont conservées.

Il n'existe plus de rappel automatique de disponibilité à J-3 ou J-1. Le rappel manuel administrateur reste disponible.

## Notifications facultatives

Chaque utilisateur dispose de trois préférences indépendantes :

- **Pronostics** : rappel à J-5 à 12 h Europe/Paris si aucun pronostic n'est rempli.
- **Vote Homme du match** : notification à l'ouverture du vote.
- **Convocations** : notification lorsqu'un joueur passe de la liste d'attente (`not_convoked`) à `convoked` après publication des convocations.

## Vote Homme du match

Le vote ouvre au premier événement valide parmi :

1. validation du récapitulatif Live par le coach ;
2. validation des Stats/finalisation du match par un administrateur ou modérateur ;
3. à défaut, deux heures après le coup d'envoi.

Le vote ne peut jamais ouvrir avant le coup d'envoi. À H+2, son ouverture ne dépend pas d'une publication de composition ou d'une finalisation préalable : dès qu'un bulletin de vote valide peut être constitué, le scrutin est créé et ouvert.

La fermeture est fixe à **H+24 après le coup d'envoi**, quelle que soit l'heure à laquelle le vote s'est ouvert. Une validation rapide après le match donne donc une fenêtre de vote plus longue qu'une ouverture automatique à H+2.

## Notifications supprimées

Les envois automatiques suivants ne font plus partie du contrat :

- rappel disponibilité J-3 ;
- rappel disponibilité J-1 ;
- rappel pronostic H-2 ;
- notification automatique du score final ;
- rappel Homme du match avant fermeture ;
- notification automatique du résultat Homme du match ;
- ancien événement `new_match`.

Les anciens types peuvent rester présents dans l'historique d'audit, mais ils ne doivent plus pouvoir être créés par de nouveaux traitements.

## Exploitation

Le coupe-circuit global `notifications_paused` reste prioritaire sur tout envoi. Il ne suspend pas les transitions métier : les disponibilités continuent donc à s'ouvrir et se fermer aux heures prévues, même lorsque les push sont en pause. Les tâches planifiées ne doivent pas consommer définitivement un événement à envoyer lorsque ce coupe-circuit est actif.

Les déclencheurs automatiques sont portés par la base afin que les mêmes règles s'appliquent quelle que soit l'interface utilisée pour modifier un match.
