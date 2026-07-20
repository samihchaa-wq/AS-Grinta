-- Sports-management reusable guests and match guest participants.
-- Additive and inert while the sports_management feature flag is disabled.

create table public.guest_players (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text,
  is_goalkeeper boolean not null default false,
  is_reusable boolean not null default true,
  archived_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(btrim(first_name)) between 1 and 80),
  check (last_name is null or char_length(btrim(last_name)) between 1 and 80),
  check (
    (is_reusable and archived_at is null)
    or (not is_reusable and archived_at is not null)
  )
);

comment on table public.guest_players is
  'Reusable guest catalog. Archiving never removes historical match references.';
comment on column public.guest_players.is_goalkeeper is
  'Used by composition warnings and later final attendance/statistics workflows.';

alter table public.match_sport_participants
  alter column season_player_id drop not null,
  add column guest_player_id uuid references public.guest_players(id) on delete restrict;

alter table public.match_sport_participants
  add constraint match_sport_participants_exactly_one_identity_check
  check (num_nonnulls(season_player_id, guest_player_id) = 1),
  add constraint match_sport_participants_guest_availability_check
  check (guest_player_id is null or availability_status = 'not_applicable');

create unique index match_sport_participants_match_guest_uidx
  on public.match_sport_participants(match_id, guest_player_id)
  where guest_player_id is not null;

create index guest_players_active_name_idx
  on public.guest_players(
    lower(btrim(first_name)),
    lower(coalesce(btrim(last_name), ''))
  )
  where is_reusable;

create index match_sport_participants_guest_idx
  on public.match_sport_participants(guest_player_id)
  where guest_player_id is not null;

alter table public.guest_players enable row level security;

revoke all on table public.guest_players from public, anon, authenticated;
grant select on table public.guest_players to authenticated;
grant select, insert, update on table public.guest_players to service_role;

create policy guest_players_admin_select
on public.guest_players for select to authenticated
using (
  (select private.is_feature_enabled('sports_management'))
  and (select private.is_admin())
);

