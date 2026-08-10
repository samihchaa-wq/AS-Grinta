-- Tableau Blanc: end match / recap / publish / timeline RPCs.
-- publish_match_live_recap calls private.finalize_match_sport_postgame
-- UNCHANGED — the live tracker never reimplements or modifies the existing
-- finalize pipeline (score/attendance/badges/MOTM all stay exactly as today).

create or replace function private.end_match_live(p_match_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.elapsed_seconds, session.running_since
  into v_state, v_elapsed, v_running_since
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;

  update public.match_live_sessions
  set state = 'finished',
      elapsed_seconds = v_elapsed + case
        when v_state = 'running'
        then greatest(0, extract(epoch from now() - v_running_since))::integer
        else 0
      end,
      running_since = null,
      finished_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (p_match_id, 'end_match_live', v_actor, v_reason, '{}'::jsonb);

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.reopen_match_live(p_match_id uuid, p_reason text default null)
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
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state <> 'finished' then
    raise exception 'Only a finished (not yet exported) match can be reopened' using errcode = '22023';
  end if;
  if v_exported then
    raise exception 'This match has already been exported and cannot be reopened' using errcode = '22023';
  end if;

  update public.match_live_sessions
  set state = 'paused',
      finished_at = null,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (p_match_id, 'reopen_match_live', v_actor, v_reason, '{}'::jsonb);

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.publish_match_live_recap(
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
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_exported boolean;
  v_finalize_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state <> 'finished' then
    raise exception 'End the match before exporting its recap' using errcode = '22023';
  end if;
  if v_exported then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;

  -- Unchanged existing pipeline: score/attendance/badges/MOTM all behave
  -- exactly as a manually-finalized match.
  v_finalize_result := private.finalize_match_sport_postgame(
    p_match_id, p_score_as_grinta, p_score_adverse, p_participants, p_reason
  );

  update public.match_live_sessions
  set exported = true,
      exported_at = now(),
      score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  return v_finalize_result;
end;
$function$;

create or replace function private.get_match_live_timeline(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_exported boolean;
  v_events jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select session.exported into v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if not found or not coalesce(v_exported, false) then
    return null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'event_type', event.event_type,
      'minute', event.minute,
      'half', event.half,
      'scorer_name', btrim(concat_ws(' ', scorer_player.first_name, scorer_player.last_name, scorer_guest.first_name, scorer_guest.last_name)),
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_name', btrim(concat_ws(' ', in_player.first_name, in_player.last_name, in_guest.first_name, in_guest.last_name)),
      'player_out_name', btrim(concat_ws(' ', out_player.first_name, out_player.last_name, out_guest.first_name, out_guest.last_name))
    ) order by event.half, event.minute, event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants in_p on in_p.id = event.player_in_participant_id
  left join public.season_players in_player on in_player.id = in_p.season_player_id
  left join public.guest_players in_guest on in_guest.id = in_p.guest_player_id
  left join public.match_sport_participants out_p on out_p.id = event.player_out_participant_id
  left join public.season_players out_player on out_player.id = out_p.season_player_id
  left join public.guest_players out_guest on out_guest.id = out_p.guest_player_id
  where event.match_id = p_match_id;

  return jsonb_build_object('match_id', p_match_id, 'events', v_events);
end;
$function$;

create or replace function public.coach_end_match_live(p_match_id uuid, p_reason text default null)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.end_match_live(p_match_id, p_reason); $function$;

create or replace function public.coach_reopen_match_live(p_match_id uuid, p_reason text default null)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.reopen_match_live(p_match_id, p_reason); $function$;

create or replace function public.coach_publish_match_live_recap(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.publish_match_live_recap(
    p_match_id, p_score_as_grinta, p_score_adverse, p_participants, p_reason
  );
$function$;

create or replace function public.get_match_live_timeline(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_match_live_timeline(p_match_id); $function$;

revoke execute on function private.end_match_live(uuid, text) from public, anon;
revoke execute on function private.reopen_match_live(uuid, text) from public, anon;
revoke execute on function private.publish_match_live_recap(uuid, integer, integer, jsonb, text) from public, anon;
revoke execute on function private.get_match_live_timeline(uuid) from public, anon;

grant execute on function private.end_match_live(uuid, text) to authenticated, service_role;
grant execute on function private.reopen_match_live(uuid, text) to authenticated, service_role;
grant execute on function private.publish_match_live_recap(uuid, integer, integer, jsonb, text) to authenticated, service_role;
grant execute on function private.get_match_live_timeline(uuid) to authenticated, service_role;

revoke execute on function public.coach_end_match_live(uuid, text) from public, anon;
revoke execute on function public.coach_reopen_match_live(uuid, text) from public, anon;
revoke execute on function public.coach_publish_match_live_recap(uuid, integer, integer, jsonb, text) from public, anon;
revoke execute on function public.get_match_live_timeline(uuid) from public, anon;

grant execute on function public.coach_end_match_live(uuid, text) to authenticated, service_role;
grant execute on function public.coach_reopen_match_live(uuid, text) to authenticated, service_role;
grant execute on function public.coach_publish_match_live_recap(uuid, integer, integer, jsonb, text) to authenticated, service_role;
grant execute on function public.get_match_live_timeline(uuid) to authenticated, service_role;
