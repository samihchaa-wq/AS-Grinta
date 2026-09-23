begin;

-- Automatic quota enforcement for classic matches.
-- Available rotation players are selected by default up to squad_size_limit.
-- Overflow is sent to the waitlist starting from the highest-priority
-- sport_waitlist_entries.position. Coaches remain outside the quota.
-- Explicit administrator overrides are preserved and the remaining automatic
-- places rebalance around them.

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
  v_match_type text;
  v_available integer;
  v_convoked integer;
  v_not_convoked integer;
  v_over_limit integer;
  v_manual_convoked integer;
  v_auto_slots integer;
begin
  perform private.require_sports_management_enabled();

  select match.season_id, workflow.squad_size_limit, match.match_type
  into v_season_id, v_limit, v_match_type
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

  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_position_snapshot = ranked.waitlist_position,
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

  select count(*)::integer
  into v_manual_convoked
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_manual_override
    and participant.convocation_status = 'convoked';

  v_auto_slots := greatest(0, v_limit - v_manual_convoked);

  if v_match_type = 'entre_nous' then
    v_auto_slots := 2147483647;
  end if;

  with ranked as (
    select
      participant.id,
      waitlist.position as waitlist_position,
      row_number() over (
        order by waitlist.position desc, participant.id
      ) as keep_rank
    from public.match_sport_participants participant
    join public.sport_waitlist_entries waitlist
      on waitlist.season_player_id = participant.season_player_id
     and waitlist.season_id = v_season_id
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.availability_status = 'available'
      and not participant.convocation_manual_override
  )
  update public.match_sport_participants participant
  set convocation_status = case
        when ranked.keep_rank <= v_auto_slots
          then 'convoked'::public.sport_convocation_status
        else 'not_convoked'::public.sport_convocation_status
      end,
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = ranked.keep_rank > v_auto_slots,
      waitlist_turn_should_consume = ranked.keep_rank > v_auto_slots,
      waitlist_turn_state = case
        when ranked.keep_rank > v_auto_slots then
          case
            when participant.waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from ranked
  where participant.id = ranked.id;

  -- Coach: present in the effectif when available, but never consumes quota.
  update public.match_sport_participants participant
  set convocation_status = case
        when participant.availability_status = 'available'
          then 'convoked'::public.sport_convocation_status
        else 'not_applicable'::public.sport_convocation_status
      end,
      convocation_manual_override = false,
      waitlist_position_snapshot = null,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'not_applicable'::public.sport_waitlist_turn_state,
      updated_at = now()
  from public.season_players player
  where participant.match_id = p_match_id
    and player.id = participant.season_player_id
    and player.is_coach;

  -- Explicit admin choices remain authoritative. A promoted player therefore
  -- takes one automatic slot; a manually waitlisted player frees one.
  update public.match_sport_participants participant
  set waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume =
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
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and participant.is_eligible
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

comment on function private.recompute_match_convocations_internal(uuid, boolean) is
  'Enforces the configured classic-match quota automatically using waitlist priority, while preserving explicit admin overrides and keeping coaches outside the quota.';

-- A one-player manual change is an atomic interchange: after preserving that
-- choice, recompute fills/demotes the remaining automatic slots immediately.
create or replace function private.set_match_convocation(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_turn_should_consume boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_convocation_status;
  v_old_consume boolean;
  v_new_status public.sport_convocation_status;
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('convoked', 'not_convoked') then
    raise exception 'Invalid convocation status' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;
  v_new_status := p_status::public.sport_convocation_status;

  select participant.id, participant.convocation_status,
    participant.waitlist_turn_should_consume
  into v_participant_id, v_old_status, v_old_consume
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
  for update;

  if not found then
    raise exception 'Available participant not found' using errcode = 'P0002';
  end if;

  update public.match_sport_participants
  set convocation_status = v_new_status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = p_turn_should_consume,
      waitlist_turn_state = case
        when p_turn_should_consume then
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where id = v_participant_id;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values (
    v_participant_id, p_match_id, 'convocation_overridden',
    jsonb_build_object(
      'status', v_old_status,
      'turn_should_consume', v_old_consume
    ),
    jsonb_build_object(
      'status', v_new_status,
      'turn_should_consume', p_turn_should_consume
    ),
    v_actor, 'staff'
  );

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'override_convocation', v_actor, v_reason,
    jsonb_build_object(
      'season_player_id', p_season_player_id,
      'old_status', v_old_status,
      'new_status', v_new_status,
      'old_turn_should_consume', v_old_consume,
      'new_turn_should_consume', p_turn_should_consume
    )
  );

  perform private.recompute_match_convocations_internal(p_match_id, false);
  return private.get_match_convocations(p_match_id);
end;
$function$;

-- Legacy immediate-effectif saves could mark every currently convoked player as
-- manual even when no interchange existed. For upcoming classic matches where
-- every available decision is merely "manual convoked" and nobody is manually
-- waitlisted, restore those rows to automatic before applying the new rule.
update public.match_sport_participants participant
set convocation_manual_override = false,
    updated_at = now()
from public.matches match
where match.id = participant.match_id
  and match.status = 'a_venir'
  and match.match_type <> 'entre_nous'
  and participant.is_eligible
  and participant.availability_status = 'available'
  and participant.convocation_manual_override
  and participant.convocation_status = 'convoked'
  and not exists (
    select 1
    from public.match_sport_participants other
    where other.match_id = participant.match_id
      and other.is_eligible
      and other.availability_status = 'available'
      and other.convocation_manual_override
      and other.convocation_status = 'not_convoked'
  );

do $do$
declare
  v_match_id uuid;
begin
  for v_match_id in
    select match.id
    from public.matches match
    join public.match_sport_workflows workflow on workflow.match_id = match.id
    where match.status = 'a_venir'
      and match.match_type <> 'entre_nous'
  loop
    perform private.recompute_match_convocations_internal(v_match_id, false);
  end loop;
end
$do$;

commit;
