-- Coach flag: a roster member marked as coach is excluded from the effectif
-- board, the convocation count and the composition, but can still mark his own
-- availability and use everything else (pronos, HDM, ...).
alter table public.season_players
  add column if not exists is_coach boolean not null default false;

grant select (is_coach), update (is_coach), insert (is_coach)
  on public.season_players to authenticated;

-- Seed participants as ineligible for coaches so every reader that filters
-- is_eligible (board, convocations, composition, finalization) drops them.
create or replace function private.sync_match_sport_workflow(p_match_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_config jsonb;
  v_open_hours integer := 144;
  v_default_squad_size integer := 14;
  v_opens_at timestamptz;
  v_computed_state public.sport_availability_state;
  v_saved_state public.sport_availability_state;
  v_opened_at timestamptz;
  v_eligible_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.season_id, match.kickoff_at, match.status
  into v_season_id, v_kickoff_at, v_match_status
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Only upcoming matches can be synchronized' using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select flag.config into v_config
  from private.app_feature_flags flag
  where flag.key = 'sports_management';

  if coalesce(v_config ->> 'availability_open_hours_before', '') ~ '^[0-9]+$' then
    v_open_hours := greatest(1, least(720, (v_config ->> 'availability_open_hours_before')::integer));
  end if;
  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_default_squad_size := greatest(1, least(30, (v_config ->> 'usual_squad_size')::integer));
  end if;

  v_opens_at := v_kickoff_at - make_interval(hours => v_open_hours);
  v_computed_state := case
    when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
    when now() >= v_opens_at then 'open'::public.sport_availability_state
    else 'pending'::public.sport_availability_state
  end;

  insert into public.match_sport_workflows as workflow (
    match_id, availability_state, availability_opens_at, availability_opened_at,
    squad_size_limit, created_by, updated_by
  ) values (
    p_match_id, v_computed_state, v_opens_at,
    case when v_computed_state = 'open' then now() else null end,
    v_default_squad_size, v_actor, v_actor
  )
  on conflict (match_id) do update
  set availability_opens_at = excluded.availability_opens_at,
      availability_state = case
        when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
        when workflow.availability_state = 'open' then 'open'::public.sport_availability_state
        when now() >= v_opens_at then 'open'::public.sport_availability_state
        else 'pending'::public.sport_availability_state
      end,
      availability_opened_at = case
        when workflow.availability_opened_at is not null then workflow.availability_opened_at
        when now() >= v_opens_at and now() < v_kickoff_at then now()
        else null
      end,
      updated_by = v_actor,
      updated_at = now()
  returning availability_state, availability_opened_at
  into v_saved_state, v_opened_at;

  -- Drop players who left the roster OR who are now coaches.
  update public.match_sport_participants participant
  set is_eligible = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.season_player_id is not null
    and participant.is_eligible
    and not exists (
      select 1
      from public.season_players player
      where player.id = participant.season_player_id
        and player.season_id = v_season_id
        and player.is_active
        and not player.is_coach
    );

  insert into public.match_sport_participants as participant (
    match_id, season_player_id, is_eligible
  )
  select p_match_id, player.id, not player.is_coach
  from public.season_players player
  where player.season_id = v_season_id
    and player.is_active
  on conflict (match_id, season_player_id) do update
  set is_eligible = excluded.is_eligible,
      updated_at = case
        when participant.is_eligible = excluded.is_eligible then participant.updated_at
        else now()
      end;

  select count(*)::integer into v_eligible_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return jsonb_build_object(
    'match_id', p_match_id,
    'availability_state', v_saved_state,
    'availability_opens_at', v_opens_at,
    'availability_opened_at', v_opened_at,
    'kickoff_at', v_kickoff_at,
    'squad_size_limit', (
      select workflow.squad_size_limit
      from public.match_sport_workflows workflow
      where workflow.match_id = p_match_id
    ),
    'eligible_participant_count', v_eligible_count
  );
end;
$function$;

-- Allow a coach (ineligible participant) to still read his availability card.
create or replace function private.get_my_match_availability(p_match_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', participant.match_id,
    'participant_id', participant.id,
    'season_player_id', participant.season_player_id,
    'is_eligible', participant.is_eligible,
    'availability_status', participant.availability_status,
    'private_comment', participant.availability_comment_private,
    'availability_updated_at', participant.availability_updated_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'kickoff_at', match.kickoff_at,
    'can_respond', (participant.is_eligible or player.is_coach)
      and now() >= workflow.availability_opens_at
      and now() < match.kickoff_at
      and workflow.availability_state <> 'closed',
    'composition_state', workflow.composition_state,
    'convocation_state', workflow.convocation_state,
    'convocation_status', case
      when workflow.convocation_state = 'published' and participant.is_eligible
        then participant.convocation_status::text
      else null
    end
  ) into v_result
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id and player.profile_id = v_actor;

  if v_result is null then
    raise exception 'Match participant not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

-- Allow a coach to set his availability without touching convocation logic.
create or replace function private.set_my_match_availability(p_match_id uuid, p_status text, p_private_comment text DEFAULT NULL::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_is_eligible boolean;
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

  select participant.id, participant.is_eligible, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_is_eligible, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_composition_state, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and (participant.is_eligible or player.is_coach)
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

    -- Coaches are ineligible: their availability never affects convocations.
    if v_is_eligible then
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
$function$;;
