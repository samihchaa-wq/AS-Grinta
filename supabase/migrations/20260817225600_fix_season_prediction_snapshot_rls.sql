-- The public compatibility wrapper is intentionally not executable by
-- authenticated users. RLS policies in this project use the guarded private
-- SECURITY DEFINER helper instead.

drop policy if exists season_prediction_roster_captures_read
  on public.season_prediction_roster_captures;
create policy season_prediction_roster_captures_read
  on public.season_prediction_roster_captures
  for select to authenticated
  using ((select private.is_active_profile()));

drop policy if exists season_prediction_roster_members_read
  on public.season_prediction_roster_members;
create policy season_prediction_roster_members_read
  on public.season_prediction_roster_members
  for select to authenticated
  using ((select private.is_active_profile()));
