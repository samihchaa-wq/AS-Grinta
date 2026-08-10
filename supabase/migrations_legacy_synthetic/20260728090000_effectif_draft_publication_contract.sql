-- Separate private squad drafts from player-visible published convocations.
-- Existing participant convocation columns remain the published source of truth.

create table if not exists private.match_effectif_drafts (
  match_id uuid primary key
    references public.matches(id) on delete cascade,
  squad_size_limit smallint not null
    check (squad_size_limit between 1 and 30),
  has_unpublished_changes boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table if not exists private.match_effectif_draft_entries (
  match_id uuid not null
    references private.match_effectif_drafts(match_id) on delete cascade,
  season_player_id uuid not null
    references public.season_players(id) on delete cascade,
  status public.sport_convocation_status not null
    check (status in ('convoked', 'not_convoked')),
  primary key (match_id, season_player_id)
);

revoke all on table private.match_effectif_drafts
  from public, anon, authenticated;
revoke all on table private.match_effectif_draft_entries
  from public, anon, authenticated;

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
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_kickoff_at timestamptz;
  v_match_status text;
  v_published_limit integer;
  v_convocation_state public.sport_convocation_state;
  v_expected_count integer;
  v_input_count integer;
  v_invalid_count integer;
  v_has_changes boolean;
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

  select match.kickoff_at, match.status, workflow.squad_size_limit,
    workflow.convocation_state
  into v_kickoff_at, v_match_status, v_published_limit, v_convocation_state
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

  create temporary table if not exists pg_temp.effectif_draft_input (
    season_player_id uuid primary key,
    status public.sport_convocation_status not null
  ) on commit drop;
  truncate table pg_temp.effectif_draft_input;

  begin
    insert into pg_temp.effectif_draft_input(season_player_id, status)
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
  from pg_temp.effectif_draft_input;

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
  from pg_temp.effectif_draft_input input
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

  insert into private.match_effectif_drafts(
    match_id, squad_size_limit, has_unpublished_changes, updated_at, updated_by
  ) values (
    p_match_id, p_squad_size_limit, true, now(), v_actor
  )
  on conflict (match_id) do update
  set squad_size_limit = excluded.squad_size_limit,
      updated_at = now(),
      updated_by = excluded.updated_by;

  delete from private.match_effectif_draft_entries
  where match_id = p_match_id;

  insert into private.match_effectif_draft_entries(
    match_id, season_player_id, status
  )
  select p_match_id, season_player_id, status
  from pg_temp.effectif_draft_input;

  select
    v_convocation_state <> 'published'
    or v_published_limit is distinct from p_squad_size_limit
    or exists (
      select 1
      from public.match_sport_participants participant
      join pg_temp.effectif_draft_input input
        on input.season_player_id = participant.season_player_id
      where participant.match_id = p_match_id
        and participant.convocation_status is distinct from input.status
    )
  into v_has_changes;

  update private.match_effectif_drafts
  set has_unpublished_changes = v_has_changes,
      updated_at = now(),
      updated_by = v_actor
  where match_id = p_match_id;

  update public.match_sport_workflows
  set updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'save_match_effectif_draft',
    v_actor,
    v_reason,
    jsonb_build_object(
      'squad_size_limit', p_squad_size_limit,
      'convoked_count', (
        select count(*) from pg_temp.effectif_draft_input
        where status = 'convoked'
      ),
      'waitlisted_count', (
        select count(*) from pg_temp.effectif_draft_input
        where status = 'not_convoked'
      ),
      'has_unpublished_changes', v_has_changes
    )
  );

  return private.get_match_convocations(p_match_id);
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
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_has_changes boolean;
  v_result jsonb;
begin
  perform private.save_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    coalesce(v_reason, 'Préparation de la publication des convocations')
  );

  select draft.has_unpublished_changes
  into v_has_changes
  from private.match_effectif_drafts draft
  where draft.match_id = p_match_id
  for update;

  if not coalesce(v_has_changes, false) then
    return private.get_match_convocations(p_match_id);
  end if;

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants participant
  set convocation_status = draft.status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = draft.status = 'not_convoked',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when draft.status = 'not_convoked'
          then 'pending'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from private.match_effectif_draft_entries draft
  where draft.match_id = p_match_id
    and participant.match_id = p_match_id
    and participant.season_player_id = draft.season_player_id
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
    coalesce(v_reason, 'Publication explicite des convocations')
  );

  update private.match_effectif_drafts
  set has_unpublished_changes = false,
      updated_at = now(),
      updated_by = v_actor
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'publish_match_effectif',
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

