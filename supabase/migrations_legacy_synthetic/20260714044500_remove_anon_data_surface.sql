-- Profiles are created exclusively by the auth trigger or trusted admin flows.
revoke insert on table public.profiles from authenticated;
drop policy if exists insert_own_profile on public.profiles;

-- The application has no unauthenticated data screens. Remove stale anonymous
-- grants from analytical views, even where underlying RLS already blocked rows.
revoke select on table public.v_match_prediction_points from anon;
revoke select on table public.v_player_season_stats from anon;
revoke select on table public.v_scorer_standings from anon;
revoke select on table public.v_season_match_count from anon;
revoke select on table public.v_season_prediction_bonus from anon;
revoke select on table public.v_x2_wallet from anon;