create or replace function private.sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
    v_open_hours := greatest(
      1,
      least(720, (v_config ->> 'availability_open_hours_before')::integer)
    );
  end if;
  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_default_squad_size := greatest(
      1,
      least(30, (v_config ->> 'usual_squad_size')::integer)
    );
  end if;

  v_opens_at := v_kickoff_at - make_interval(hours => v_open_hours);
  v_computed_state := case
    when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
    when now() >= v_opens_at then 'open'::public.sport_availability_state
    else 'pending'::public.sport_availability_state
  end;

  insert into public.match_sport_workflows as workflow (
    match_id,
    availability_state,
    availability_opens_at,
    availability_opened_at,
    squad_size_limit,
    created_by,
    updated_by
  ) values (
    p_match_id,
    v_computed_state,
    v_opens_at,
    case when v_computed_state = 'open' then now() else null end,
    v_default_squad_size,
    v_actor,
    v_actor
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

  -- Synchronisation du seul effectif permanent. Les invités restent liés au match.
  update public.match_sport_participants participant
  set is_eligible = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.season_player_id is not null
    and participant.is_eligible
    and not exists (
      select 1
      from public.season_players player
      join public.profiles profile on profile.id = player.profile_id
      where player.id = participant.season_player_id
        and player.season_id = v_season_id
        and player.is_active
        and profile.status = 'active'
    );

  insert into public.match_sport_participants as participant (
    match_id,
    season_player_id,
    is_eligible
  )
  select p_match_id, player.id, true
  from public.season_players player
  join public.profiles profile on profile.id = player.profile_id
  where player.season_id = v_season_id
    and player.is_active
    and profile.status = 'active'
  on conflict (match_id, season_player_id) do update
  set is_eligible = true,
      updated_at = case
        when participant.is_eligible then participant.updated_at
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
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', count(*) filter (
      where participant.is_eligible
        and (
          (
            participant.season_player_id is not null
            and participant.availability_status = 'available'
          )
          or participant.guest_player_id is not null
        )
    ),
    'convoked_count', count(*) filter (
      where participant.is_eligible
        and participant.convocation_status = 'convoked'
        and (
          participant.availability_status = 'available'
          or participant.guest_player_id is not null
        )
    ),
    'not_convoked_count', count(*) filter (
      where participant.is_eligible
        and participant.season_player_id is not null
        and participant.availability_status = 'available'
        and participant.convocation_status = 'not_convoked'
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end,
        'is_guest', guest.id is not null,
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'availability_status', participant.availability_status,
        'availability_updated_at', participant.availability_updated_at,
        'convocation_status', participant.convocation_status,
        'manual_override', participant.convocation_manual_override,
        'waitlist_position', waitlist.position,
        'waitlist_position_snapshot', participant.waitlist_position_snapshot,
        'recommended_not_convoked', participant.waitlist_recommended_not_convoked,
        'turn_should_consume', participant.waitlist_turn_should_consume,
        'turn_state', participant.waitlist_turn_state,
        'promoted_after_withdrawal_at', participant.promoted_after_withdrawal_at
      )
      order by
        case
          when participant.guest_player_id is not null then 0
          when participant.availability_status = 'available' then 0
          when participant.availability_status = 'no_response' then 1
          when participant.availability_status = 'absent' then 2
          else 3
        end,
        waitlist.position,
        lower(coalesce(player.first_name, guest.first_name)),
        lower(coalesce(player.last_name, guest.last_name, ''))
    ) filter (
      where participant.id is not null
        and participant.is_eligible
    ), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function private.composition_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'match_id', composition.match_id,
    'formation_code', composition.formation_code,
    'status', composition.status,
    'version', composition.version,
    'has_unpublished_changes', composition.has_unpublished_changes,
    'squad_size_exception_approved', composition.squad_size_exception_approved,
    'published_at', composition.published_at,
    'last_modified_at', composition.last_modified_at,
    'field_count', count(*) filter (where entry.zone = 'field'),
    'bench_count', count(*) filter (where entry.zone = 'bench'),
    'not_selected_count', count(*) filter (where entry.zone = 'not_selected'),
    'available_count', count(*) filter (where entry.zone = 'available'),
    'has_goalkeeper_warning', not coalesce(bool_or(
      entry.zone = 'field'
      and coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
    ), false),
    'entries', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'participant_id', participant.id,
          'season_player_id', participant.season_player_id,
          'guest_player_id', participant.guest_player_id,
          'display_name', case
            when guest.id is not null then
              btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
            else btrim(concat_ws(' ', player.first_name, player.last_name))
          end,
          'is_guest', guest.id is not null,
          'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
          'zone', entry.zone,
          'x', entry.x,
          'y', entry.y,
          'slot_label', entry.slot_label,
          'sort_order', entry.sort_order,
          'availability_status', participant.availability_status,
          'convocation_status', participant.convocation_status,
          'selection_status', participant.selection_status
        ) order by
          case entry.zone
            when 'field' then 1
            when 'bench' then 2
            when 'available' then 3
            else 4
          end,
          entry.sort_order,
          lower(coalesce(player.first_name, guest.first_name)),
          participant.id
      ) filter (where entry.participant_id is not null),
      '[]'::jsonb
    )
  ) into v_result
  from public.match_compositions composition
  left join public.match_composition_entries entry
    on entry.match_id = composition.match_id
  left join public.match_sport_participants participant
    on participant.id = entry.participant_id
   and participant.match_id = entry.match_id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  where composition.match_id = p_match_id
  group by composition.match_id;

  return v_result;
end;
$function$;

