alter view public.v_player_season_stats set (security_invoker = true);
alter view public.v_player_career_stats set (security_invoker = true);
alter view public.v_season_prediction_points set (security_invoker = true);
alter view public.v_classement_general set (security_invoker = true);

revoke all on function public.guard_match_prediction_window()
  from public, anon, authenticated;
revoke all on function public.assert_coach_event_allowed()
  from public, anon, authenticated;
