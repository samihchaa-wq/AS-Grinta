-- The public compatibility wrapper is intentionally not executable by
-- authenticated users. RLS policies in this project use the guarded private
-- SECURITY DEFINER helper instead.

-- Match the global public-table security floor: every business table has a
-- restrictive active-profile policy, then its operation-specific policies.
drop policy if exists active_authenticated_profile_only
  on public.season_prediction_roster_captures;
create policy active_authenticated_profile_only
  on public.season_prediction_roster_captures
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

drop policy if exists season_prediction_roster_captures_read
  on public.season_prediction_roster_captures;
create policy season_prediction_roster_captures_read
  on public.season_prediction_roster_captures
  for select to authenticated
  using ((select private.is_active_profile()));

drop policy if exists active_authenticated_profile_only
  on public.season_prediction_roster_members;
create policy active_authenticated_profile_only
  on public.season_prediction_roster_members
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

drop policy if exists season_prediction_roster_members_read
  on public.season_prediction_roster_members;
create policy season_prediction_roster_members_read
  on public.season_prediction_roster_members
  for select to authenticated
  using ((select private.is_active_profile()));
