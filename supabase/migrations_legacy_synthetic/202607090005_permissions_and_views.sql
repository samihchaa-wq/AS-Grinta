grant update(role, status, is_goalkeeper, updated_at)
on public.profiles to authenticated;

grant update(first_name, last_name, photo_url, updated_at)
on public.profiles to authenticated;

grant select on public.v_match_prediction_points to authenticated;
grant select on public.v_player_season_stats to authenticated;
grant select on public.v_player_career_stats to authenticated;
grant select on public.v_season_prediction_points to authenticated;
grant select on public.v_classement_general to authenticated;

revoke all on public.v_match_prediction_points from anon;
revoke all on public.v_player_season_stats from anon;
revoke all on public.v_player_career_stats from anon;
revoke all on public.v_season_prediction_points from anon;
revoke all on public.v_classement_general from anon;
