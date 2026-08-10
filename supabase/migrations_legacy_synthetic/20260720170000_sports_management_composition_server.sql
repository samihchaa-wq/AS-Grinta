-- Sports-management composition drafts and immutable publications.
-- Additive and inert while the sports_management feature flag is disabled.

create type public.sport_composition_zone as enum (
  'available',
  'field',
  'bench',
  'not_selected'
);

create table public.match_compositions (
  match_id uuid primary key references public.match_sport_workflows(match_id) on delete restrict,
  formation_code text check (formation_code is null or char_length(formation_code) <= 32),
  status public.sport_composition_state not null default 'draft'
    check (status <> 'none'),
  version integer not null default 0 check (version >= 0),
  has_unpublished_changes boolean not null default true,
  squad_size_exception_approved boolean not null default false,
  published_at timestamptz,
  published_by uuid references public.profiles(id) on delete restrict,
  last_modified_at timestamptz not null default now(),
  last_modified_by uuid not null references public.profiles(id) on delete restrict,
  closed_at timestamptz,
  check (
    (version = 0 and published_at is null and published_by is null)
    or (version > 0 and published_at is not null and published_by is not null)
  )
);

create table public.match_composition_entries (
  match_id uuid not null references public.match_compositions(match_id) on delete restrict,
  participant_id uuid not null,
  zone public.sport_composition_zone not null,
  x numeric(7,6),
  y numeric(7,6),
  slot_label text check (slot_label is null or char_length(slot_label) <= 16),
  sort_order integer not null default 0 check (sort_order >= 0),
  updated_at timestamptz not null default now(),
  primary key (match_id, participant_id),
  foreign key (participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict,
  check (
    (zone = 'field' and x between 0 and 1 and y between 0 and 1)
    or (zone <> 'field' and x is null and y is null)
  )
);

create table public.match_composition_publications (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.match_compositions(match_id) on delete restrict,
  version integer not null check (version >= 1),
  formation_code text check (formation_code is null or char_length(formation_code) <= 32),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  publication_kind text not null check (publication_kind in ('initial', 'update')),
  published_at timestamptz not null default now(),
  published_by uuid not null references public.profiles(id) on delete restrict,
  unique (match_id, version)
);

comment on table public.match_compositions is
  'Current administrator draft. Published players read immutable publication snapshots instead.';
comment on column public.match_compositions.has_unpublished_changes is
  'True when the current normalized draft differs from the latest immutable publication.';
comment on table public.match_composition_publications is
  'Immutable public snapshots written atomically for each composition publication.';

create index match_composition_entries_zone_idx
  on public.match_composition_entries(match_id, zone, sort_order);
create index match_composition_publications_latest_idx
  on public.match_composition_publications(match_id, version desc);

alter table public.match_compositions enable row level security;
alter table public.match_composition_entries enable row level security;
alter table public.match_composition_publications enable row level security;

revoke all on table public.match_compositions from public, anon, authenticated;
revoke all on table public.match_composition_entries from public, anon, authenticated;
revoke all on table public.match_composition_publications from public, anon, authenticated;

-- Only immutable snapshots are exposed directly, and only when the module is active.
grant select on table public.match_composition_publications to authenticated;
grant select, insert, update on table public.match_compositions to service_role;
grant select, insert, update, delete on table public.match_composition_entries to service_role;
grant select, insert on table public.match_composition_publications to service_role;

create policy match_composition_publications_active_profile_select
on public.match_composition_publications for select to authenticated
using (
  (select private.is_feature_enabled('sports_management'))
  and (select private.is_active_profile())
);

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
      entry.zone = 'field' and player.is_goalkeeper
    ), false),
    'entries', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'participant_id', participant.id,
          'season_player_id', participant.season_player_id,
          'display_name', btrim(concat_ws(' ', player.first_name, player.last_name)),
          'is_goalkeeper', player.is_goalkeeper,
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
          lower(player.first_name),
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
  where participant.match_id = p_match_id and participant.is_eligible;

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
    (input.zone = 'field' and (
      input.x is null or input.y is null
      or input.x < 0 or input.x > 1 or input.y < 0 or input.y > 1
    ))
    or (input.zone <> 'field' and (input.x is not null or input.y is not null))
    or (input.zone in ('field', 'bench', 'available') and (
      participant.availability_status <> 'available'
      or participant.convocation_status <> 'convoked'
    ))
    or (input.zone = 'not_selected' and participant.convocation_status = 'convoked');

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
  if v_selected_count > v_squad_limit and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  insert into public.match_compositions (
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, last_modified_by
  ) values (
    p_match_id, v_formation, 'draft', 0, true,
    v_exception_used, v_actor
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
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, input.participant_id, input.zone,
    input.x, input.y, input.slot_label, input.sort_order
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
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  )
  select participant.id, p_match_id, 'selection_changed',
    jsonb_build_object('status', old_selection.old_status),
    jsonb_build_object('status', participant.selection_status),
    v_actor, 'staff'
  from public.match_sport_participants participant
  join pg_temp.composition_old_selection old_selection
    on old_selection.participant_id = participant.id
  where participant.match_id = p_match_id
    and old_selection.old_status is distinct from participant.selection_status;

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
    case when v_exception_used then 'save_composition_exception' else 'save_composition_draft' end,
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
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at, workflow.squad_size_limit,
    composition.version
  into v_match_status, v_kickoff_at, v_squad_limit, v_current_version
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  join public.match_compositions composition on composition.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow, composition;

  if not found then
    raise exception 'Composition draft not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Composition can only be published before kickoff' using errcode = '22023';
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
    raise exception 'Every convoked player must be placed on the field or bench before publication'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;
  v_publication_kind := case when v_current_version = 0 then 'initial' else 'update' end;

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
    match_id, version, formation_code, snapshot,
    publication_kind, published_by
  )
  select composition.match_id, composition.version, composition.formation_code,
    v_snapshot, v_publication_kind, v_actor
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_exception_used then 'publish_composition_exception' else 'publish_composition' end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_current_version + 1,
      'publication_kind', v_publication_kind,
      'field_count', v_field_count,
      'bench_count', v_bench_count,
      'squad_size_limit', v_squad_limit,
      'exception_used', v_exception_used,
      'has_goalkeeper_warning', coalesce((v_snapshot ->> 'has_goalkeeper_warning')::boolean, false)
    )
  );

  return v_snapshot;
