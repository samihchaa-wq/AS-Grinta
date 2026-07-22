create or replace function private.get_match_availability_board(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'kickoff_at', match.kickoff_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'composition_published', exists (
      select 1
      from public.match_composition_publications publication
      where publication.match_id = match.id
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'is_guest', guest.id is not null,
        'status', participant.availability_status,
        'convocation_status', participant.convocation_status,
        'waitlist_position', waitlist.position,
        'promoted_from_participant_id', participant.promoted_from_participant_id
      )
      order by
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null) then 0
          when participant.availability_status = 'available' then 1
          when participant.availability_status = 'absent' then 2
          when participant.availability_status = 'no_response' then 3
          else 4
        end,
        waitlist.position,
        lower(coalesce(player.first_name, guest.first_name, '')),
        participant.id
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
   and participant.is_eligible
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

create or replace function private.restore_returning_convoked_player(
  p_match_id uuid,
  p_participant_id uuid,
  p_actor uuid,
  p_actor_kind text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_was_convoked boolean := false;
  v_promoted_id uuid;
  v_promoted_season_player_id uuid;
begin
  select exists (
    select 1
    from public.match_sport_participant_events event
    where event.match_id = p_match_id
      and event.participant_id = p_participant_id
      and event.event_type = 'convoked_player_withdrew'
  )
  into v_was_convoked;

  select candidate.id, candidate.season_player_id
  into v_promoted_id, v_promoted_season_player_id
  from public.match_sport_participants candidate
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = candidate.season_player_id
  where candidate.match_id = p_match_id
    and candidate.is_eligible
    and candidate.convocation_status = 'convoked'
    and candidate.promoted_from_participant_id = p_participant_id
  order by candidate.promoted_after_withdrawal_at desc nulls last,
    waitlist.position,
    candidate.id
  limit 1
  for update of candidate;

  v_was_convoked := v_was_convoked or v_promoted_id is not null;

  if not v_was_convoked then
    update public.match_sport_participants
    set convocation_status = 'not_convoked',
        convocation_manual_override = false,
        waitlist_turn_should_consume = true,
        waitlist_turn_state = 'pending',
        waitlist_turn_updated_at = now(),
        updated_at = now()
    where id = p_participant_id;
    return null;
  end if;

  update public.match_sport_participants
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'waived',
      waitlist_turn_updated_at = now(),
      promoted_after_withdrawal_at = null,
      promoted_from_participant_id = null,
      updated_at = now()
  where id = p_participant_id;

  if v_promoted_id is not null then
    update public.match_sport_participants
    set convocation_status = 'not_convoked',
        convocation_manual_override = true,
        waitlist_turn_should_consume = true,
        waitlist_turn_state = 'pending',
        waitlist_turn_updated_at = now(),
        promoted_after_withdrawal_at = null,
        promoted_from_participant_id = null,
        updated_at = now()
    where id = v_promoted_id;
  end if;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = coalesce(p_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values (
    p_participant_id,
    p_match_id,
    'convoked_player_returned',
    jsonb_build_object('convocation_status', 'not_applicable'),
    jsonb_build_object('convocation_status', 'convoked'),
    p_actor,
    p_actor_kind
  );

  if v_promoted_id is not null then
    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_promoted_id,
      p_match_id,
      'promoted_player_returned_to_waitlist',
      jsonb_build_object('convocation_status', 'convoked'),
      jsonb_build_object('convocation_status', 'not_convoked'),
      p_actor,
      p_actor_kind
    );
  end if;

  return v_promoted_season_player_id;
end;
$$;

create or replace function private.set_my_match_availability(
  p_match_id uuid,
  p_status text,
  p_private_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_composition_state public.sport_composition_state;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('available', 'absent') then
    raise exception 'Availability status must be available or absent' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status = 'available' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_composition_state, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and participant.is_eligible
    and player.profile_id = v_actor
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'player'
    );

    if v_convocation_state = 'published'
       and v_old_status = 'available'
       and v_new_status = 'absent' then
      v_promoted_player_id := private.handle_convoked_withdrawal(
        p_match_id, v_participant_id, v_actor, 'player'
      );
    elsif v_convocation_state = 'published'
       and v_old_status = 'absent'
       and v_new_status = 'available' then
      v_promoted_player_id := private.restore_returning_convoked_player(
        p_match_id, v_participant_id, v_actor, 'player'
      );
    else
      perform private.recompute_match_convocations_internal(p_match_id, false);
    end if;
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id,
    'composition_already_published',
      v_composition_state in ('published', 'updated', 'closed')
  );
end;
$$;

create or replace function private.publish_match_convocations(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_summary jsonb;
  v_unresolved integer;
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_summary := private.recompute_match_convocations_internal(p_match_id, false);

  select count(*)::integer into v_unresolved
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_status = 'not_applicable';

  if v_unresolved > 0 then
    raise exception 'Every available player needs a convocation decision'
      using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set convocation_state = 'published',
      convocation_version = convocation_version + 1,
      convocation_published_at = coalesce(convocation_published_at, now()),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants
  set waitlist_turn_state = case
        when waitlist_turn_should_consume then
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        else
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'waived'::public.sport_waitlist_turn_state
          end
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where match_id = p_match_id
    and is_eligible
    and availability_status = 'available';

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'publish_convocations', v_actor, v_reason, v_summary
  );

  return private.get_match_convocations(p_match_id);
