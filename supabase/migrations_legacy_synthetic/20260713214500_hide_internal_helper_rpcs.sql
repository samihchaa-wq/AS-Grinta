-- P0: helper functions used only inside privileged database code must not be
-- exposed as direct PostgREST RPC endpoints to authenticated clients.

revoke execute on function public.current_profile_role()
  from public, anon, authenticated;

revoke execute on function public.is_exact_moderator()
  from public, anon, authenticated;

revoke execute on function public.match_prediction_participant_count(uuid)
  from public, anon, authenticated;

-- Trusted server workflows retain explicit access.
grant execute on function public.current_profile_role() to service_role;
grant execute on function public.is_exact_moderator() to service_role;
grant execute on function public.match_prediction_participant_count(uuid)
  to service_role;
