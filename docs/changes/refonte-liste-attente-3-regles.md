# Liste d'attente — contrat métier

## Évolution du 15 novembre 2026 : +1 exclusivement manuels

Décision du propriétaire : les +1 sont gérés à 100 % par l'administration.
Ce contrat remplace la règle de crédit automatique introduite par la PR #1571.
Il prend effet en production après application de la nouvelle migration
`20261115125239_waitlist_credits_admin_only.sql`.

### 1. Convocations et désistements

- Pour un quota X, les joueurs présents ayant les numéros les plus élevés
  dans la liste générale sont prioritaires, dans la limite des places libres.
- Désistements et retours passent par le même calcul de convocation.
- Les décisions manuelles par match sont conservées : un joueur forcé
  convoqué prend une place, un joueur forcé en attente est exclu du calcul
  automatique. Un joueur présent qui se désiste perd cette décision manuelle.
- Le coach est hors quota. Les matchs « entre nous » conservent leur exception :
  tous les présents sont convoqués.
- L'effectif est verrouillé à l'ouverture du Live, à T−15.
- Une notification de convocation ou de mise en attente correspond à un
  changement réel du statut ; modifier un compteur ne notifie pas à lui seul.

### 2. Compteurs de passages en attente

- Seul un administrateur actif peut ajouter ou retirer un +1, depuis les
  boutons +/− de la liste d'attente (`admin_set_waitlist_manual_count`).
- Le compteur ne peut pas être négatif ; chaque modification reste auditée.
- Aucun +1 n'est ajouté automatiquement, ni à J−1 midi, ni au coup d'envoi,
  ni à la validation d'un match, ni à l'ouverture de la liste par l'admin.
- Aucun +1 n'est retiré automatiquement : une annulation, un report, un
  changement de quota ou de disponibilité ne modifie pas le compteur.
- Les compteurs, l'ordre existant et les journaux historiques sont conservés
  lors de la migration. Aucun ancien crédit en attente n'est rattrapé.
- La tâche `as-grinta-waitlist-credit-v2` est désinscrite. Les anciennes
  fonctions de finalisation et de révocation restent compatibles et renvoient
  0 sans modifier les compteurs ni le journal des anciens crédits.

### 3. Classement

- Chaque modification manuelle du compteur recalcule le classement et les
  convocations des prochains matchs qui ne sont pas encore verrouillés.
- Pour la saison déjà ouverte lors de la refonte, le tri conserve le point
  de départ du 10 novembre : écart entre le compteur actuel et le compteur
  initial, puis ordre initial, puis les critères ci-dessous.
- Une nouvelle saison est classée par compteur croissant, nombre de matchs
  joués la saison précédente croissant, puis nom et prénom alphabétiques.
  Un identifiant stable départage les homonymes.
- Un joueur ajouté en cours de saison passe après les joueurs du point de
  départ à écart de compteur égal.
- Le compteur affiché est celui utilisé par le calcul, après déduction du
  compteur initial pour la saison ayant un point de départ.
- La liste générale n'a plus de glisser-déposer ni de boutons Enregistrer,
  Recalculer ou Actualiser. Après un +/−, l'écran affiche le nouvel ordre
  lorsqu'on tire la liste vers le bas ou qu'on revient sur la page.

## Validation avant déploiement

- Rejouer l'historique des migrations sur une base isolée et exécuter tous les
  tests pgTAP/RLS et le lint des fonctions.
- Vérifier les modifications admin et leur audit, le refus des comptes joueur,
  le maintien des priorités de convocation et le verrou T−15.
- Vérifier qu'aucun appel historique, crédit en attente, report, annulation
  ou changement de quota ne modifie automatiquement les compteurs.
- Inspecter l'état réel et les migrations de production avant déploiement.
  Ne pas modifier le verrou de production pour masquer une dérive.
