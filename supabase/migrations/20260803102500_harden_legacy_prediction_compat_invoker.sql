-- The legacy 4-argument prediction RPC exists only to keep stale clients working.
-- It delegates to the guarded 3-argument RPC and must not run with definer rights.

alter function public.save_match_prediction(uuid, integer, integer, boolean)
security invoker;

revoke all on function public.save_match_prediction(uuid, integer, integer, boolean)
from public, anon;

grant execute on function public.save_match_prediction(uuid, integer, integer, boolean)
to authenticated;
