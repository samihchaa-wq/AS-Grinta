-- Restore only the profile columns required by authenticated app flows.
-- Sensitive fields such as email, role, password flags and full third-party
-- surnames remain inaccessible through direct table reads.

revoke all on table public.profiles from authenticated;

grant select (id, first_name, surnom, status)
  on table public.profiles to authenticated;

grant update (first_name, last_name, updated_at)
  on table public.profiles to authenticated;

-- Cover foreign keys reported by the Supabase performance advisor.
create index if not exists match_player_stats_season_player_id_idx
  on public.match_player_stats(season_player_id);

create index if not exists season_players_season_id_idx
  on public.season_players(season_id);

create index if not exists season_predictions_season_player_id_idx
  on public.season_predictions(season_player_id);
