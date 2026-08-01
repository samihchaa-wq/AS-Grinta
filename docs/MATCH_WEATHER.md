# Météo du prochain match

La météo est un enrichissement non bloquant du **Prochain match**.

## Fenêtre

- avant J-6 : aucune météo n'est demandée ni affichée ;
- de J-6 au coup d'envoi : le cache serveur est éligible ;
- après le coup d'envoi ou si le match n'est plus `a_venir` : aucun rafraîchissement.

## Source et cadence

Le serveur utilise Open-Meteo. Un réveil Supabase toutes les 15 minutes demande au worker interne de traiter uniquement les matchs dont le cache est réellement dû :

- plus de 72 h avant le match : 12 h ;
- de 72 h à 24 h : 6 h ;
- de 24 h à 6 h : 2 h ;
- dans les 6 dernières heures : 1 h.

Les téléphones n'appellent jamais Open-Meteo directement. Ils lisent `match_weather` et reçoivent ses changements via Realtime.

## Lieu

L'ordre de résolution est :

1. adresse enregistrée sur le match ;
2. à domicile, adresse du club ;
3. à l'extérieur, adresse mémorisée de l'adversaire.

Les coordonnées géocodées sont conservées dans le cache et réutilisées tant que l'adresse ne change pas.

## Résilience

Une erreur de géocodage ou d'API météo ne bloque jamais un match. La dernière prévision valide reste intacte. Un changement d'adresse ou de coup d'envoi invalide le cache et force une nouvelle prévision au prochain cycle serveur.

## Interface

La carte affiche la température au coup d'envoi, le ressenti, pluie, vent, rafales, humidité et trois créneaux horaires pertinents. L'Indice Grinta est calculé localement et reste prudent en cas de conditions potentiellement dangereuses.
