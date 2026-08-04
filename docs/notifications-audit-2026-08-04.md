# Audit notifications — 2026-08-04

## Automatiques actives en production

- Disponibilité : ouverture à J-6 à 12h (Europe/Paris), essentielle.
- Disponibilité : relance manuelle du staff pour les joueurs sans réponse.
- Pronostic : rappel facultatif à J-5 à 12h si aucun prono n'est enregistré ; il ne part plus après T-15.
- Match : annulation, changement de date et changement d'heure.
- Convocation : notification facultative lors d'une promotion depuis la liste d'attente.
- HDM : notification facultative à l'ouverture du scrutin.

## Anciens automatismes confirmés absents

- Aucun rappel disponibilité J-3/J-1 automatique.
- Aucun rappel HDM automatique en fin de fenêtre.
- Aucun ancien push de score final/résultat validé.

## Correction de cet audit

Le résultat HDM avait été retiré lors d'un durcissement antérieur. Il est restauré avec le même réglage `notify_motm_vote` que l'ouverture du scrutin :

- les non-élus concernés reçoivent « X a été élu Homme du match ! » ;
- l'élu disposant d'un compte lié reçoit uniquement « Bravo, tu as été élu Homme du match ! » ;
- en cas d'ex aequo, les textes passent en « co-Homme(s) du match » ;
- un invité/non-lié peut être annoncé collectivement mais ne reçoit évidemment pas de push personnel ;
- un utilisateur ayant désactivé le réglage HDM ne reçoit ni l'ouverture ni le résultat ;
- le coupe-circuit global des notifications reste prioritaire.
