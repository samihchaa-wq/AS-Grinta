-- Tableau Blanc: workspace lifecycle + live lineup + clock + score RPCs.
-- All write RPCs require private.is_match_coach_or_admin(match_id). Every
-- write RPC returns the same shape as private.get_match_live_state, so the
-- Flutter client always parses one bundle regardless of which action ran.

create or replace function private.match_live_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_session jsonb;
  v_true_elapsed integer;
  v_events jsonb;
  v_counts jsonb;
begin
  select jsonb_build_object(
    'match_id', session.match_id,
    'state', session.state,
    'planned_duration_minutes', session.planned_duration_minutes,
    'half', session.half,
    'elapsed_seconds', session.elapsed_seconds,
    'running_since', session.running_since,
    'score_as_grinta', session.score_as_grinta,
    'score_adverse', session.score_adverse,
    'started_at', session.started_at,
    'finished_at', session.finished_at,
    'exported', session.exported,
    'exported_at', session.exported_at,
    'lineup_revision', session.lineup_revision,
    'true_elapsed_seconds',
      session.elapsed_seconds + case
        when session.state = 'running'
        then greatest(0, extract(epoch from now() - session.running_since))::integer
        else 0
      end,
    'display_minute',
      (session.elapsed_seconds + case
        when session.state = 'running'
        then greatest(0, extract(epoch from now() - session.running_since))::integer
        else 0
      end) / 60 + 1
  )
  into v_session
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if v_session is null then
    return jsonb_build_object('match_id', p_match_id, 'state', null, 'session_exists', false);
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', event.id,
      'event_type', event.event_type,
      'minute', event.minute,
      'half', event.half,
      'scorer_participant_id', event.scorer_participant_id,
      'scorer_name', btrim(concat_ws(' ', scorer_player.first_name, scorer_player.last_name, scorer_guest.first_name, scorer_guest.last_name)),
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_participant_id', event.player_in_participant_id,
      'player_in_name', btrim(concat_ws(' ', in_player.first_name, in_player.last_name, in_guest.first_name, in_guest.last_name)),
      'player_out_participant_id', event.player_out_participant_id,
      'player_out_name', btrim(concat_ws(' ', out_player.first_name, out_player.last_name, out_guest.first_name, out_guest.last_name)),
      'created_at', event.created_at
    ) order by event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants in_p on in_p.id = event.player_in_participant_id
  left join public.season_players in_player on in_player.id = in_p.season_player_id
  left join public.guest_players in_guest on in_guest.id = in_p.guest_player_id
  left join public.match_sport_participants out_p on out_p.id = event.player_out_participant_id
  left join public.season_players out_player on out_player.id = out_p.season_player_id
  left join public.guest_players out_guest on out_guest.id = out_p.guest_player_id
  where event.match_id = p_match_id;

  select coalesce(jsonb_object_agg(participant_id, times_benched), '{}'::jsonb)
  into v_counts
  from (
    select
      participant.id as participant_id,
      (
        case when coalesce(session.starting_lineup_snapshot -> participant.id::text, 'null'::jsonb) = '"bench"'::jsonb
          then 1 else 0
        end
        + coalesce((
          select count(*)
          from public.match_live_events sub_event
          where sub_event.match_id = p_match_id
            and sub_event.event_type = 'substitution'
            and sub_event.player_out_participant_id = participant.id
        ), 0)
      ) as times_benched
    from public.match_sport_participants participant
    cross join public.match_live_sessions session
    where participant.match_id = p_match_id
      and session.match_id = p_match_id
      and (participant.is_eligible or participant.final_presence_status <> 'pending')
  ) counted
  where counted.times_benched > 0;

  return v_session
    || jsonb_build_object('session_exists', true)
    || jsonb_build_object('lineup', private.composition_snapshot(p_match_id))
    || jsonb_build_object('events', v_events)
    || jsonb_build_object('substitute_counts', v_counts);
end;
$function$;

