alter table public.matches
  drop constraint if exists matches_opponent_id_fkey;

alter table public.matches
  add constraint matches_opponent_id_fkey
  foreign key (opponent_id)
  references public.opponents(id)
  on delete restrict;

alter table public.matches
  drop constraint if exists matches_season_id_fkey;

alter table public.matches
  add constraint matches_season_id_fkey
  foreign key (season_id)
  references public.seasons(id)
  on delete restrict;

alter table public.season_players
  drop constraint if exists season_players_season_id_fkey;

alter table public.season_players
  add constraint season_players_season_id_fkey
  foreign key (season_id)
  references public.seasons(id)
  on delete restrict;

alter table public.season_predictions
  drop constraint if exists season_predictions_season_id_fkey;

alter table public.season_predictions
  add constraint season_predictions_season_id_fkey
  foreign key (season_id)
  references public.seasons(id)
  on delete restrict;