end;
$function$;

create or replace function private.get_admin_match_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.composition_snapshot(p_match_id);
end;
$function$;

create or replace function private.get_published_match_composition(p_match_id uuid)
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
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select publication.snapshot into v_result
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  return v_result;
end;
$function$;

create or replace function public.admin_save_match_composition(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.save_match_composition(
    p_match_id, p_formation_code, p_entries,
    p_allow_squad_size_exception, p_reason
  );
$function$;

create or replace function public.admin_publish_match_composition(
  p_match_id uuid,
  p_allow_squad_size_exception boolean default false,
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.publish_match_composition(
    p_match_id, p_allow_squad_size_exception, p_reason
  );
$function$;

create or replace function public.admin_get_match_composition(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_admin_match_composition(p_match_id); $function$;

create or replace function public.get_published_match_composition(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_published_match_composition(p_match_id); $function$;

revoke execute on function private.composition_snapshot(uuid) from public, anon;
revoke execute on function private.save_match_composition(uuid, text, jsonb, boolean, text) from public, anon;
revoke execute on function private.publish_match_composition(uuid, boolean, text) from public, anon;
revoke execute on function private.get_admin_match_composition(uuid) from public, anon;
revoke execute on function private.get_published_match_composition(uuid) from public, anon;

grant execute on function private.composition_snapshot(uuid) to authenticated, service_role;
grant execute on function private.save_match_composition(uuid, text, jsonb, boolean, text) to authenticated, service_role;
grant execute on function private.publish_match_composition(uuid, boolean, text) to authenticated, service_role;
grant execute on function private.get_admin_match_composition(uuid) to authenticated, service_role;
grant execute on function private.get_published_match_composition(uuid) to authenticated, service_role;

revoke execute on function public.admin_save_match_composition(uuid, text, jsonb, boolean, text) from public, anon;
revoke execute on function public.admin_publish_match_composition(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_get_match_composition(uuid) from public, anon;
revoke execute on function public.get_published_match_composition(uuid) from public, anon;

grant execute on function public.admin_save_match_composition(uuid, text, jsonb, boolean, text) to authenticated, service_role;
grant execute on function public.admin_publish_match_composition(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.admin_get_match_composition(uuid) to authenticated, service_role;
grant execute on function public.get_published_match_composition(uuid) to authenticated, service_role;

comment on function public.admin_save_match_composition(uuid, text, jsonb, boolean, text) is
  'Saves a complete normalized draft, with at most eleven starters and an explicit squad-size exception.';
comment on function public.admin_publish_match_composition(uuid, boolean, text) is
  'Publishes an immutable composition snapshot and increments the public version atomically.';
comment on function public.get_published_match_composition(uuid) is
  'Returns only the latest immutable published snapshot while the sports-management module is active.';
