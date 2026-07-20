-- Sports-management final attendance and atomic statistics synchronization.
-- Permanent players feed the existing attendance/player-stat tables. Guests remain
-- linked to the same validated result through match_sport_participants.

alter table public.match_sport_participants
  add column final_selection_status public.sport_selection_status not null default 'undecided',
  add column final_goals smallint not null default 0 check (final_goals between 0 and 99),
  add column final_clean_sheet boolean not null default false;

alter table public.match_sport_participants
  add constraint match_sport_participants_final_presence_consistency_check
  check (
    final_presence_status = 'pending'
    or final_presence_status = 'present'
    or (
      final_presence_status = 'actual_absent'
      and final_selection_status in ('undecided', 'not_selected')
      and final_goals = 0
      and not final_clean_sheet
    )
  );

create table public.match_sport_finalizations (
  match_id uuid primary key references public.match_sport_workflows(match_id) on delete restrict,
  version integer not null default 0 check (version >= 0),
  score_as_grinta smallint not null check (score_as_grinta between 0 and 99),
  score_adverse smallint not null check (score_adverse between 0 and 99),
  composition_version integer not null default 0 check (composition_version >= 0),
  validated_at timestamptz not null default now(),
  validated_by uuid not null references public.profiles(id) on delete restrict,
  corrected_at timestamptz,
  corrected_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now()
);

create table public.match_sport_finalization_versions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.match_sport_finalizations(match_id) on delete restrict,
  version integer not null check (version >= 1),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  validation_kind text not null check (validation_kind in ('initial', 'correction')),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  unique (match_id, version)
);

comment on table public.match_sport_finalizations is
  'Current validated post-match state. Permanent-player statistics are synchronized atomically.';
comment on table public.match_sport_finalization_versions is
  'Immutable snapshots of every initial validation and later correction.';
comment on column public.match_sport_participants.final_presence_status is
  'Actual presence validated after the match; this alone feeds attendance statistics.';
comment on column public.match_sport_participants.final_selection_status is
  'Actual post-match role, independent from the published pre-match composition.';
comment on column public.match_sport_participants.final_goals is
  'Validated goals. Permanent players are mirrored to match_player_stats; guest goals stay here.';

create index match_sport_final_participants_present_idx
  on public.match_sport_participants(match_id, final_selection_status)
  where final_presence_status = 'present';
create index match_sport_finalization_versions_latest_idx
  on public.match_sport_finalization_versions(match_id, version desc);

alter table public.match_sport_finalizations enable row level security;
alter table public.match_sport_finalization_versions enable row level security;

revoke all on table public.match_sport_finalizations from public, anon, authenticated;
revoke all on table public.match_sport_finalization_versions from public, anon, authenticated;
grant select, insert, update on table public.match_sport_finalizations to service_role;
grant select, insert on table public.match_sport_finalization_versions to service_role;