create or replace function private.save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
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
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_expected_count integer;
  v_input_count integer;
  v_selected_count integer;
  v_field_count integer;
  v_invalid_identity_count integer;
  v_invalid_zone_count integer;
  v_exception_used boolean := false;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Composition entries must be a JSON array' using errcode = '22023';
  end if;
  if v_formation is not null and char_length(v_formation) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at, workflow.squad_size_limit
  into v_match_status, v_kickoff_at, v_squad_limit
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Composition can only be edited before kickoff' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.composition_input;

  begin
    insert into pg_temp.composition_input (
      participant_id, zone, x, y, slot_label, sort_order
    )
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a composition' using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count from pg_temp.composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once' using errcode = '22023';
  end if;

  select count(*) into v_invalid_identity_count
  from pg_temp.composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and participant.is_eligible
  where participant.id is null;
  if v_invalid_identity_count > 0 then
    raise exception 'Composition contains an ineligible participant' using errcode = '22023';
  end if;

  select count(*) into v_invalid_zone_count
  from pg_temp.composition_input input
  join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
  where
    (
      input.zone = 'field'
      and (
        input.x is null
        or input.y is null
        or input.x < 0
        or input.x > 1
        or input.y < 0
        or input.y > 1
      )
    )
    or (
      input.zone <> 'field'
      and (input.x is not null or input.y is not null)
    )
    or (
      input.zone in ('field', 'bench', 'available')
      and (
        participant.convocation_status <> 'convoked'
        or (
          participant.season_player_id is not null
          and participant.availability_status <> 'available'
        )
        or (
          participant.guest_player_id is not null
          and participant.availability_status <> 'not_applicable'
        )
      )
    )
    or (
      input.zone = 'not_selected'
      and participant.convocation_status = 'convoked'
    );

  if v_invalid_zone_count > 0 then
    raise exception 'Composition zones conflict with availability or convocation decisions'
      using errcode = '22023';
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.composition_input;

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
    and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  insert into public.match_compositions (
    match_id,
    formation_code,
    status,
    version,
    has_unpublished_changes,
    squad_size_exception_approved,
    last_modified_by
  ) values (
    p_match_id,
    v_formation,
    'draft',
    0,
    true,
    v_exception_used,
    v_actor
  )
  on conflict (match_id) do update
  set formation_code = excluded.formation_code,
      has_unpublished_changes = true,
      squad_size_exception_approved = excluded.squad_size_exception_approved,
      last_modified_at = now(),
      last_modified_by = excluded.last_modified_by;

  create temporary table if not exists pg_temp.composition_old_selection (
    participant_id uuid primary key,
    old_status public.sport_selection_status not null
  ) on commit drop;
  truncate table pg_temp.composition_old_selection;

  insert into pg_temp.composition_old_selection(participant_id, old_status)
  select participant.id, participant.selection_status
  from public.match_sport_participants participant
  where participant.match_id = p_match_id;

  delete from public.match_composition_entries entry
  where entry.match_id = p_match_id;

  insert into public.match_composition_entries (
    match_id,
    participant_id,
    zone,
    x,
    y,
    slot_label,
    sort_order
  )
  select
    p_match_id,
    input.participant_id,
    input.zone,
    input.x,
    input.y,
    input.slot_label,
    input.sort_order
  from pg_temp.composition_input input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        when 'not_selected' then 'not_selected'::public.sport_selection_status
        else 'undecided'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.composition_input input
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
    'selection_changed',
    jsonb_build_object('status', old_selection.old_status),
    jsonb_build_object('status', participant.selection_status),
    v_actor,
    'staff'
  from public.match_sport_participants participant
  join pg_temp.composition_old_selection old_selection
    on old_selection.participant_id = participant.id
  where participant.match_id = p_match_id
    and old_selection.old_status is distinct from participant.selection_status;

  update public.match_sport_workflows workflow
  set composition_state = case
        when workflow.composition_state = 'none'
          then 'draft'::public.sport_composition_state
        else workflow.composition_state
      end,
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
    case
      when v_exception_used then 'save_composition_exception'
      else 'save_composition_draft'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'formation_code', v_formation,
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'squad_size_limit', v_squad_limit,
      'exception_used', v_exception_used
    )
  );

  return private.composition_snapshot(p_match_id);
end;
$function$;

