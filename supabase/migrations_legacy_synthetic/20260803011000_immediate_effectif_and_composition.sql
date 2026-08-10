-- Effectif and composition changes are now immediately visible.
-- There is no persistent draft/publication workflow anymore for these screens.

-- ---------------------------------------------------------------------------
-- Effectif: direct validated write
-- ---------------------------------------------------------------------------

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
as $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_kickoff_at timestamptz;
  v_match_status text;
  v_expected_count integer;
  v_input_count integer;
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
    when invalid_text_representation then
      raise exception 'Invalid effectif decision' using errcode = '22023';
  end;

  select count(*)::integer into v_input_count
  from pg_temp.effectif_input;

  select count(*)::integer into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status = 'available';

  if v_input_count <> v_expected_count then
    raise exception 'Every available permanent player needs one effectif decision'
      using errcode = '22023';
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
    raise exception 'Effectif contains an unavailable or ineligible player'
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
      waitlist_turn_should_consume = input.status = 'not_convoked',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when input.status = 'not_convoked'
          then 'pending'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from pg_temp.effectif_input input
  where participant.match_id = p_match_id
    and participant.season_player_id = input.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available';

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
    and participant.availability_status <> 'available';

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
$$;

-- Backward-compatible name: an old "save" call now performs the exact same
-- immediate publication. It can never create a private draft.
create or replace function private.save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language sql
security definer
set search_path to ''
as $$
  select private.publish_match_effectif(
    p_match_id, p_squad_size_limit, p_decisions, p_reason
  );
$$;

create or replace function public.admin_save_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language sql
set search_path to ''
as $$
  select private.publish_match_effectif(
    p_match_id, p_squad_size_limit, p_decisions, p_reason
  );
$$;

-- ---------------------------------------------------------------------------
-- Effectif read model without any draft overlay
-- ---------------------------------------------------------------------------

create or replace function private.get_match_convocations(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
      and workflow.convocation_state = 'draft'
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', coalesce(opponent.name, 'Match entre nous'),
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'published_squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'has_unpublished_changes', false,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', coalesce(players.available_count, 0),
    'convoked_count', coalesce(players.convoked_count, 0),
    'not_convoked_count', coalesce(players.not_convoked_count, 0),
    'players', coalesce(players.items, '[]'::jsonb)
  )
  into v_result
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join lateral (
    select
      count(*) filter (
        where row.is_eligible
          and (
            (row.season_player_id is not null and row.availability_status = 'available')
            or row.guest_player_id is not null
          )
      )::integer as available_count,
      count(*) filter (
        where row.is_eligible
          and row.convocation_status = 'convoked'
          and (
            row.availability_status = 'available'
            or row.guest_player_id is not null
          )
      )::integer as convoked_count,
      count(*) filter (
        where row.is_eligible
          and row.season_player_id is not null
          and row.availability_status = 'available'
          and row.convocation_status = 'not_convoked'
      )::integer as not_convoked_count,
      jsonb_agg(
        jsonb_build_object(
          'participant_id', row.participant_id,
          'season_player_id', row.season_player_id,
          'guest_player_id', row.guest_player_id,
          'first_name', row.first_name,
          'last_name', row.last_name,
          'display_name', row.display_name,
          'is_guest', row.guest_player_id is not null,
          'is_goalkeeper', row.is_goalkeeper,
          'availability_status', row.availability_status,
          'availability_updated_at', row.availability_updated_at,
          'convocation_status', row.convocation_status,
          'published_convocation_status', row.convocation_status,
          'manual_override', row.convocation_manual_override,
          'waitlist_position', row.waitlist_position,
          'waitlist_position_snapshot', row.waitlist_position_snapshot,
          'current_season_waitlist_count', row.current_season_waitlist_count,
          'recommended_not_convoked', row.waitlist_recommended_not_convoked,
          'turn_should_consume', row.waitlist_turn_should_consume,
          'turn_state', row.waitlist_turn_state,
          'promoted_after_withdrawal_at', row.promoted_after_withdrawal_at
        )
        order by row.availability_order, row.waitlist_position,
          lower(row.first_name), lower(coalesce(row.last_name, ''))
      ) filter (where row.participant_id is not null and row.is_eligible) as items
    from (
      select
        participant.id as participant_id,
        participant.season_player_id,
        participant.guest_player_id,
        participant.is_eligible,
        coalesce(player.first_name, guest.first_name) as first_name,
        coalesce(player.last_name, guest.last_name) as last_name,
        case
          when guest.id is not null then btrim(guest.first_name) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''),
            nullif(btrim(profile.first_name), ''),
            btrim(player.first_name)
          )
        end as display_name,
        coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
        participant.availability_status,
        participant.availability_updated_at,
        participant.convocation_status,
        participant.convocation_manual_override,
        waitlist.position as waitlist_position,
        participant.waitlist_position_snapshot,
        coalesce(waitlist.manual_waitlist_count, 0) as current_season_waitlist_count,
        participant.waitlist_recommended_not_convoked,
        participant.waitlist_turn_should_consume,
        participant.waitlist_turn_state,
        participant.promoted_after_withdrawal_at,
        case
          when participant.guest_player_id is not null then 0
          when participant.availability_status = 'available' then 0
          when participant.availability_status = 'no_response' then 1
          when participant.availability_status = 'absent' then 2
          else 3
        end as availability_order
      from public.match_sport_participants participant
      left join public.season_players player
        on player.id = participant.season_player_id
      left join public.profiles profile on profile.id = player.profile_id
      left join public.guest_players guest
        on guest.id = participant.guest_player_id
      left join public.sport_waitlist_entries waitlist
        on waitlist.season_player_id = participant.season_player_id
       and waitlist.season_id = match.season_id
      where participant.match_id = match.id
    ) row
  ) players on true
  where match.id = p_match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Composition: a save is an atomic save + publication
