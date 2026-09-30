# Les tâches de chaque minute ne font plus tout recharger

Correctif du 30 septembre 2026.

## Le problème, vu par un joueur

Le 28 septembre 2026, après le match, l'application est devenue très lente
pendant environ six minutes (de 23 h 08 à 23 h 14, heure de Paris) : jusqu'à
neuf secondes pour afficher un écran, alors qu'une dizaine de personnes
seulement étaient connectées.

## La cause

L'application se tient à jour grâce à un petit signal partagé
(`shared_data_change_signals`) : dès qu'une donnée change, chaque application
ouverte recharge ce qui la concerne.

Ce signal est incrémenté par des déclencheurs `FOR EACH STATEMENT`, qui
s'exécutent même quand une requête ne modifie aucune ligne. Or deux tâches
planifiées chaque minute lançaient leurs mises à jour sans condition préalable :

- `private.process_sport_availability_notifications` (deux `UPDATE` sur
  `match_sport_workflows`) ;
- `private.finish_due_internal_matches` (un `UPDATE` sur `matches`).

Résultat : trois révisions par minute, dont une non sportive, donc un
rechargement complet de chaque application connectée à chaque minute ronde,
toutes en même temps. Le compteur dépassait 324 000 révisions fin
septembre. Le soir du match, ces rechargements synchronisés se sont ajoutés
aux calculs d'après-match et ont saturé la base.

## Ce qui change

Chaque `UPDATE` n'est lancé que si au moins une ligne est concernée, avec
exactement les mêmes conditions. Le comportement métier et les valeurs
renvoyées sont inchangés. Une vraie ouverture, fermeture ou fin de match
continue de prévenir les applications.

Test : `supabase/tests/database/idle_cron_shared_data_signal.test.sql`.