create or replace function private.get_guest_players(
  p_include_archived boolean default false
)
returns jsonb
language plpgsql
stable
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

  select jsonb_build_object(
    'guests', coalesce(jsonb_agg(
      jsonb_build_object(
        'guest_player_id', guest.id,
        'first_name', guest.first_name,
        'last_name', guest.last_name,
        'display_name',
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)',
        'is_goalkeeper', guest.is_goalkeeper,
        'is_reusable', guest.is_reusable,
        'archived_at', guest.archived_at,
        'created_at', guest.created_at,
        'updated_at', guest.updated_at
      )
      order by
        guest.is_reusable desc,
        lower(guest.first_name),
        lower(coalesce(guest.last_name, '')),
        guest.created_at
    ), '[]'::jsonb)
  )
  into v_result
  from public.guest_players guest
  where p_include_archived or guest.is_reusable;

  return v_result;
end;
$function$;

create or replace function private.get_match_guests(p_match_id uuid)
returns jsonb
language plpgsql
stable
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

  if not exists (
    select 1 from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
  ) then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'match_id', p_match_id,
    'guests', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'guest_player_id', guest.id,
        'first_name', guest.first_name,
        'last_name', guest.last_name,
        'display_name',
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)',
        'is_goalkeeper', guest.is_goalkeeper,
        'is_reusable', guest.is_reusable,
        'archived_at', guest.archived_at,
        'selection_status', participant.selection_status,
        'created_at', participant.created_at
      )
      order by lower(guest.first_name), lower(coalesce(guest.last_name, ''))
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.match_sport_participants participant
  join public.guest_players guest on guest.id = participant.guest_player_id
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return v_result;
end;
$function$;

create or replace function private.add_or_reuse_match_guest(
  p_match_id uuid,
  p_guest_player_id uuid default null,
  p_first_name text default null,
  p_last_name text default null,
  p_is_goalkeeper boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_first_name text := nullif(btrim(p_first_name), '');
  v_last_name text := nullif(btrim(p_last_name), '');
  v_reason text := nullif(btrim(p_reason), '');
  v_guest public.guest_players%rowtype;
  v_participant_id uuid;
  v_was_eligible boolean;
  v_created boolean := false;
  v_reactivated boolean := false;
  v_match_status text;
  v_kickoff_at timestamptz;
  v_sort_order integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at
  into v_match_status, v_kickoff_at
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Guests can only be managed before kickoff' using errcode = '22023';
  end if;

  if p_guest_player_id is not null then
    select guest.* into v_guest
    from public.guest_players guest
    where guest.id = p_guest_player_id
    for update;

    if not found then
      raise exception 'Guest player not found' using errcode = 'P0002';
    end if;
    if not v_guest.is_reusable then
      raise exception 'Archived guest must be restored before reuse' using errcode = '22023';
    end if;
  else
    if v_first_name is null then
      raise exception 'Guest first name is required' using errcode = '22023';
    end if;
    if char_length(v_first_name) > 80
      or (v_last_name is not null and char_length(v_last_name) > 80) then
      raise exception 'Guest name cannot exceed 80 characters per field'
        using errcode = '22023';
    end if;

    select guest.* into v_guest
    from public.guest_players guest
    where guest.is_reusable
      and lower(btrim(guest.first_name)) = lower(v_first_name)
      and lower(coalesce(btrim(guest.last_name), '')) =
          lower(coalesce(v_last_name, ''))
      and guest.is_goalkeeper = coalesce(p_is_goalkeeper, false)
    order by guest.created_at
    limit 1
    for update;

    if not found then
      insert into public.guest_players (
        first_name,
        last_name,
        is_goalkeeper,
        created_by,
        updated_by
      ) values (
        v_first_name,
        v_last_name,
        coalesce(p_is_goalkeeper, false),
        v_actor,
        v_actor
      )
      returning * into v_guest;
      v_created := true;
    end if;
  end if;

  select participant.id, participant.is_eligible
  into v_participant_id, v_was_eligible
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.guest_player_id = v_guest.id
  for update;

  if found then
    v_reactivated := not v_was_eligible;
    update public.match_sport_participants participant
    set is_eligible = true,
        availability_status = 'not_applicable',
        availability_comment_private = null,
        convocation_status = 'convoked',
        convocation_manual_override = true,
        waitlist_position_snapshot = null,
        waitlist_recommended_not_convoked = false,
        waitlist_turn_should_consume = false,
        waitlist_turn_state = 'not_applicable',
        selection_status = case
          when participant.is_eligible then participant.selection_status
          else 'undecided'::public.sport_selection_status
        end,
        updated_at = now()
    where participant.id = v_participant_id;
  else
    insert into public.match_sport_participants (
      match_id,
      guest_player_id,
      is_eligible,
      availability_status,
      convocation_status,
      convocation_manual_override,
      waitlist_turn_state
    ) values (
      p_match_id,
      v_guest.id,
      true,
      'not_applicable',
      'convoked',
      true,
      'not_applicable'
    )
    returning id into v_participant_id;
    v_reactivated := true;
  end if;

  if exists (
    select 1 from public.match_compositions composition
    where composition.match_id = p_match_id
  ) then
    select coalesce(max(entry.sort_order), -1) + 1
    into v_sort_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.zone = 'available';

    insert into public.match_composition_entries (
      match_id,
      participant_id,
      zone,
      sort_order
    ) values (
      p_match_id,
      v_participant_id,
      'available',
      coalesce(v_sort_order, 0)
    )
    on conflict (match_id, participant_id) do nothing;

    update public.match_compositions composition
    set has_unpublished_changes = true,
        last_modified_at = now(),
        last_modified_by = v_actor
    where composition.match_id = p_match_id;
  end if;

  if v_reactivated then
    insert into public.match_sport_participant_events (
      participant_id,
      match_id,
      event_type,
      old_value,
      new_value,
      actor_profile_id,
      actor_kind
    ) values (
      v_participant_id,
      p_match_id,
      'guest_added',
      jsonb_build_object('eligible', false),
      jsonb_build_object(
        'eligible', true,
        'guest_player_id', v_guest.id,
        'created_catalog_entry', v_created
      ),
      v_actor,
      'staff'
    );
  end if;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    case
      when v_created then 'create_and_add_guest'
      when v_reactivated then 'add_guest'
      else 'reuse_existing_match_guest'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'guest_player_id', v_guest.id,
      'participant_id', v_participant_id,
      'created_catalog_entry', v_created,
      'reactivated', v_reactivated
    )
  );

  return jsonb_build_object(
    'guest_player_id', v_guest.id,
    'participant_id', v_participant_id,
    'created_catalog_entry', v_created,
    'match_guests', private.get_match_guests(p_match_id)
  );