create or replace function private.match_sport_finalization_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  with latest_publication as (
    select publication.version, publication.snapshot
    from public.match_composition_publications publication
    where publication.match_id = p_match_id
    order by publication.version desc
    limit 1
  ), planned_entries as (
    select
      (entry ->> 'participant_id')::uuid as participant_id,
      entry ->> 'zone' as planned_zone
    from latest_publication publication,
      lateral jsonb_array_elements(
        coalesce(publication.snapshot -> 'entries', '[]'::jsonb)
      ) entry
  )
  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'match_status', match.status,
    'is_validated', finalization.match_id is not null,
    'version', coalesce(finalization.version, 0),
    'score_as_grinta', coalesce(finalization.score_as_grinta, match.score_as_grinta, 0),
    'score_adverse', coalesce(finalization.score_adverse, match.score_adverse, 0),
    'composition_version', coalesce(finalization.composition_version, workflow.composition_version, 0),
    'presence_state', workflow.presence_state,
    'vote_state', workflow.vote_state,
    'validated_at', finalization.validated_at,
    'corrected_at', finalization.corrected_at,
    'participants', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'is_guest', participant.guest_player_id is not null,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end,
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'planned_zone', coalesce(planned.planned_zone, case participant.selection_status
          when 'starter' then 'field'
          when 'substitute' then 'bench'
          when 'not_selected' then 'not_selected'
          else 'available'
        end),
        'present', case
          when finalization.match_id is not null then participant.final_presence_status = 'present'
          else coalesce(planned.planned_zone in ('field', 'bench'), false)
        end,
        'final_presence_status', participant.final_presence_status,
        'final_selection_status', case
          when finalization.match_id is not null then participant.final_selection_status
          when planned.planned_zone = 'field' then 'starter'::public.sport_selection_status
          when planned.planned_zone = 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        'goals', participant.final_goals,
        'clean_sheet', participant.final_clean_sheet
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(player.first_name, guest.first_name)),
        participant.id
    ) filter (
      where participant.id is not null
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  left join public.match_sport_participants participant on participant.match_id = match.id
  left join public.season_players player on player.id = participant.season_player_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;

create or replace function private.get_admin_match_sport_finalization(p_match_id uuid)
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
  v_result := private.match_sport_finalization_snapshot(p_match_id);
  if v_result is null then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function private.get_published_match_sport_result(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.match_sport_finalizations finalization
    where finalization.match_id = p_match_id
  ) then
    return null;
  end if;
  return private.match_sport_finalization_snapshot(p_match_id);
end;
$function$;

create or replace function private.finalize_match_sport_postgame(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
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
  v_existing_version integer := 0;
  v_composition_version integer := 0;
  v_expected integer;
  v_received integer;
  v_present_count integer;
  v_starter_count integer;
  v_goal_total integer;
  v_clean_sheet_count integer;
  v_permanent_present uuid[];
  v_permanent_scorers jsonb;
  v_permanent_clean_sheet uuid;
  v_snapshot jsonb;
  v_kind text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_score_as_grinta is null or p_score_as_grinta not between 0 and 99
     or p_score_adverse is null or p_score_adverse not between 0 and 99 then
    raise exception 'Scores must be between 0 and 99' using errcode = '22023';
  end if;
  if p_participants is null or jsonb_typeof(p_participants) <> 'array' then
    raise exception 'Participants payload must be a JSON array' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at, workflow.composition_version
into v_match_status, v_kickoff_at, v_composition_version
from public.matches match
join public.match_sport_workflows workflow on workflow.match_id = match.id
where match.id = p_match_id
for update of match, workflow;

if not found then
  raise exception 'Sport match workflow not found' using errcode = 'P0002';
end if;

select finalization.version
into v_existing_version
from public.match_sport_finalizations finalization
where finalization.match_id = p_match_id
for update;

if not found then
  v_existing_version := 0;
end if;

  if v_match_status not in ('a_venir', 'termine') then
    raise exception 'Only upcoming or finished matches can be validated' using errcode = '22023';
  end if;
  if now() < v_kickoff_at then
    raise exception 'The match cannot be finalized before kickoff' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.sport_final_input (
    participant_id uuid primary key,
    present boolean not null,
    final_selection_status public.sport_selection_status not null,
    goals integer not null,
    clean_sheet boolean not null
  ) on commit drop;
  truncate table pg_temp.sport_final_input;

  begin
    insert into pg_temp.sport_final_input(
      participant_id, present, final_selection_status, goals, clean_sheet
    )
    select
      (item ->> 'participant_id')::uuid,
      coalesce((item ->> 'present')::boolean, false),
      (item ->> 'final_selection_status')::public.sport_selection_status,
      coalesce((item ->> 'goals')::integer, 0),
      coalesce((item ->> 'clean_sheet')::boolean, false)
    from jsonb_array_elements(p_participants) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once' using errcode = '22023';
    when invalid_text_representation or numeric_value_out_of_range or check_violation then
      raise exception 'Invalid final participant entry' using errcode = '22023';
  end;

  select count(*) into v_received from pg_temp.sport_final_input;
  select count(*) into v_expected
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (participant.is_eligible or participant.final_presence_status <> 'pending');
  if v_received <> v_expected then
    raise exception 'Every match participant must appear exactly once' using errcode = '22023';
  end if;
  if exists (
    select 1
    from pg_temp.sport_final_input input
    left join public.match_sport_participants participant
      on participant.id = input.participant_id
     and participant.match_id = p_match_id
     and (participant.is_eligible or participant.final_presence_status <> 'pending')
    where participant.id is null
  ) then
    raise exception 'Finalization contains an unknown participant' using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_final_input input
    where input.goals < 0 or input.goals > 99
      or input.final_selection_status = 'undecided'
      or (
        not input.present and (
          input.final_selection_status <> 'not_selected'
          or input.goals <> 0
          or input.clean_sheet
        )
      )
      or (input.goals > 0 and not input.present)
  ) then
    raise exception 'Final presence, role and statistics are inconsistent' using errcode = '22023';
  end if;

  select
    count(*) filter (where present),
    count(*) filter (where present and final_selection_status = 'starter'),
    coalesce(sum(goals), 0),
    count(*) filter (where clean_sheet)
  into v_present_count, v_starter_count, v_goal_total, v_clean_sheet_count
  from pg_temp.sport_final_input;

  if v_present_count = 0 then
    raise exception 'At least one present participant is required' using errcode = '22023';
  end if;
  if v_starter_count > 11 then
    raise exception 'A match cannot have more than eleven actual starters' using errcode = '22023';
  end if;
  if v_goal_total > p_score_as_grinta then
    raise exception 'Attributed goals exceed the AS Grinta score' using errcode = '22023';
  end if;
  if v_clean_sheet_count > 1 then
    raise exception 'Only one goalkeeper can receive the clean sheet' using errcode = '22023';
  end if;
  if v_clean_sheet_count = 1 and p_score_adverse <> 0 then
    raise exception 'Clean sheet is impossible when the opponent scored' using errcode = '22023';
  end if;
  if exists (
    select 1
    from pg_temp.sport_final_input input
    join public.match_sport_participants participant on participant.id = input.participant_id
    left join public.season_players player on player.id = participant.season_player_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where input.clean_sheet
      and (
        not input.present
        or not coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
      )
  ) then
    raise exception 'Clean sheet must belong to a present goalkeeper' using errcode = '22023';
  end if;

  select coalesce(array_agg(participant.season_player_id), '{}'::uuid[])
  into v_permanent_present
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.present and participant.season_player_id is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'season_player_id', participant.season_player_id,
    'goals', input.goals
  )), '[]'::jsonb)
  into v_permanent_scorers
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.goals > 0 and participant.season_player_id is not null;

  select participant.season_player_id into v_permanent_clean_sheet
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.clean_sheet and participant.season_player_id is not null
  limit 1;

  -- Existing statistics remain the canonical source for permanent players.
  perform public.staff_set_match_attendance(p_match_id, v_permanent_present);
  perform public.staff_set_match_mvp(p_match_id, '{}'::uuid[]);
  perform public.finalize_match_postgame(
    p_match_id,
    p_score_adverse,
    v_permanent_scorers,
    v_permanent_clean_sheet,
    p_score_as_grinta
  );

  create temporary table if not exists pg_temp.old_sport_final (
    participant_id uuid primary key,
    presence_status public.sport_final_presence_status not null,
    selection_status public.sport_selection_status not null,
    goals integer not null,
    clean_sheet boolean not null
  ) on commit drop;
  truncate table pg_temp.old_sport_final;
  insert into pg_temp.old_sport_final
  select participant.id, participant.final_presence_status,
    participant.final_selection_status, participant.final_goals,
    participant.final_clean_sheet
  from public.match_sport_participants participant
  where participant.match_id = p_match_id;

  update public.match_sport_participants participant
  set final_presence_status = case
        when input.present then 'present'::public.sport_final_presence_status
        else 'actual_absent'::public.sport_final_presence_status
      end,
      final_selection_status = input.final_selection_status,
      final_goals = input.goals,
      final_clean_sheet = input.clean_sheet,
      final_presence_confirmed_at = now(),
      final_presence_confirmed_by = v_actor,
      updated_at = now()
  from pg_temp.sport_final_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  insert into public.match_sport_participant_events(
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  )
  select participant.id, p_match_id, 'final_presence_validated',
    jsonb_build_object(
      'presence_status', old.presence_status,
      'selection_status', old.selection_status,
      'goals', old.goals,
      'clean_sheet', old.clean_sheet
    ),
    jsonb_build_object(
      'presence_status', participant.final_presence_status,
      'selection_status', participant.final_selection_status,
      'goals', participant.final_goals,
      'clean_sheet', participant.final_clean_sheet
    ),
    v_actor, 'staff'
  from public.match_sport_participants participant
  join pg_temp.old_sport_final old on old.participant_id = participant.id
  where participant.match_id = p_match_id
    and (
      old.presence_status is distinct from participant.final_presence_status
      or old.selection_status is distinct from participant.final_selection_status
      or old.goals is distinct from participant.final_goals
      or old.clean_sheet is distinct from participant.final_clean_sheet
    );

  update public.match_sport_workflows
  set availability_state = 'closed',
      composition_state = 'closed',
      presence_state = 'confirmed',
      vote_state = 'draft',
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  v_kind := case when v_existing_version = 0 then 'initial' else 'correction' end;

  insert into public.match_sport_finalizations(
    match_id, version, score_as_grinta, score_adverse,
    composition_version, validated_by, corrected_at, corrected_by
  ) values (
    p_match_id, 1, p_score_as_grinta, p_score_adverse,
    v_composition_version, v_actor, null, null
  )
  on conflict (match_id) do update
  set version = match_sport_finalizations.version + 1,
      score_as_grinta = excluded.score_as_grinta,
      score_adverse = excluded.score_adverse,
      composition_version = excluded.composition_version,
      corrected_at = now(),
      corrected_by = v_actor,
      updated_at = now();

  v_snapshot := private.match_sport_finalization_snapshot(p_match_id)
    || jsonb_build_object('validation_kind', v_kind);

  insert into public.match_sport_finalization_versions(
    match_id, version, snapshot, validation_kind, created_by
  )
  select finalization.match_id, finalization.version, v_snapshot, v_kind, v_actor
  from public.match_sport_finalizations finalization
  where finalization.match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_kind = 'initial' then 'validate_final_attendance' else 'correct_final_attendance' end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_existing_version + 1,
      'score_as_grinta', p_score_as_grinta,
      'score_adverse', p_score_adverse,
      'present_count', v_present_count,
      'starter_count', v_starter_count,
      'guest_present_count', (
        select count(*)
        from pg_temp.sport_final_input input
        join public.match_sport_participants participant on participant.id = input.participant_id
        where input.present and participant.guest_player_id is not null
      ),
      'attributed_goals', v_goal_total
    )
  );

  return v_snapshot;
