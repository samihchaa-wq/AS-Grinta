-- Emergency rollback for 20260719010000_harden_public_rpc_execute_privileges.sql.
--
-- WARNING: this intentionally restores the former PUBLIC/anon exposure and
-- should only be used to recover from an unexpected compatibility problem.

grant execute on function public.featured_badges()
  to public, authenticated, service_role;

grant execute on function public.profile_badge_stars(uuid)
  to public, authenticated, service_role;

grant execute on function public.staff_list_historical_players()
  to public, authenticated, service_role;

grant execute on function public.staff_set_historical_profile(uuid, bigint)
  to public, authenticated, service_role;