end;
$function$;

create or replace function private.remove_match_guest(
  p_match_id uuid,
  p_participant_id uuid,
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
  v_guest_player_id uuid;
  v_match_status text;
  v_kickoff_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at
  into v_match_status, v_kickoff_at
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Guests can only be managed before kickoff' using errcode = '22023';
  end if;

  select participant.guest_player_id into v_guest_player_id
  from public.match_sport_participants participant
  where participant.id = p_participant_id
    and participant.match_id = p_match_id
    and participant.guest_player_id is not null
    and participant.is_eligible
  for update;

  if not found then
    raise exception 'Active match guest not found' using errcode = 'P0002';
  end if;

  delete from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.participant_id = p_participant_id;

  update public.match_sport_participants participant
  set is_eligible = false,
      convocation_status = 'not_applicable',
      selection_status = 'not_selected',
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      final_presence_status = 'pending',
      final_presence_confirmed_at = null,
      final_presence_confirmed_by = null,
      updated_at = now()
  where participant.id = p_participant_id;

  update public.match_compositions composition
  set has_unpublished_changes = true,
      last_modified_at = now(),
      last_modified_by = v_actor
  where composition.match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id,
    match_id,
    event_type,
    old_value,
    new_value,
    actor_profile_id,
    actor_kind
  ) values (
    p_participant_id,
    p_match_id,
    'guest_removed',
    jsonb_build_object('eligible', true, 'guest_player_id', v_guest_player_id),
    jsonb_build_object('eligible', false, 'guest_player_id', v_guest_player_id),
    v_actor,
    'staff'
  );

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'remove_guest',
    v_actor,
    v_reason,
    jsonb_build_object(
      'guest_player_id', v_guest_player_id,
      'participant_id', p_participant_id
    )
  );

  return private.get_match_guests(p_match_id);