-- ---------------------------------------------------------------------------

create or replace function private.publish_match_composition(
  p_match_id uuid,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_match_status text;
  v_squad_limit integer;
  v_convocation_state public.sport_convocation_state;
  v_current_version integer;
  v_has_unpublished_changes boolean;
  v_field_count integer;
  v_bench_count integer;
  v_available_count integer;
  v_selected_count integer;
  v_exception_used boolean;
  v_publication_kind text;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.status, workflow.squad_size_limit,
    workflow.convocation_state, composition.version,
    composition.has_unpublished_changes
  into v_match_status, v_squad_limit,
    v_convocation_state, v_current_version, v_has_unpublished_changes
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  join public.match_compositions composition on composition.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow, composition;

  if not found then
    raise exception 'Composition not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be published for this match state'
      using errcode = '22023';
  end if;
  if v_match_status = 'a_venir' and v_convocation_state <> 'published' then
    raise exception 'Convocations must be available before the composition'
      using errcode = '22023';
  end if;

  -- Compatibility with the old client, which may call publish immediately
  -- after save. The save is already published atomically, so this is a no-op.
  if v_current_version > 0 and not coalesce(v_has_unpublished_changes, false) then
    return private.composition_snapshot(p_match_id);
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone = 'bench'),
    count(*) filter (where zone = 'available')
  into v_field_count, v_bench_count, v_available_count
  from public.match_composition_entries
  where match_id = p_match_id;

  v_selected_count := v_field_count + v_bench_count;
  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_available_count > 0 then
    raise exception 'Every selected player must be placed on the field or bench before publication'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;

  v_exception_used := v_selected_count > v_squad_limit;
  v_publication_kind := case
    when v_match_status in ('termine', 'archive') then 'postmatch'
    when v_current_version = 0 then 'initial'
    else 'update'
  end;

  update public.match_compositions composition
  set status = case
        when v_current_version = 0
          then 'published'::public.sport_composition_state
        else 'updated'::public.sport_composition_state
      end,
      version = v_current_version + 1,
      has_unpublished_changes = false,
      squad_size_exception_approved = v_exception_used,
      published_at = now(),
      published_by = v_actor,
      last_modified_at = now(),
      last_modified_by = v_actor
  where composition.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = case
        when v_current_version = 0
          then 'published'::public.sport_composition_state
        else 'updated'::public.sport_composition_state
      end,
      composition_version = v_current_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', v_publication_kind
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot, publication_kind, published_by
  ) values (
    p_match_id,
    v_current_version + 1,
    (select formation_code from public.match_compositions where match_id = p_match_id),
    v_snapshot,
    v_publication_kind,
    v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_match_status in ('termine', 'archive')
      then 'publish_postmatch_composition'
      else 'update_composition'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_current_version + 1,
      'publication_kind', v_publication_kind,
      'field_count', v_field_count,
      'bench_count', v_bench_count,
      'match_status', v_match_status
    )
  );

  return v_snapshot;
end;
$$;

create or replace function public.admin_save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
set search_path to ''
as $$
begin
  perform private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
  return private.publish_match_composition(
    p_match_id,
    p_allow_squad_size_exception,
    p_reason
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Remove obsolete effectif/squad-plan draft storage
-- ---------------------------------------------------------------------------

drop function if exists public.admin_save_match_squad_plan(uuid, text, jsonb, text);
drop function if exists public.admin_publish_match_squad_plan(uuid, text, jsonb, text);
drop function if exists private.save_match_squad_plan(uuid, text, jsonb, text);
drop function if exists private.publish_match_squad_plan(uuid, text, jsonb, text);

-- Keep account deletion intact after the private draft tables disappear.
create or replace function private.prepare_profile_for_hard_deletion(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_system_actor constant uuid := '00000000-0000-0000-0000-000000000001'::uuid;
begin
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;
  if p_profile_id = v_system_actor then
    raise exception 'Technical profile cannot be deleted' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = v_system_actor) then
    raise exception 'Technical replacement profile is missing' using errcode = '55000';
  end if;

  delete from public.sport_availability_notification_events
  where profile_id = p_profile_id;

  delete from public.match_sport_motm_votes
  where voter_profile_id = p_profile_id;

  update private.sport_admin_audit_log
  set actor_profile_id = v_system_actor
  where actor_profile_id = p_profile_id;

  update public.guest_players
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.guest_players
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

  update public.match_composition_publications
  set published_by = v_system_actor
  where published_by = p_profile_id;

  update public.match_compositions
  set last_modified_by = v_system_actor
  where last_modified_by = p_profile_id;
  update public.match_compositions
  set published_by = v_system_actor
  where published_by = p_profile_id;

  update public.match_sport_finalization_versions
  set created_by = v_system_actor
  where created_by = p_profile_id;

  update public.match_sport_finalizations
  set validated_by = v_system_actor
  where validated_by = p_profile_id;
  update public.match_sport_finalizations
  set corrected_by = null
  where corrected_by = p_profile_id;

  update public.match_sport_workflows
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.match_sport_workflows
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  update public.sport_waitlist_entries
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.sport_waitlist_entries
  set updated_by = v_system_actor
  where updated_by = p_profile_id;
end;
$$;

drop table if exists private.match_effectif_draft_entries;
drop table if exists private.match_effectif_drafts;
