-- Ordre d'affichage manuel de l'effectif (l'admin saisit les joueurs dans
-- l'ordre de son choix, ex. par nombre de matchs joués).
alter table public.season_players add column if not exists position integer;
