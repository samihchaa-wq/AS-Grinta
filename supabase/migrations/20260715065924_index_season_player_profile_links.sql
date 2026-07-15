create index if not exists season_players_profile_id_idx
  on public.season_players(profile_id)
  where profile_id is not null;