end;
$function$;

create or replace function public.admin_get_match_sport_finalization(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_admin_match_sport_finalization(p_match_id); $function$;

create or replace function public.admin_finalize_match_sport_postgame(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.finalize_match_sport_postgame(
    p_match_id, p_score_as_grinta, p_score_adverse, p_participants, p_reason
  );
$function$;

create or replace function public.get_match_sport_result(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_published_match_sport_result(p_match_id); $function$;

revoke execute on function private.match_sport_finalization_snapshot(uuid) from public, anon;
revoke execute on function private.get_admin_match_sport_finalization(uuid) from public, anon;
revoke execute on function private.get_published_match_sport_result(uuid) from public, anon;
revoke execute on function private.finalize_match_sport_postgame(uuid, integer, integer, jsonb, text) from public, anon;

grant execute on function private.match_sport_finalization_snapshot(uuid) to authenticated, service_role;
grant execute on function private.get_admin_match_sport_finalization(uuid) to authenticated, service_role;
grant execute on function private.get_published_match_sport_result(uuid) to authenticated, service_role;
grant execute on function private.finalize_match_sport_postgame(uuid, integer, integer, jsonb, text) to authenticated, service_role;

revoke execute on function public.admin_get_match_sport_finalization(uuid) from public, anon;
revoke execute on function public.admin_finalize_match_sport_postgame(uuid, integer, integer, jsonb, text) from public, anon;
revoke execute on function public.get_match_sport_result(uuid) from public, anon;

grant execute on function public.admin_get_match_sport_finalization(uuid) to authenticated, service_role;
grant execute on function public.admin_finalize_match_sport_postgame(uuid, integer, integer, jsonb, text) to authenticated, service_role;
grant execute on function public.get_match_sport_result(uuid) to authenticated, service_role;

comment on function public.admin_finalize_match_sport_postgame(uuid, integer, integer, jsonb, text) is
  'Atomically validates actual attendance, roles and goals, mirrors permanent-player statistics, and versions corrections.';
comment on function public.get_match_sport_result(uuid) is
  'Returns the validated result and all permanent/guest participant statistics to active profiles.';
