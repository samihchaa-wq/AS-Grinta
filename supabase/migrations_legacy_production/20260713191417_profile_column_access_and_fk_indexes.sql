revoke all on table public.profiles from authenticated;

grant select (id, first_name, surnom, status)
  on table public.profiles to authenticated;

grant update (first_name, last_name, updated_at)
  on table public.profiles to authenticated;

create index if not exists match_player_stats_season_player_id_idx
  on public.match_player_stats(season_player_id);

create index if not exists season_players_season_id_idx
  on public.season_players(season_id);

create index if not exists season_predictions_season_player_id_idx
  on public.season_predictions(season_player_id);;
