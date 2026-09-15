# Une notification attend désormais vingt-quatre heures, pas une

Correctif du 15 septembre 2026.

## Le problème, vu par un joueur

Chaque notification partait avec une durée de vie d'une heure. Si le téléphone
n'était pas joignable pendant cette heure — éteint, en avion, dans le métro, ou
simplement hors réseau — le service de notification jetait le message. Rien ne
le rattrapait ensuite : le destinataire ne saurait jamais qu'on avait cherché à
le joindre.

Le défaut était invisible côté administration. Le journal d'envoi affiche un
succès dans les deux cas, parce que le service de notification avait bien
accepté le message. « Accepté » ne veut pourtant pas dire « affiché sur le
téléphone ».

Constaté le 15 septembre 2026 : un joueur n'a pas reçu l'ouverture des
disponibilités de midi, alors qu'il avait reçu sans problème celle de la semaine
précédente. Même appareil, même abonnement, même envoi réussi à la même heure.
La seule différence possible était la joignabilité de son téléphone pendant
l'heure qui suivait.

## Ce qui change

La durée de vie passe d'une heure à vingt-quatre heures, pour toutes les
notifications de l'application.

Quelqu'un dont le téléphone était coupé à midi reçoit désormais la notification
en le rallumant le soir, ou le lendemain matin.

## Pourquoi vingt-quatre heures, et pas plus

Aucune de nos notifications n'est urgente à la minute près : l'ouverture des
disponibilités prévient six jours avant le match, et la plus serrée annonce un
match le lendemain. Les relances de disponibilité se répètent d'elles-mêmes à
J-3 et J-1.

Au-delà d'une journée, un message deviendrait trompeur plutôt qu'utile : une
ouverture de disponibilités reçue trois jours après coup n'aide personne.

## Ce qui ne change pas

Le nombre de tentatives d'envoi, la suppression des abonnements expirés et le
journal de livraison sont inchangés. Ce réglage ne concerne que le temps
pendant lequel le service de notification conserve un message destiné à un
appareil injoignable.

## Vérifications faites

`supabase/functions/send-push/delivery_policy_test.ts` fige la valeur, pour
qu'un retour à une heure ne passe pas inaperçu. Les 21 tests Deno de la
fonction d'envoi ont été exécutés et passent. Le contrat de sécurité des Edge
Functions a été rejoué et passe également.
