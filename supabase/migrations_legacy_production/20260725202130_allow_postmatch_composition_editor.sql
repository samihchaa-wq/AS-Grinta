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
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be edited for this match state' using errcode = '22023';
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
    insert into pg_temp.composition_input (participant_id, zone, x, y, slot_label, sort_order)
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
        input.x is null or input.y is null
        or input.x < 0 or input.x > 1
        or input.y < 0 or input.y > 1
      )
    )
    or (
      input.zone <> 'field' and (input.x is not null or input.y is not null)
    )
    or (
      v_match_status = 'a_venir'
      and input.zone in ('field', 'bench', 'available')
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
      v_match_status in ('termine', 'archive')
      and input.zone in ('field', 'bench')
      and participant.final_presence_status <> 'present'
    );

  if v_invalid_zone_count > 0 then
    raise exception 'Composition zones conflict with availability, presence or convocation decisions' using errcode = '22023';
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.composition_input;

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters' using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
    and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit' using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  insert into public.match_compositions (
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, last_modified_by
  ) values (
    p_match_id, v_formation, 'draft', 0, true, v_exception_used, v_actor
  )
  on conflict (match_id) do update
  set formation_code = excluded.formation_code,
      has_unpublished_changes = true,
      squad_size_exception_approved = excluded.squad_size_exception_approved,
      last_modified_at = now(),
      last_modified_by = excluded.last_modified_by;

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        when 'not_selected' then 'not_selected'::public.sport_selection_status
        else 'undecided'::public.sport_selection_status
      end,
      final_selection_status = case
        when v_match_status in ('termine', 'archive') then case input.zone
          when 'field' then 'starter'::public.sport_selection_status
          when 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end
        else participant.final_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = case
        when workflow.composition_state = 'none' then 'draft'::public.sport_composition_state
        else workflow.composition_state
      end,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_match_status in ('termine', 'archive')
      then 'save_postmatch_composition'
      else 'save_composition_draft'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'formation_code', v_formation,
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.composition_snapshot(p_match_id);
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

  select match.status, match.kickoff_at, workflow.squad_size_limit, composition.version
  into v_match_status, v_kickoff_at, v_squad_limit, v_current_version
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  join public.match_compositions composition on composition.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow, composition;

  if not found then
    raise exception 'Composition draft not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be published for this match state' using errcode = '22023';
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
    raise exception 'A composition cannot contain more than 11 starters' using errcode = '22023';
  end if;
  if v_available_count > 0 then
    raise exception 'Every selected player must be placed on the field or bench before publication' using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit' using errcode = '22023';
  end if;

  v_exception_used := v_selected_count > v_squad_limit;
  v_publication_kind := case
    when v_match_status in ('termine', 'archive') then 'postmatch'
    when v_current_version = 0 then 'initial'
    else 'update'
  end;

  update public.match_compositions composition
  set status = case
        when v_current_version = 0 then 'published'::public.sport_composition_state
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
        when v_current_version = 0 then 'published'::public.sport_composition_state
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

  insert into public.match_composition_publications (
    match_id, version, formation_code, snapshot, publication_kind, published_by
  ) values (
    p_match_id, v_current_version + 1,
    (select formation_code from public.match_compositions where match_id = p_match_id),
    v_snapshot, v_publication_kind, v_actor
  );

  insert into private.sport_admin_audit_log (
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
$function$;;
