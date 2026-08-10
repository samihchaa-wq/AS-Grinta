-- Public SECURITY INVOKER wrappers need EXECUTE on their private SECURITY
-- DEFINER entry points. Authorization and feature-flag checks remain inside
-- those private functions; tables and raw ballots stay inaccessible.

grant execute on function private.get_match_motm_vote(uuid)
  to authenticated, service_role;
grant execute on function private.cast_match_motm_vote(uuid, uuid)
  to authenticated, service_role;
grant execute on function private.admin_cancel_match_motm_vote(uuid, text)
  to authenticated, service_role;
grant execute on function private.admin_restart_match_motm_vote(uuid, text)
  to authenticated, service_role;

grant execute on function public.get_match_motm_vote(uuid)
  to authenticated, service_role;
grant execute on function public.cast_match_motm_vote(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.admin_cancel_match_motm_vote(uuid, text)
  to authenticated, service_role;
grant execute on function public.admin_restart_match_motm_vote(uuid, text)
  to authenticated, service_role;
