-- La disponibilité déclarée par le joueur et la décision sportive de
-- l'administration sont deux axes indépendants. Un absent ou un joueur sans
-- réponse peut donc être pré-positionné parmi les convoqués ou en liste
-- d'attente, sans que sa réponse soit modifiée.

create or replace function private.recompute_match_convocations_internal(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_limit integer;
  v_available integer;
  v_convoked integer;
  v_not_convoked integer;
  v_over_limit integer;
begin
  perform private.require_sports_management_enabled();

  select match.season_id, workflow.squad_size_limit
  into v_season_id, v_limit
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  perform private.finalize_due_waitlist_turns_for_season(v_season_id);
  perform private.ensure_sport_waitlist(v_season_id, v_actor);

  update public.match_sport_participants participant
  set convocation_manual_override = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and p_reset_overrides;

  -- Les inéligibles et les non-disponibles sans décision manuelle restent
  -- hors effectif. Une décision explicite de l'admin est conservée même si
  -- la disponibilité vaut absent ou no_response.
  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state in ('consumed', 'waived')
          then participant.waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and (
      not participant.is_eligible
      or (
        participant.availability_status <> 'available'
        and not participant.convocation_manual_override
      )
    );

  -- Les disponibles sans décision manuelle restent convoqués par défaut.
  update public.match_sport_participants participant
  set convocation_status = 'convoked',
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state in ('consumed', 'waived')
          then participant.waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and not participant.convocation_manual_override;

  -- Une décision prise avant la réponse devient pleinement active dès que le
  -- joueur se déclare disponible. La liste d'attente ne consomme jamais de
  -- tour tant que la disponibilité reste absente ou sans réponse.
  update public.match_sport_participants participant
  set waitlist_turn_should_consume =
        participant.convocation_status = 'not_convoked',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when participant.convocation_status = 'not_convoked'
          then 'pending'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status = 'available'
    and participant.convocation_manual_override
    and participant.convocation_status in ('convoked', 'not_convoked');

  update public.match_sport_workflows
  set convocation_generated_at = now(),
      updated_by = coalesce(v_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  select count(*)::integer into v_available
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available';

  select
    count(*) filter (
      where participant.convocation_status = 'convoked'
    )::integer,
    count(*) filter (
      where participant.convocation_status = 'not_convoked'
    )::integer
  into v_convoked, v_not_convoked
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available';

  v_over_limit := greatest(0, v_convoked - v_limit);

  return jsonb_build_object(
    'match_id', p_match_id,
    'squad_size_limit', v_limit,
    'available_count', v_available,
    'convoked_count', v_convoked,
    'not_convoked_count', v_not_convoked,
    'over_limit_count', v_over_limit
  );
end;
$function$;

-- Lorsqu'un absent redevient disponible, une décision d'effectif manuelle
-- existante prime sur le comportement automatique historique de retour.
create or replace function private.restore_returning_convoked_player(
  p_match_id uuid,
  p_participant_id uuid,
  p_actor uuid,
  p_actor_kind text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_current_status public.sport_convocation_status;
  v_manual_override boolean;
  v_was_convoked boolean := false;
  v_promoted_id uuid;
  v_promoted_season_player_id uuid;
begin
  select participant.convocation_status,
    participant.convocation_manual_override
  into v_current_status, v_manual_override
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.id = p_participant_id
    and participant.is_eligible
  for update;

  if not found then
    return null;
  end if;

  if v_manual_override
     and v_current_status in ('convoked', 'not_convoked') then
    update public.match_sport_participants participant
    set waitlist_turn_should_consume =
          v_current_status = 'not_convoked',
        waitlist_turn_state = case
          when participant.waitlist_turn_state = 'consumed'
            then 'consumed'::public.sport_waitlist_turn_state
          when v_current_status = 'not_convoked'
            then 'pending'::public.sport_waitlist_turn_state
          else 'waived'::public.sport_waitlist_turn_state
        end,
        waitlist_turn_updated_at = now(),
        updated_at = now()
    where participant.id = p_participant_id;
    return null;
  end if;

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
$function$;

-- Le même contrat s'applique quand la disponibilité est corrigée par un
-- administrateur : le retour d'un absent ne doit pas effacer une décision
-- d'effectif manuelle prise pendant son absence.
create or replace function private.override_match_availability(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_private_comment text default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_reason text := nullif(btrim(p_reason), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('no_response', 'available', 'absent') then
    raise exception 'Invalid availability override status' using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception 'Override reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Override reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status <> 'absent' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and participant.is_eligible
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
      v_actor, 'staff'
    );

    if v_convocation_state = 'published'
       and v_old_status = 'available'
       and v_new_status = 'absent' then
      v_promoted_player_id := private.handle_convoked_withdrawal(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    elsif v_convocation_state = 'published'
       and v_old_status = 'absent'
       and v_new_status = 'available' then
      v_promoted_player_id := private.restore_returning_convoked_player(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    else
      perform private.recompute_match_convocations_internal(p_match_id, false);
    end if;

    insert into private.sport_admin_audit_log (
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id, 'override_availability', v_actor, v_reason,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'season_player_id', p_season_player_id,
        'old_status', v_old_status,
        'new_status', v_new_status,
        'promoted_season_player_id', v_promoted_player_id
      )
    );
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id
  );
end;
$function$;

create or replace function private.publish_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_kickoff_at timestamptz;
  v_match_status text;
  v_payload_count integer;
  v_input_count integer;
  v_missing_count integer;
  v_invalid_count integer;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit is null
     or p_squad_size_limit < 1
     or p_squad_size_limit > 30 then
    raise exception 'Squad size limit must be between 1 and 30'
      using errcode = '22023';
  end if;
  if p_decisions is null or jsonb_typeof(p_decisions) <> 'array' then
    raise exception 'Effectif decisions must be a JSON array'
      using errcode = '22023';
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
    raise exception 'Effectif can only be edited before kickoff'
      using errcode = '22023';
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
      raise exception 'A player can appear only once in effectif decisions'
        using errcode = '22023';
    when invalid_text_representation or not_null_violation then
      raise exception 'Invalid effectif decision' using errcode = '22023';
  end;

  v_payload_count := jsonb_array_length(p_decisions);
  select count(*)::integer into v_input_count
  from pg_temp.effectif_input;

  if v_input_count <> v_payload_count then
    raise exception 'Invalid effectif decision' using errcode = '22023';
  end if;

  select count(*)::integer into v_missing_count
  from public.match_sport_participants participant
  left join pg_temp.effectif_input input
    on input.season_player_id = participant.season_player_id
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status = 'available'
    and input.season_player_id is null;

  if v_missing_count > 0 then
    raise exception 'Every available permanent player needs one effectif decision'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_invalid_count
  from pg_temp.effectif_input input
  left join public.match_sport_participants participant
    on participant.match_id = p_match_id
   and participant.season_player_id = input.season_player_id
   and participant.is_eligible
   and participant.availability_status in (
     'available', 'absent', 'no_response'
   )
  where participant.id is null;

  if v_invalid_count > 0 then
    raise exception 'Effectif contains an ineligible player'
      using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants participant
  set convocation_status = input.status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume =
        input.status = 'not_convoked'
        and participant.availability_status = 'available',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when input.status = 'not_convoked'
             and participant.availability_status = 'available'
          then 'pending'::public.sport_waitlist_turn_state
        when input.status = 'convoked'
          then 'waived'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from pg_temp.effectif_input input
  where participant.match_id = p_match_id
    and participant.season_player_id = input.season_player_id
    and participant.is_eligible;

  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status <> 'available'
    and not exists (
      select 1
      from pg_temp.effectif_input input
      where input.season_player_id = participant.season_player_id
    );

  update public.match_sport_participants participant
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'waived',
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.guest_player_id is not null;

  v_result := private.publish_match_convocations(
    p_match_id,
    coalesce(v_reason, 'Mise à jour immédiate de l’effectif')
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'update_match_effectif',
    v_actor,
    v_reason,
    jsonb_build_object(
      'squad_size_limit', p_squad_size_limit,
      'convocation_version', v_result -> 'convocation_version'
    )
  );

  return private.get_match_convocations(p_match_id);
end;
$function$;

comment on function private.publish_match_effectif(uuid, integer, jsonb, text)
is 'Publishes admin effectif decisions independently from player availability.';
