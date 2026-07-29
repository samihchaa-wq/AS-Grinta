-- All available players are convoked by default.
-- The squad-size limit becomes an advisory warning only; administrators
-- explicitly move players to the waitlist through the effectif draft.

create or replace function private.recompute_match_convocations_internal(
  p_match_id uuid,
  p_reset_overrides boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
      or participant.availability_status <> 'available'
    );

  -- Automatic decisions never remove an available player. A player is sent to
  -- the waitlist only when an administrator has explicitly overridden them.
  update public.match_sport_participants participant
  set convocation_status = 'convoked',
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and not participant.convocation_manual_override;

  -- Preserve explicit administrator decisions and their waitlist-turn state.
  update public.match_sport_participants participant
  set waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_state = case
        when participant.convocation_status = 'not_convoked'
          and participant.waitlist_turn_should_consume
          and participant.waitlist_turn_state not in ('consumed', 'waived')
          then 'pending'::public.sport_waitlist_turn_state
        when participant.convocation_status = 'convoked'
          and participant.waitlist_turn_state = 'pending'
          then 'waived'::public.sport_waitlist_turn_state
        else participant.waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_manual_override;

  update public.match_sport_workflows
  set convocation_generated_at = now(),
      updated_by = coalesce(v_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  select
    count(*)::integer,
    count(*) filter (
      where participant.convocation_status = 'convoked'
    )::integer,
    count(*) filter (
      where participant.convocation_status = 'not_convoked'
    )::integer
  into v_available, v_convoked, v_not_convoked
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
  'Convokes every available player by default. Squad-limit overflow is advisory; only explicit admin overrides create waitlisted players.';
