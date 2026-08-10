-- The public MOTM RPC wrappers are SECURITY INVOKER and delegate to private
-- SECURITY DEFINER implementations containing the actual authorization checks.
-- Their private delegates must therefore be executable by signed-in members.

grant execute on function private.get_match_motm_vote(uuid) to authenticated;
grant execute on function private.cast_match_motm_vote(uuid, uuid) to authenticated;
grant execute on function private.admin_cancel_match_motm_vote(uuid, text) to authenticated;
grant execute on function private.admin_restart_match_motm_vote(uuid, text) to authenticated;
