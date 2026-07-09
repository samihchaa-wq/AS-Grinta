create or replace function public.mark_live_reconnected(
  p_match_id uuid,
  p_controller_session_id text
)
returns boolean
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  affected integer;
begin
  update public.live_sessions
  set controller_disconnected_at=null,
      updated_at=now()
  where match_id=p_match_id
    and controller_profile_id=auth.uid()
    and controller_session_id=public.live_session_token_hash(
      p_controller_session_id
    );

  get diagnostics affected=row_count;
  return affected=1;
end;
$$;

revoke execute on function public.mark_live_reconnected(uuid,text)
from public;
revoke execute on function public.mark_live_reconnected(uuid,text)
from anon;
grant execute on function public.mark_live_reconnected(uuid,text)
to authenticated;