end;
$function$;

create or replace function private.set_guest_archived(
  p_guest_player_id uuid,
  p_archived boolean,
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
  v_old_reusable boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_archived is null then
    raise exception 'Archived state is required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select guest.is_reusable into v_old_reusable
  from public.guest_players guest
  where guest.id = p_guest_player_id
  for update;

  if not found then
    raise exception 'Guest player not found' using errcode = 'P0002';
  end if;

  update public.guest_players guest
  set is_reusable = not p_archived,
      archived_at = case when p_archived then now() else null end,
      updated_by = v_actor,
      updated_at = now()
  where guest.id = p_guest_player_id;

  insert into private.sport_admin_audit_log (
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    case when p_archived then 'archive_guest' else 'restore_guest' end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'guest_player_id', p_guest_player_id,
      'old_is_reusable', v_old_reusable,
      'new_is_reusable', not p_archived
    )
  );

  return private.get_guest_players(true);
end;
$function$;

create or replace function public.admin_get_guest_players(
  p_include_archived boolean default false
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_guest_players(p_include_archived);
$function$;

create or replace function public.admin_get_match_guests(p_match_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_match_guests(p_match_id);
$function$;

create or replace function public.admin_add_or_reuse_match_guest(
  p_match_id uuid,
  p_guest_player_id uuid default null,
  p_first_name text default null,
  p_last_name text default null,
  p_is_goalkeeper boolean default false,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.add_or_reuse_match_guest(
    p_match_id,
    p_guest_player_id,
    p_first_name,
    p_last_name,
    p_is_goalkeeper,
    p_reason
  );
$function$;

create or replace function public.admin_remove_match_guest(
  p_match_id uuid,
  p_participant_id uuid,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.remove_match_guest(p_match_id, p_participant_id, p_reason);
$function$;

create or replace function public.admin_set_guest_archived(
  p_guest_player_id uuid,
  p_archived boolean,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.set_guest_archived(p_guest_player_id, p_archived, p_reason);
$function$;

revoke execute on function private.get_guest_players(boolean) from public, anon;
revoke execute on function private.get_match_guests(uuid) from public, anon;
revoke execute on function private.add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text)
  from public, anon;
revoke execute on function private.remove_match_guest(uuid, uuid, text) from public, anon;
revoke execute on function private.set_guest_archived(uuid, boolean, text) from public, anon;

grant execute on function private.get_guest_players(boolean) to authenticated, service_role;
grant execute on function private.get_match_guests(uuid) to authenticated, service_role;
grant execute on function private.add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text)
  to authenticated, service_role;
grant execute on function private.remove_match_guest(uuid, uuid, text)
  to authenticated, service_role;
grant execute on function private.set_guest_archived(uuid, boolean, text)
  to authenticated, service_role;

revoke execute on function public.admin_get_guest_players(boolean) from public, anon;
revoke execute on function public.admin_get_match_guests(uuid) from public, anon;
revoke execute on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text)
  from public, anon;
revoke execute on function public.admin_remove_match_guest(uuid, uuid, text) from public, anon;
revoke execute on function public.admin_set_guest_archived(uuid, boolean, text) from public, anon;

grant execute on function public.admin_get_guest_players(boolean)
  to authenticated, service_role;
grant execute on function public.admin_get_match_guests(uuid)
  to authenticated, service_role;
grant execute on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text)
  to authenticated, service_role;
grant execute on function public.admin_remove_match_guest(uuid, uuid, text)
  to authenticated, service_role;
grant execute on function public.admin_set_guest_archived(uuid, boolean, text)
  to authenticated, service_role;

comment on function public.admin_add_or_reuse_match_guest(uuid, uuid, text, text, boolean, text) is
  'Creates or reuses a reusable guest and attaches that identity to an upcoming match.';
comment on function public.admin_remove_match_guest(uuid, uuid, text) is
  'Removes a guest from the current match without deleting the reusable catalog identity or past publications.';
comment on function public.admin_set_guest_archived(uuid, boolean, text) is
  'Archives or restores a reusable guest without changing existing historical match references.';
