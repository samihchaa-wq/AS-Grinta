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
- **Liste d’attente** : « Tu passes en liste d’attente » part à chaque entrée
  en liste d’attente, quelle qu’en soit l’origine : joueur déjà placé en
  attente quand l’effectif est publié pour la première fois, réponse
  « Présent » après la publication qui tombe directement en attente,
  convoqué qui perd sa place.
- **Convocation** : « Tu es convoqué » part quand un joueur passe de la liste
  d’attente aux convoqués. Entrer directement chez les convoqués (première
  publication ou réponse tardive) ne déclenche rien : c’est le résultat
  attendu.

Il n’existe plus de rappel automatique de disponibilité à J-3 ou J-1.
Le rappel manuel du staff reste disponible.

## Indisponibilité déclarée

Un joueur qui a déclaré une période d’indisponibilité sort de l’effectif
convocable pour les matchs dont le coup d’envoi tombe dans cette période. Il en
découle qu’il ne reçoit, pour ces matchs-là :

- ni l’ouverture des disponibilités ;
- ni les rappels manuels du staff, puisqu’ils ne visent que les réponses
  manquantes et que la sienne est déjà posée ;
- ni la convocation, puisqu’il n’est plus convocable ;
- ni la mise en ligne de la composition, y compris pour un match « entre nous »
  dont l’envoi couvre habituellement tout le club.

Le reste de la vie du club continue de lui parvenir normalement : rappel de
pronostic, vote Homme du match et son résultat, annonces de match. Annuler ou
raccourcir la période le remet dans le circuit, sans rattraper les
notifications déjà passées.

## Notifications facultatives

Les réglages utilisateur actuels couvrent notamment :

- **Pronostics** : rappel le jour du match à 16 h Europe/Paris si aucun
  pronostic n’est rempli ; jamais avant, et plus après 16 h 10 (rattrapage
  d’une exécution manquée) ni après T-15.
- **Homme du match** : le même réglage couvre l’ouverture du vote et son
  résultat.
- **Composition en ligne** : envoyée aux convoqués (à tout le club pour un
  match « entre nous »).
- **Badge débloqué**.
- **Changement de disponibilité d’un joueur** (administrateurs) : un joueur
  passe de présent à absent ou l’inverse.

L’ancien réglage « Passage en convoqué » n’est plus proposé ni lu : la
convocation et la liste d’attente sont devenues essentielles.

## Écran Notifications

- La cloche de l’encadré « Notifications essentielles » abonne ou désabonne
  **cet appareil**. Désabonné, l’appareil ne reçoit plus rien, pas même les
  notifications réglables.
- Les cloches réglables valent pour le compte, sur tous ses appareils. Quand
  cet appareil ne reçoit rien (désabonné, ou incapable de recevoir), elles
  sont grises et inactives, avec la mention « Coupées sur cet appareil » pour
  un appareil désabonné. Le réglage du compte est conservé et réapparaît dès
  le réabonnement.
- La cloche du haut reflète l’abonnement du navigateur. À chaque ouverture
  de l’application (lancement, connexion, retour au premier plan), cet
  abonnement est réenregistré sans rien demander : il est rattaché au compte
  connecté et redevient l’appareil le plus récent. Sans cela, la cloche
  pouvait rester verte alors que le serveur ne connaissait plus l’appareil
  (autre compte connecté sur le même téléphone, sixième appareil ayant
  remplacé le plus ancien).

## Journal de livraison

`push_delivery_log` garde une ligne par appareil et par envoi : succès ou
échec, code renvoyé par Apple ou Google, nombre d’essais. Les envois à
contenu préparé y figurent aussi, sous leur type (`convocation_promoted`,
`convocation_demoted`, `composition_published`, `motm_result_general`,
`motm_result_winner`, `badge_unlocked`) ; les messages libres et changements
de disponibilité sous `custom`, les tests sous `test`. Les badges et
messages libres n’ont pas de match.

« Livré » signifie accepté par Apple ou Google, pas affiché : un téléphone
injoignable plus de 24 heures, ou dont les notifications sont coupées dans
ses propres réglages, ne l’affichera pas.

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

## Écran ouvert par chaque notification

Toucher une notification ouvre l’écran qu’elle annonce :

| Notification | Écran |
| --- | --- |
| Ouverture des disponibilités, relance, match reporté | Calendrier, sur la carte du match (choix Présent / Absent) |
| Convocation | Fiche du match, Effectif |
| Composition en ligne | Fiche du match, Composition |
| Rappel pronostic | Fiche du match, Prono |
| Match annulé, horaire modifié | Fiche du match, Info |
| Coup d’envoi, buts, fin de match (Live) | Fiche du match, Live |
| Ouverture du vote Homme du match | Vote Homme du match |
| Résultat Homme du match | Fiche du match terminé |
| Badge(s) débloqué(s) | Armoire à badges |
| Nouveau compte en attente (admin) | Administration |
| Changement de disponibilité (admin) | Fiche du match, Effectif |
| Message libre d’un administrateur | Accueil |

La fiche du match reste soumise à ses règles habituelles : un onglet qui n’est
plus disponible (Prono après T-15, par exemple) bascule sur l’onglet prévu.
L’adresse est contrôlée par `send-push` : seule une route de l’application est
acceptée, toute autre valeur ouvre l’accueil.

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