end;
$$;

create or replace function private.get_published_match_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_kickoff_at timestamptz;
  v_entries jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_participant record;
  v_field_count integer := 0;
  v_bench_count integer := 0;
  v_available_count integer := 0;
  v_not_selected_count integer := 0;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select publication.snapshot, match.kickoff_at
  into v_result, v_kickoff_at
  from public.match_composition_publications publication
  join public.matches match on match.id = publication.match_id
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_result is null or now() >= v_kickoff_at then
    return v_result;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(v_result -> 'entries', '[]'::jsonb))
    order by coalesce((value ->> 'sort_order')::integer, 0)
  loop
    select participant.availability_status::text as availability_status,
      participant.convocation_status::text as convocation_status,
      participant.season_player_id,
      participant.guest_player_id
    into v_participant
    from public.match_sport_participants participant
    where participant.match_id = p_match_id
      and participant.id = (v_entry ->> 'participant_id')::uuid;

    if found then
      v_entry := v_entry || jsonb_build_object(
        'availability_status', v_participant.availability_status,
        'convocation_status', v_participant.convocation_status
      );
      if v_participant.season_player_id is not null
         and v_participant.availability_status <> 'available' then
        v_entry := v_entry || jsonb_build_object(
          'zone', 'not_selected',
          'x', null,
          'y', null,
          'selection_status', 'not_selected'
        );
      elsif v_participant.convocation_status <> 'convoked'
         and (v_entry ->> 'zone') in ('field', 'bench', 'available') then
        v_entry := v_entry || jsonb_build_object(
          'zone', 'not_selected',
          'x', null,
          'y', null,
          'selection_status', 'not_selected'
        );
      end if;
    end if;

    case v_entry ->> 'zone'
      when 'field' then v_field_count := v_field_count + 1;
      when 'bench' then v_bench_count := v_bench_count + 1;
      when 'available' then v_available_count := v_available_count + 1;
      else v_not_selected_count := v_not_selected_count + 1;
    end case;
    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  return v_result || jsonb_build_object(
    'entries', v_entries,
    'field_count', v_field_count,
    'bench_count', v_bench_count,
    'available_count', v_available_count,
    'not_selected_count', v_not_selected_count
  );
end;
$$;

create or replace function private.save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_kickoff_at timestamptz;
  v_match_status text;
  v_expected_count integer;
  v_input_count integer;
  v_invalid_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit < 1 or p_squad_size_limit > 30 then
    raise exception 'Squad size limit must be between 1 and 30' using errcode = '22023';
  end if;
  if p_decisions is null or jsonb_typeof(p_decisions) <> 'array' then
    raise exception 'Effectif decisions must be a JSON array' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.kickoff_at, match.status
  into v_kickoff_at, v_match_status
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Effectif can only be edited before kickoff' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.effectif_input (
    season_player_id uuid primary key,
    status public.sport_convocation_status not null
  ) on commit drop;
  truncate table pg_temp.effectif_input;

  begin
    insert into pg_temp.effectif_input(season_player_id, status)
    select
      (item ->> 'season_player_id')::uuid,
      (item ->> 'status')::public.sport_convocation_status
    from jsonb_array_elements(p_decisions) item
    where item ->> 'status' in ('convoked', 'not_convoked');
  exception
    when unique_violation then
      raise exception 'A player can appear only once in effectif decisions' using errcode = '22023';
    when invalid_text_representation then
      raise exception 'Invalid effectif decision' using errcode = '22023';
  end;

  select count(*)::integer into v_input_count from pg_temp.effectif_input;
  select count(*)::integer into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status = 'available';

  if v_input_count <> v_expected_count then
    raise exception 'Every available permanent player needs one effectif decision' using errcode = '22023';
  end if;

  select count(*)::integer into v_invalid_count
  from pg_temp.effectif_input input
  left join public.match_sport_participants participant
    on participant.match_id = p_match_id
   and participant.season_player_id = input.season_player_id
   and participant.is_eligible
   and participant.availability_status = 'available'
  where participant.id is null;

  if v_invalid_count > 0 then
    raise exception 'Effectif contains an unavailable or ineligible player' using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      convocation_state = 'published',
      convocation_version = convocation_version + 1,
      convocation_generated_at = now(),
      convocation_published_at = coalesce(convocation_published_at, now()),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants participant
  set convocation_status = input.status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = input.status = 'not_convoked',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed' then 'consumed'::public.sport_waitlist_turn_state
        when input.status = 'not_convoked' then 'pending'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from pg_temp.effectif_input input
  where participant.match_id = p_match_id
    and participant.season_player_id = input.season_player_id;

  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed' then 'consumed'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status <> 'available';

  update public.match_sport_participants participant
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'waived',
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.guest_player_id is not null;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'save_match_effectif',
    v_actor,
    v_reason,
    jsonb_build_object(
      'squad_size_limit', p_squad_size_limit,
      'convoked_count', (
        select count(*) from pg_temp.effectif_input where status = 'convoked'
      ),
      'waitlisted_count', (
        select count(*) from pg_temp.effectif_input where status = 'not_convoked'
      )
    )
  );

  return private.get_match_convocations(p_match_id);
end;
$$;

create or replace function public.admin_save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language sql
set search_path = ''
as $$
  select private.save_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
$$;

