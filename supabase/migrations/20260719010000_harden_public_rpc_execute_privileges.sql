-- Phase 1 security hardening.
--
-- These SECURITY DEFINER functions must never inherit PostgreSQL's default
-- EXECUTE privilege for PUBLIC. The application keeps the same behaviour for
-- authenticated users and the service role.

revoke execute on function public.featured_badges()
  from public, anon;
grant execute on function public.featured_badges()
  to authenticated, service_role;

revoke execute on function public.profile_badge_stars(uuid)
  from public, anon;
grant execute on function public.profile_badge_stars(uuid)
  to authenticated, service_role;

revoke execute on function public.staff_list_historical_players()
  from public, anon;
grant execute on function public.staff_list_historical_players()
  to authenticated, service_role;

revoke execute on function public.staff_set_historical_profile(uuid, bigint)
  from public, anon;
grant execute on function public.staff_set_historical_profile(uuid, bigint)
  to authenticated, service_role;
