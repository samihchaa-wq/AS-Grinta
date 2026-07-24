-- L'écran Effectif lit profiles.photo_url via une jointure directe. Sans droit
-- de lecture au niveau colonne, PostgREST renvoie « permission denied for
-- column photo_url », affiché comme « Tu n'as pas les droits pour cette
-- action ». photo_url pointe vers un bucket public : l'exposer en lecture est
-- sans risque et aligne la colonne avec les autres colonnes lisibles
-- (id, first_name, status, surnom).
grant select (photo_url) on public.profiles to authenticated;
