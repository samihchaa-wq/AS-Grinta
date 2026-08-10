-- Unified administrator workflow: availability decisions, squad selection and
-- composition are saved and published in one transaction.

create or replace function private.save_match_squad_plan(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
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
  v_expected_count integer;
  v_input_count integer;
  v_invalid_count integer;
  v_changed_count integer := 0;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Squad plan entries must be a JSON array' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.match_squad_plan_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null
  ) on commit drop;
  truncate table pg_temp.match_squad_plan_input;

  begin
    insert into pg_temp.match_squad_plan_input(participant_id, zone)
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a squad plan'
        using errcode = '22023';
    when invalid_text_representation or check_violation then
      raise exception 'Invalid squad plan entry' using errcode = '22023';
  end;

  select count(*)::integer into v_input_count
  from pg_temp.match_squad_plan_input;

  select count(*)::integer into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  if v_expected_count = 0 then
    raise exception 'Sport match participants not found' using errcode = 'P0002';
  end if;
  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_invalid_count
  from pg_temp.match_squad_plan_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and participant.is_eligible
  where participant.id is null;

  if v_invalid_count > 0 then
    raise exception 'Squad plan contains an ineligible participant'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_invalid_count
  from pg_temp.match_squad_plan_input input
  join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
  where participant.season_player_id is not null
    and participant.availability_status <> 'available'
    and input.zone <> 'not_selected';

  if v_invalid_count > 0 then
    raise exception 'Absent or unanswered players must remain outside the squad'
      using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.match_squad_plan_old_decisions (
    participant_id uuid primary key,
    old_status public.sport_convocation_status not null,
    old_manual_override boolean not null,
    old_turn_should_consume boolean not null,
    old_turn_state public.sport_waitlist_turn_state not null
  ) on commit drop;
  truncate table pg_temp.match_squad_plan_old_decisions;

  insert into pg_temp.match_squad_plan_old_decisions(
    participant_id,
    old_status,
    old_manual_override,
    old_turn_should_consume,
    old_turn_state
  )
  select
    participant.id,
    participant.convocation_status,
    participant.convocation_manual_override,
    participant.waitlist_turn_should_consume,
    participant.waitlist_turn_state
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
  for update;

  update public.match_sport_participants participant
  set convocation_status = case
        when participant.season_player_id is not null
             and participant.availability_status <> 'available'
          then 'not_applicable'::public.sport_convocation_status
        when input.zone = 'not_selected'
          then 'not_convoked'::public.sport_convocation_status
        else 'convoked'::public.sport_convocation_status
      end,
      convocation_manual_override = case
        when participant.season_player_id is not null
             and participant.availability_status <> 'available'
          then false
        else true
      end,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = case
        when participant.season_player_id is not null
             and participant.availability_status = 'available'
             and input.zone = 'not_selected'
          then true
        else false
      end,
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when participant.season_player_id is not null
             and participant.availability_status = 'available'
             and input.zone = 'not_selected'
          then 'pending'::public.sport_waitlist_turn_state
        when participant.season_player_id is not null
             and participant.availability_status = 'available'
          then 'waived'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from pg_temp.match_squad_plan_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id,
    match_id,
    event_type,
    old_value,
    new_value,
    actor_profile_id,
    actor_kind
  )
  select
    participant.id,
    p_match_id,
    'convocation_overridden',
    jsonb_build_object(
      'status', old_decision.old_status,
      'manual_override', old_decision.old_manual_override,
      'turn_should_consume', old_decision.old_turn_should_consume,
      'turn_state', old_decision.old_turn_state
    ),
    jsonb_build_object(
      'status', participant.convocation_status,
      'manual_override', participant.convocation_manual_override,
      'turn_should_consume', participant.waitlist_turn_should_consume,
      'turn_state', participant.waitlist_turn_state,
      'source', 'unified_squad_plan'
    ),
    v_actor,
    'staff'
  from public.match_sport_participants participant
  join pg_temp.match_squad_plan_old_decisions old_decision
    on old_decision.participant_id = participant.id
  where participant.match_id = p_match_id
    and (
      old_decision.old_status is distinct from participant.convocation_status
      or old_decision.old_manual_override is distinct from participant.convocation_manual_override
      or old_decision.old_turn_should_consume is distinct from participant.waitlist_turn_should_consume
      or old_decision.old_turn_state is distinct from participant.waitlist_turn_state
    );

  get diagnostics v_changed_count = row_count;

  update public.match_sport_workflows workflow
  set convocation_version = convocation_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'save_unified_squad_plan',
    v_actor,
    v_reason,
    jsonb_build_object('convocation_decisions_changed', v_changed_count)
  );

  return private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    false,
    coalesce(v_reason, 'Plan de sélection unifié')
  );
end;
$function$;

create or replace function private.publish_match_squad_plan(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.save_match_squad_plan(
    p_match_id,
    p_formation_code,
    p_entries,
    coalesce(v_reason, 'Publication du plan de sélection unifié')
  );

  perform private.publish_match_convocations(
    p_match_id,
    coalesce(v_reason, 'Publication depuis Sélection & composition')
  );

  return private.publish_match_composition(
    p_match_id,
    false,
    coalesce(v_reason, 'Publication depuis Sélection & composition')
  );
end;
$function$;

create or replace function public.admin_save_match_squad_plan(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.save_match_squad_plan(
    p_match_id,
    p_formation_code,
    p_entries,
    p_reason
  );
$function$;

create or replace function public.admin_publish_match_squad_plan(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.publish_match_squad_plan(
    p_match_id,
    p_formation_code,
    p_entries,
    p_reason
  );
$function$;

revoke execute on function private.save_match_squad_plan(uuid, text, jsonb, text)
  from public, anon;
revoke execute on function private.publish_match_squad_plan(uuid, text, jsonb, text)
  from public, anon;
revoke execute on function public.admin_save_match_squad_plan(uuid, text, jsonb, text)
  from public, anon;
revoke execute on function public.admin_publish_match_squad_plan(uuid, text, jsonb, text)
  from public, anon;

grant execute on function private.save_match_squad_plan(uuid, text, jsonb, text)
  to authenticated, service_role;
grant execute on function private.publish_match_squad_plan(uuid, text, jsonb, text)
  to authenticated, service_role;
grant execute on function public.admin_save_match_squad_plan(uuid, text, jsonb, text)
  to authenticated, service_role;
grant execute on function public.admin_publish_match_squad_plan(uuid, text, jsonb, text)
  to authenticated, service_role;

comment on function public.admin_save_match_squad_plan(uuid, text, jsonb, text) is
  'Saves availability-based selection decisions and the complete composition atomically.';
comment on function public.admin_publish_match_squad_plan(uuid, text, jsonb, text) is
  'Publishes selection decisions, waitlist turns and the immutable composition in one transaction.';
