create or replace function private.restart_match_live_session(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_exported boolean;
  v_snapshot jsonb;
  v_events integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported, session.starting_lineup_snapshot
  into v_state, v_exported, v_snapshot
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;
  if v_exported then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;
  if v_state = 'not_started' then
    raise exception 'The match has not been started yet' using errcode = '22023';
  end if;

  select count(*) into v_events
  from public.match_live_events
  where match_id = p_match_id;

  delete from public.match_live_events where match_id = p_match_id;

  if v_snapshot is not null and jsonb_typeof(v_snapshot) = 'object' then
    update public.match_composition_entries entry
    set zone = (snapshot.value #>> '{}')::public.sport_composition_zone
    from jsonb_each(v_snapshot) snapshot
    where entry.match_id = p_match_id
      and entry.participant_id = snapshot.key::uuid
      and entry.zone <> (snapshot.value #>> '{}')::public.sport_composition_zone;
  end if;

  update public.match_live_sessions
  set state = 'not_started',
      half = 1,
      elapsed_seconds = 0,
      running_since = null,
      score_as_grinta = 0,
      score_adverse = 0,
      started_at = null,
      finished_at = null,
      starting_composition_version = null,
      starting_lineup_snapshot = null,
      lineup_revision = lineup_revision + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_match_live', v_actor, v_reason,
    jsonb_build_object('deleted_events', v_events, 'previous_state', v_state)
  );

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.coach_restart_match_live_session(
  p_match_id uuid, p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.restart_match_live_session(p_match_id, p_reason); $function$;

revoke execute on function private.restart_match_live_session(uuid, text)
  from public, anon;
grant execute on function private.restart_match_live_session(uuid, text)
  to authenticated, service_role;

revoke execute on function public.coach_restart_match_live_session(uuid, text)
  from public, anon;
grant execute on function public.coach_restart_match_live_session(uuid, text)
  to authenticated, service_role;

comment on function public.coach_restart_match_live_session(uuid, text) is
  'Wipes a non-exported live session (events, clock, score) and restores the kickoff lineup.';;