create or replace function private.get_match_convocations(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
  ) and not exists (
    select 1
    from private.match_effectif_drafts draft
    where draft.match_id = p_match_id
      and draft.has_unpublished_changes
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', case
      when coalesce(draft.has_unpublished_changes, false)
        then draft.squad_size_limit
      else workflow.squad_size_limit
    end,
    'published_squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'has_unpublished_changes', coalesce(draft.has_unpublished_changes, false),
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', coalesce(players.available_count, 0),
    'convoked_count', coalesce(players.convoked_count, 0),
    'not_convoked_count', coalesce(players.not_convoked_count, 0),
    'players', coalesce(players.items, '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join private.match_effectif_drafts draft on draft.match_id = match.id
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
          and row.effective_status = 'convoked'
          and (
            row.availability_status = 'available'
            or row.guest_player_id is not null
          )
      )::integer as convoked_count,
      count(*) filter (
        where row.is_eligible
          and row.season_player_id is not null
          and row.availability_status = 'available'
          and row.effective_status = 'not_convoked'
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
          'convocation_status', row.effective_status,
          'published_convocation_status', row.published_status,
          'manual_override', row.effective_manual_override,
          'waitlist_position', row.waitlist_position,
          'waitlist_position_snapshot', row.waitlist_position_snapshot,
          'recommended_not_convoked', row.effective_recommended_not_convoked,
          'turn_should_consume', row.effective_turn_should_consume,
          'turn_state', row.effective_turn_state,
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
          else coalesce(nullif(btrim(profile.surnom), ''), btrim(player.first_name))
        end as display_name,
        coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
        participant.availability_status,
        participant.availability_updated_at,
        participant.convocation_status as published_status,
        case
          when coalesce(draft.has_unpublished_changes, false)
               and participant.guest_player_id is not null
            then 'convoked'::public.sport_convocation_status
          when coalesce(draft.has_unpublished_changes, false)
               and participant.season_player_id is not null
               and participant.availability_status = 'available'
            then coalesce(draft_entry.status, participant.convocation_status)
          when coalesce(draft.has_unpublished_changes, false)
            then 'not_applicable'::public.sport_convocation_status
          else participant.convocation_status
        end as effective_status,
        case
          when coalesce(draft.has_unpublished_changes, false)
               and (
                 participant.guest_player_id is not null
                 or participant.availability_status = 'available'
               ) then true
          else participant.convocation_manual_override
        end as effective_manual_override,
        waitlist.position as waitlist_position,
        participant.waitlist_position_snapshot,
        case
          when coalesce(draft.has_unpublished_changes, false) then false
          else participant.waitlist_recommended_not_convoked
        end as effective_recommended_not_convoked,
        case
          when coalesce(draft.has_unpublished_changes, false)
            then participant.season_player_id is not null
              and participant.availability_status = 'available'
              and coalesce(draft_entry.status, participant.convocation_status) = 'not_convoked'
          else participant.waitlist_turn_should_consume
        end as effective_turn_should_consume,
        case
          when coalesce(draft.has_unpublished_changes, false)
               and participant.waitlist_turn_state = 'consumed'
            then 'consumed'::public.sport_waitlist_turn_state
          when coalesce(draft.has_unpublished_changes, false)
               and participant.season_player_id is not null
               and participant.availability_status = 'available'
               and coalesce(draft_entry.status, participant.convocation_status) = 'not_convoked'
            then 'pending'::public.sport_waitlist_turn_state
          when coalesce(draft.has_unpublished_changes, false)
               and (
                 participant.guest_player_id is not null
                 or participant.availability_status = 'available'
               )
            then 'waived'::public.sport_waitlist_turn_state
          when coalesce(draft.has_unpublished_changes, false)
            then 'not_applicable'::public.sport_waitlist_turn_state
          else participant.waitlist_turn_state
        end as effective_turn_state,
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
      left join private.match_effectif_draft_entries draft_entry
        on draft_entry.match_id = participant.match_id
       and draft_entry.season_player_id = participant.season_player_id
      where participant.match_id = match.id
    ) row
  ) players on true
  where match.id = p_match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function private.publish_match_composition(
  p_match_id uuid,
  p_allow_squad_size_exception boolean default false,
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
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_convocation_state public.sport_convocation_state;
  v_effectif_dirty boolean;
  v_current_version integer;
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

  select match.status, match.kickoff_at, workflow.squad_size_limit,
    workflow.convocation_state,
    coalesce(draft.has_unpublished_changes, false), composition.version
  into v_match_status, v_kickoff_at, v_squad_limit,
    v_convocation_state, v_effectif_dirty, v_current_version
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  join public.match_compositions composition on composition.match_id = match.id
  left join private.match_effectif_drafts draft on draft.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow, composition;

  if not found then
    raise exception 'Composition draft not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be published for this match state'
      using errcode = '22023';
  end if;
  if v_match_status = 'a_venir' and v_convocation_state <> 'published' then
    raise exception 'Publish convocations before publishing the composition'
      using errcode = '22023';
  end if;
  if v_match_status = 'a_venir' and v_effectif_dirty then
    raise exception 'Publish pending convocation changes before publishing the composition'
      using errcode = '22023';
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
    (select formation_code
     from public.match_compositions
     where match_id = p_match_id),
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
      else 'publish_composition'
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
$function$;

create or replace function public.admin_publish_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.publish_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
$function$;

revoke execute on function private.publish_match_effectif(uuid, integer, jsonb, text)
  from public, anon;
revoke execute on function public.admin_publish_match_effectif(uuid, integer, jsonb, text)
  from public, anon;

grant execute on function private.publish_match_effectif(uuid, integer, jsonb, text)
  to authenticated, service_role;
grant execute on function public.admin_publish_match_effectif(uuid, integer, jsonb, text)
  to authenticated, service_role;

comment on function public.admin_save_match_effectif(uuid, integer, jsonb, text) is
  'Stores a private effectif draft without changing player-visible published convocations.';
comment on function public.admin_publish_match_effectif(uuid, integer, jsonb, text) is
  'Atomically stores and explicitly publishes the current effectif decisions.';
