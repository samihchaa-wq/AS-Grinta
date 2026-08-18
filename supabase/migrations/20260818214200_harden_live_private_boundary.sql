-- AUD-006 follow-up: keep Live implementation private and expose only guarded public RPCs.
-- Public wrappers become SECURITY DEFINER boundaries with an explicit active-profile gate;
-- match-specific coach/admin authorization remains enforced inside the private implementations.

create or replace function public.coach_add_match_live_players(
  p_match_id uuid,
  p_players jsonb,
  p_reason text default null
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
  return private.add_match_live_players(p_match_id, p_players, p_reason);
end;
$function$;

create or replace function public.confirm_start_match_live(
  p_match_id uuid,
  p_reason text default null
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
  return private.confirm_start_match_live(p_match_id, p_reason);
end;
$function$;

create or replace function public.coach_delete_match_live_event(
  p_match_id uuid,
  p_event_id uuid
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
  return private.delete_match_live_event(p_match_id, p_event_id);
end;
$function$;

create or replace function public.coach_end_match_live(
  p_match_id uuid,
  p_reason text default null
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
  return private.end_match_live(p_match_id, p_reason);
end;
$function$;

create or replace function public.get_match_live_add_player_options(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.get_match_live_add_player_options(p_match_id);
end;
$function$;

create or replace function public.get_match_live_timeline(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.get_match_live_timeline(p_match_id);
end;
$function$;

create or replace function public.get_match_live_state(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
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
  return private.open_match_live_workspace(p_match_id, p_planned_duration_minutes);
end;
$function$;

create or replace function public.coach_publish_match_live_recap(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null
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
  return private.publish_match_live_recap(
    p_match_id, p_score_as_grinta, p_score_adverse, p_participants, p_reason
  );
end;
$function$;

create or replace function public.coach_reopen_match_live(
  p_match_id uuid,
  p_reason text default null
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
  return private.reopen_match_live(p_match_id, p_reason);
end;
$function$;

create or replace function public.coach_restart_match_live_session(
  p_match_id uuid,
  p_reason text default null
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
  return private.restart_match_live_session(p_match_id, p_reason);
end;
$function$;

create or replace function public.coach_set_match_live_clock_state(
  p_match_id uuid,
  p_action text,
  p_reason text default null
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
  return private.set_match_live_clock_state(p_match_id, p_action, p_reason);
end;
$function$;

create or replace function public.coach_set_match_live_event_scorer(
  p_match_id uuid,
  p_event_id uuid,
  p_scorer_participant_id uuid default null,
  p_is_opponent_own_goal boolean default false
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
  return private.set_match_live_event_scorer(
    p_match_id, p_event_id, p_scorer_participant_id, p_is_opponent_own_goal
  );
end;
$function$;

revoke execute on function private.add_match_live_players(uuid,jsonb,text) from public, anon, authenticated;
revoke execute on function private.confirm_start_match_live(uuid,text) from public, anon, authenticated;
revoke execute on function private.delete_match_live_event(uuid,uuid) from public, anon, authenticated;
revoke execute on function private.end_match_live(uuid,text) from public, anon, authenticated;
revoke execute on function private.get_match_live_add_player_options(uuid) from public, anon, authenticated;
revoke execute on function private.get_match_live_timeline(uuid) from public, anon, authenticated;
revoke execute on function private.match_live_snapshot(uuid) from public, anon, authenticated;
revoke execute on function private.open_match_live_workspace(uuid,integer) from public, anon, authenticated;
revoke execute on function private.publish_match_live_recap(uuid,integer,integer,jsonb,text) from public, anon, authenticated;
revoke execute on function private.reopen_match_live(uuid,text) from public, anon, authenticated;
revoke execute on function private.restart_match_live_session(uuid,text) from public, anon, authenticated;
revoke execute on function private.set_match_live_clock_state(uuid,text,text) from public, anon, authenticated;
revoke execute on function private.set_match_live_event_scorer(uuid,uuid,uuid,boolean) from public, anon, authenticated;

revoke execute on function public.coach_add_match_live_players(uuid,jsonb,text) from public, anon;
revoke execute on function public.confirm_start_match_live(uuid,text) from public, anon;
revoke execute on function public.coach_delete_match_live_event(uuid,uuid) from public, anon;
revoke execute on function public.coach_end_match_live(uuid,text) from public, anon;
revoke execute on function public.get_match_live_add_player_options(uuid) from public, anon;
revoke execute on function public.get_match_live_timeline(uuid) from public, anon;
revoke execute on function public.get_match_live_state(uuid) from public, anon;
revoke execute on function public.open_match_live_workspace(uuid,integer) from public, anon;
revoke execute on function public.coach_publish_match_live_recap(uuid,integer,integer,jsonb,text) from public, anon;
revoke execute on function public.coach_reopen_match_live(uuid,text) from public, anon;
revoke execute on function public.coach_restart_match_live_session(uuid,text) from public, anon;
revoke execute on function public.coach_set_match_live_clock_state(uuid,text,text) from public, anon;
revoke execute on function public.coach_set_match_live_event_scorer(uuid,uuid,uuid,boolean) from public, anon;

grant execute on function public.coach_add_match_live_players(uuid,jsonb,text) to authenticated, service_role;
grant execute on function public.confirm_start_match_live(uuid,text) to authenticated, service_role;
grant execute on function public.coach_delete_match_live_event(uuid,uuid) to authenticated, service_role;
grant execute on function public.coach_end_match_live(uuid,text) to authenticated, service_role;
grant execute on function public.get_match_live_add_player_options(uuid) to authenticated, service_role;
grant execute on function public.get_match_live_timeline(uuid) to authenticated, service_role;
grant execute on function public.get_match_live_state(uuid) to authenticated, service_role;
grant execute on function public.open_match_live_workspace(uuid,integer) to authenticated, service_role;
grant execute on function public.coach_publish_match_live_recap(uuid,integer,integer,jsonb,text) to authenticated, service_role;
grant execute on function public.coach_reopen_match_live(uuid,text) to authenticated, service_role;
grant execute on function public.coach_restart_match_live_session(uuid,text) to authenticated, service_role;
grant execute on function public.coach_set_match_live_clock_state(uuid,text,text) to authenticated, service_role;
grant execute on function public.coach_set_match_live_event_scorer(uuid,uuid,uuid,boolean) to authenticated, service_role;
