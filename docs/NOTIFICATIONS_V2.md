# Notifications — contrat actuel

Ce document décrit uniquement le comportement actuel de production.
Les anciennes migrations peuvent conserver des types et règles historiques.

## Notifications essentielles

Ces notifications n’ont pas de réglage individuel dans l’application. Elles
nécessitent toutefois que le Web Push soit autorisé sur l’appareil.

- **Ouverture des disponibilités** : J-6 à 12 h, heure Europe/Paris.
- **Match annulé** : pendant la fenêtre active du match.
- **Date du match modifiée** : les disponibilités sont remises à `no_response`
  lorsqu’elles doivent être redemandées.
- **Heure du match modifiée** : les disponibilités existantes sont conservées.

Il n’existe plus de rappel automatique de disponibilité à J-3 ou J-1.
Le rappel manuel du staff reste disponible.

## Notifications facultatives

Les réglages utilisateur actuels couvrent notamment :

- **Pronostics** : rappel à J-5 à 12 h Europe/Paris si aucun pronostic n’est
  rempli ; aucun rappel n’est envoyé après T-15.
- **Homme du match** : le même réglage couvre l’ouverture du vote et son
  résultat.
- **Convocations** : notification lorsqu’un joueur passe de la liste d’attente
  vers les convoqués selon le workflow actuel.

## Vote Homme du match

Le vote n’est plus ancré à H+1 h 45.

Le fonctionnement actuel est :

1. le match est validé via le workflow post-match / Live ;
2. `match_sport_finalizations.validated_at` devient l’ancre du scrutin ;
3. le vote ouvre après cette validation ;
4. il reste ouvert pendant **24 heures**.

La clôture produit ensuite le résultat du vote.

### Notification d’ouverture

Les utilisateurs concernés ayant activé le réglage HDM reçoivent la notification
d’ouverture du vote.

### Notification de résultat

Le résultat utilise le même réglage `notify_motm_vote` :

- les autres utilisateurs concernés reçoivent « X a été élu Homme du match ! » ;
- l’élu lié à un compte reçoit « Bravo, tu as été élu Homme du match ! » ;
- en cas d’égalité, les textes utilisent la notion de co-Homme(s) du match ;
- un invité sans compte peut être annoncé dans le résultat mais ne reçoit pas de
  push personnel ;
- un utilisateur ayant désactivé le réglage HDM ne reçoit ni l’ouverture ni le
  résultat.

Le traitement prévoit aussi un rattrapage afin qu’un échec temporaire de
livraison ne supprime pas définitivement le résultat à envoyer.

## Automatismes retirés

Les automatismes suivants ne font plus partie du produit actuel :

- rappel disponibilité J-3 ;
- rappel disponibilité J-1 ;
- ancien rappel pronostic H-2 ;
- notification automatique du score final ;
- rappel HDM avant fermeture ;
- ancien événement `new_match`.

Les anciens types peuvent rester dans l’historique de migrations ou d’audit sans
être encore générés par le système actuel.

## Coupe-circuit global

`notifications_paused` reste prioritaire sur les envois lorsqu’il est activé.

Ce coupe-circuit ne doit pas arrêter les transitions métier : les disponibilités,
le cycle du match et les autres états continuent d’évoluer normalement même si
les push sont temporairement suspendus.

Sa valeur est opérationnelle et peut changer. Elle doit toujours être lue dans
la production au moment d’un audit.

## Principe technique

Les déclencheurs automatiques sont principalement portés côté serveur afin que
les mêmes règles s’appliquent quelle que soit l’interface ayant modifié le match.
