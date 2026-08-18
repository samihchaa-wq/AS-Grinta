-- AUD-006 follow-up: keep MOTM implementation private and expose only guarded public RPCs.
-- Public wrappers become SECURITY DEFINER boundaries with explicit authorization;
-- authenticated users no longer need EXECUTE on the private implementations.

create or replace function public.get_match_motm_vote(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.get_match_motm_vote(p_match_id);
end;
$function$;

create or replace function public.cast_match_motm_vote(
  p_match_id uuid,
  p_candidate_participant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.cast_match_motm_vote(p_match_id, p_candidate_participant_id);
end;
$function$;

create or replace function public.admin_get_match_motm_dashboard(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.get_admin_match_motm_dashboard(p_match_id);
end;
$function$;

create or replace function public.admin_list_match_motm_votes()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.list_admin_match_motm_votes();
end;
$function$;

create or replace function public.admin_cancel_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.admin_cancel_match_motm_vote(p_match_id, p_reason);
end;
$function$;

create or replace function public.admin_restart_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.admin_restart_match_motm_vote(p_match_id, p_reason);
end;
$function$;

create or replace function public.admin_close_match_motm_vote_early(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.admin_close_match_motm_vote_early(p_match_id, p_reason);
end;
$function$;

revoke execute on function private.get_match_motm_vote(uuid)
  from public, anon, authenticated;
revoke execute on function private.cast_match_motm_vote(uuid,uuid)
  from public, anon, authenticated;
revoke execute on function private.get_admin_match_motm_dashboard(uuid)
  from public, anon, authenticated;
revoke execute on function private.list_admin_match_motm_votes()
  from public, anon, authenticated;
revoke execute on function private.admin_cancel_match_motm_vote(uuid,text)
  from public, anon, authenticated;
revoke execute on function private.admin_restart_match_motm_vote(uuid,text)
  from public, anon, authenticated;
revoke execute on function private.admin_close_match_motm_vote_early(uuid,text)
  from public, anon, authenticated;

revoke execute on function public.get_match_motm_vote(uuid) from public, anon;
revoke execute on function public.cast_match_motm_vote(uuid,uuid) from public, anon;
revoke execute on function public.admin_get_match_motm_dashboard(uuid) from public, anon;
revoke execute on function public.admin_list_match_motm_votes() from public, anon;
revoke execute on function public.admin_cancel_match_motm_vote(uuid,text) from public, anon;
revoke execute on function public.admin_restart_match_motm_vote(uuid,text) from public, anon;
revoke execute on function public.admin_close_match_motm_vote_early(uuid,text) from public, anon;

grant execute on function public.get_match_motm_vote(uuid) to authenticated, service_role;
grant execute on function public.cast_match_motm_vote(uuid,uuid) to authenticated, service_role;
grant execute on function public.admin_get_match_motm_dashboard(uuid) to authenticated, service_role;
grant execute on function public.admin_list_match_motm_votes() to authenticated, service_role;
grant execute on function public.admin_cancel_match_motm_vote(uuid,text) to authenticated, service_role;
grant execute on function public.admin_restart_match_motm_vote(uuid,text) to authenticated, service_role;
grant execute on function public.admin_close_match_motm_vote_early(uuid,text) to authenticated, service_role;