create or replace function private.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_match_status text;
  v_kickoff_at timestamptz;
  v_default_duration integer;
  v_existing_state public.match_live_state;
  v_publication_snapshot jsonb;
  v_formation text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status, match.kickoff_at, match.planned_duration_minutes
  into v_match_status, v_kickoff_at, v_default_duration
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() < v_kickoff_at then
    raise exception 'Live tracking is only available once kickoff has occurred'
      using errcode = '22023';
  end if;

  select session.state into v_existing_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if found and v_existing_state <> 'not_started' then
    -- Already started: just return current state, no reset.
    return private.match_live_snapshot(p_match_id);
  end if;

  select publication.snapshot, publication.formation_code
  into v_publication_snapshot, v_formation
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_publication_snapshot is null then
    raise exception 'No published composition to start from' using errcode = '22023';
  end if;

  insert into public.match_live_sessions (
    match_id, state, planned_duration_minutes, updated_by
  ) values (
    p_match_id, 'not_started',
    greatest(1, least(200, coalesce(p_planned_duration_minutes, v_default_duration))),
    v_actor
  )
  on conflict (match_id) do update
  set planned_duration_minutes =
        greatest(1, least(200, coalesce(p_planned_duration_minutes, match_live_sessions.planned_duration_minutes))),
      updated_by = v_actor,
      updated_at = now();

  -- Reset the editable draft to the published snapshot every time this is
  -- called while still not_started, so the pre-kickoff editor always starts
  -- from what players actually saw published (discarding any stray
  -- unpublished draft edits left over from before kickoff).
  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select
    p_match_id,
    (entry ->> 'participant_id')::uuid,
    (entry ->> 'zone')::public.sport_composition_zone,
    case when entry ->> 'x' is null then null else (entry ->> 'x')::numeric end,
    case when entry ->> 'y' is null then null else (entry ->> 'y')::numeric end,
    entry ->> 'slot_label',
    coalesce((entry ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(v_publication_snapshot -> 'entries') entry
  where (entry ->> 'zone') in ('field', 'bench', 'not_selected');

  update public.match_compositions
  set formation_code = v_formation,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.confirm_start_match_live(
  p_match_id uuid,
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
  v_state public.match_live_state;
  v_field_count integer;
  v_composition_version integer;
  v_snapshot_map jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state into v_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Open the live workspace before starting the match' using errcode = '22023';
  end if;
  if v_state <> 'not_started' then
    raise exception 'The match has already been started' using errcode = '22023';
  end if;

  select count(*) filter (where zone = 'field') into v_field_count
  from public.match_composition_entries
  where match_id = p_match_id;
  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters' using errcode = '22023';
  end if;

  select composition.version into v_composition_version
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  select coalesce(jsonb_object_agg(entry.participant_id::text, entry.zone), '{}'::jsonb)
  into v_snapshot_map
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone in ('field', 'bench');

  update public.match_live_sessions
  set state = 'running',
      started_at = now(),
      running_since = now(),
      elapsed_seconds = 0,
      half = 1,
      starting_composition_version = v_composition_version,
      starting_lineup_snapshot = v_snapshot_map,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'start_match_live', v_actor, v_reason,
    jsonb_build_object('field_count', v_field_count)
  );

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.set_match_live_clock_state(
  p_match_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_action not in ('pause', 'resume', 'halftime', 'resume_second_half') then
    raise exception 'Invalid clock action' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half
  into v_state, v_elapsed, v_running_since, v_half
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;

  if p_action = 'pause' then
    if v_state <> 'running' then
      raise exception 'The clock is not running' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'paused',
        elapsed_seconds = v_elapsed + greatest(0, extract(epoch from now() - v_running_since))::integer,
        running_since = null,
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'resume' then
    if v_state <> 'paused' then
      raise exception 'The clock is not paused' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'running',
        running_since = now(),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'halftime' then
    if v_state not in ('running', 'paused') or v_half <> 1 then
      raise exception 'Half-time is only available during the first half' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'halftime',
        elapsed_seconds = v_elapsed + case
          when v_state = 'running'
          then greatest(0, extract(epoch from now() - v_running_since))::integer
          else 0
        end,
        running_since = null,
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'resume_second_half' then
    if v_state <> 'halftime' then
      raise exception 'The match is not at half-time' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'running',
        half = 2,
        running_since = now(),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.adjust_match_live_score(
  p_match_id uuid,
  p_team text,
  p_delta integer,
  p_scorer_participant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_true_elapsed integer;
  v_minute integer;
  v_score_us integer;
  v_score_them integer;
  v_scorer_valid boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_team not in ('us', 'them') then
    raise exception 'Invalid team' using errcode = '22023';
  end if;
  if p_delta not in (-1, 1) then
    raise exception 'Score delta must be -1 or 1' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half,
    session.score_as_grinta, session.score_adverse
  into v_state, v_elapsed, v_running_since, v_half, v_score_us, v_score_them
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;

  v_true_elapsed := v_elapsed + case
    when v_state = 'running'
    then greatest(0, extract(epoch from now() - v_running_since))::integer
    else 0
  end;
  v_minute := v_true_elapsed / 60 + 1;

  if p_team = 'us' and p_delta = 1 then
    if p_scorer_participant_id is null then
      raise exception 'A scorer is required' using errcode = '22023';
    end if;
    select exists (
      select 1 from public.match_sport_participants participant
      where participant.id = p_scorer_participant_id and participant.match_id = p_match_id
    ) into v_scorer_valid;
    if not v_scorer_valid then
      raise exception 'Unknown scorer for this match' using errcode = '22023';
    end if;

    update public.match_live_sessions
    set score_as_grinta = least(99, v_score_us + 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;

    insert into public.match_live_events (
      match_id, event_type, minute, half, scorer_participant_id,
      score_as_grinta_after, created_by
    ) values (
      p_match_id, 'goal_us', v_minute, v_half, p_scorer_participant_id,
      least(99, v_score_us + 1), v_actor
    );
  elsif p_team = 'us' and p_delta = -1 then
    update public.match_live_sessions
    set score_as_grinta = greatest(0, v_score_us - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_team = 'them' and p_delta = 1 then
    update public.match_live_sessions
    set score_adverse = least(99, v_score_them + 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;

    insert into public.match_live_events (
      match_id, event_type, minute, half, score_adverse_after, created_by
    ) values (
      p_match_id, 'goal_them', v_minute, v_half, least(99, v_score_them + 1), v_actor
    );
  else
    update public.match_live_sessions
    set score_adverse = greatest(0, v_score_them - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.save_match_live_lineup(
  p_match_id uuid,
  p_entries jsonb,
  p_substitution jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_true_elapsed integer;
  v_minute integer;
  v_expected_count integer;
  v_input_count integer;
  v_invalid_count integer;
  v_field_count integer;
  v_player_in uuid;
  v_player_out uuid;
  v_bad_boundary_count integer;
  v_in_old_zone public.sport_composition_zone;
  v_out_old_zone public.sport_composition_zone;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Lineup entries must be a JSON array' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half
  into v_state, v_elapsed, v_running_since, v_half
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('not_started', 'running', 'paused', 'halftime') then
    raise exception 'The lineup can only be edited while the live session is open' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.live_lineup_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.live_lineup_input;

  begin
    insert into pg_temp.live_lineup_input (participant_id, zone, x, y, slot_label, sort_order)
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
      raise exception 'A participant can appear only once' using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid lineup entry' using errcode = '22023';
  end;

  if exists (select 1 from pg_temp.live_lineup_input where zone = 'available') then
    raise exception 'Live lineup entries cannot use the available zone' using errcode = '22023';
  end if;

  select count(*) into v_input_count from pg_temp.live_lineup_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (participant.is_eligible or participant.final_presence_status <> 'pending');
  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once' using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.live_lineup_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id and participant.match_id = p_match_id
  where participant.id is null
     or (input.zone = 'field' and (
       input.x is null or input.y is null
       or input.x < 0 or input.x > 1 or input.y < 0 or input.y > 1
     ))
     or (input.zone <> 'field' and (input.x is not null or input.y is not null));
  if v_invalid_count > 0 then
    raise exception 'Invalid lineup zone or coordinates' using errcode = '22023';
  end if;

  select count(*) into v_field_count from pg_temp.live_lineup_input where zone = 'field';
  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters' using errcode = '22023';
  end if;

  if p_substitution is not null then
    v_player_in := (p_substitution ->> 'player_in')::uuid;
    v_player_out := (p_substitution ->> 'player_out')::uuid;
    if v_player_in is null or v_player_out is null or v_player_in = v_player_out then
      raise exception 'Invalid substitution payload' using errcode = '22023';
    end if;

    select zone into v_in_old_zone from public.match_composition_entries
    where match_id = p_match_id and participant_id = v_player_in;
    select zone into v_out_old_zone from public.match_composition_entries
    where match_id = p_match_id and participant_id = v_player_out;

    if coalesce(v_in_old_zone, 'not_selected') = 'field'
       or coalesce(v_out_old_zone, 'not_selected') <> 'field' then
      raise exception 'Substitution must bring in a non-field player and remove a field player'
        using errcode = '22023';
    end if;
    select zone into v_in_old_zone from pg_temp.live_lineup_input where participant_id = v_player_in;
    if v_in_old_zone <> 'field' then
      raise exception 'The incoming player must end up on the field' using errcode = '22023';
    end if;
  end if;

  -- Sanity check: any zone crossing the field/bench boundary that wasn't
  -- flagged as the declared substitution is silently corrupting
  -- Remplacements/Faits du match and the times-benched counter — reject it.
  select count(*) into v_bad_boundary_count
  from pg_temp.live_lineup_input input
  join public.match_composition_entries old_entry
    on old_entry.match_id = p_match_id and old_entry.participant_id = input.participant_id
  where (old_entry.zone = 'field') <> (input.zone = 'field')
    and input.participant_id not in (coalesce(v_player_in, '00000000-0000-0000-0000-000000000000'::uuid),
                                      coalesce(v_player_out, '00000000-0000-0000-0000-000000000000'::uuid));
  if v_bad_boundary_count > 0 then
    raise exception 'A field/bench change was not declared as a substitution' using errcode = '22023';
  end if;

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.live_lineup_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.live_lineup_input input
  where participant.id = input.participant_id and participant.match_id = p_match_id;

  update public.match_compositions
  set last_modified_at = now(), last_modified_by = v_actor
  where match_id = p_match_id;

  if p_substitution is not null then
    v_true_elapsed := v_elapsed + case
      when v_state = 'running'
      then greatest(0, extract(epoch from now() - v_running_since))::integer
      else 0
    end;
    v_minute := v_true_elapsed / 60 + 1;

    insert into public.match_live_events (
      match_id, event_type, minute, half,
      player_in_participant_id, player_out_participant_id, created_by
    ) values (
      p_match_id, 'substitution', v_minute, v_half, v_player_in, v_player_out, v_actor
    );
  end if;

  update public.match_live_sessions
  set lineup_revision = lineup_revision + 1, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.open_match_live_workspace(
  p_match_id uuid, p_planned_duration_minutes integer default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.open_match_live_workspace(p_match_id, p_planned_duration_minutes); $function$;

create or replace function public.confirm_start_match_live(p_match_id uuid, p_reason text default null)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.confirm_start_match_live(p_match_id, p_reason); $function$;

create or replace function public.coach_set_match_live_clock_state(
  p_match_id uuid, p_action text, p_reason text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.set_match_live_clock_state(p_match_id, p_action, p_reason); $function$;

create or replace function public.coach_adjust_match_live_score(
  p_match_id uuid, p_team text, p_delta integer, p_scorer_participant_id uuid default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.adjust_match_live_score(p_match_id, p_team, p_delta, p_scorer_participant_id); $function$;

create or replace function public.coach_save_match_live_lineup(
  p_match_id uuid, p_entries jsonb, p_substitution jsonb default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$ select private.save_match_live_lineup(p_match_id, p_entries, p_substitution); $function$;

create or replace function public.get_match_live_state(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.match_live_snapshot(p_match_id); $function$;

revoke execute on function private.match_live_snapshot(uuid) from public, anon;
revoke execute on function private.open_match_live_workspace(uuid, integer) from public, anon;
revoke execute on function private.confirm_start_match_live(uuid, text) from public, anon;
revoke execute on function private.set_match_live_clock_state(uuid, text, text) from public, anon;
revoke execute on function private.adjust_match_live_score(uuid, text, integer, uuid) from public, anon;
revoke execute on function private.save_match_live_lineup(uuid, jsonb, jsonb) from public, anon;

grant execute on function private.match_live_snapshot(uuid) to authenticated, service_role;
grant execute on function private.open_match_live_workspace(uuid, integer) to authenticated, service_role;
grant execute on function private.confirm_start_match_live(uuid, text) to authenticated, service_role;
grant execute on function private.set_match_live_clock_state(uuid, text, text) to authenticated, service_role;
grant execute on function private.adjust_match_live_score(uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function private.save_match_live_lineup(uuid, jsonb, jsonb) to authenticated, service_role;

revoke execute on function public.open_match_live_workspace(uuid, integer) from public, anon;
revoke execute on function public.confirm_start_match_live(uuid, text) from public, anon;
revoke execute on function public.coach_set_match_live_clock_state(uuid, text, text) from public, anon;
revoke execute on function public.coach_adjust_match_live_score(uuid, text, integer, uuid) from public, anon;
revoke execute on function public.coach_save_match_live_lineup(uuid, jsonb, jsonb) from public, anon;
revoke execute on function public.get_match_live_state(uuid) from public, anon;

grant execute on function public.open_match_live_workspace(uuid, integer) to authenticated, service_role;
grant execute on function public.confirm_start_match_live(uuid, text) to authenticated, service_role;
grant execute on function public.coach_set_match_live_clock_state(uuid, text, text) to authenticated, service_role;
grant execute on function public.coach_adjust_match_live_score(uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function public.coach_save_match_live_lineup(uuid, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.get_match_live_state(uuid) to authenticated, service_role;
