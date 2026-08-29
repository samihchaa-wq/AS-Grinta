begin;

-- Compte rendu de match : une seule validation, atomique.
--
-- L'écran « Compte rendu » n'envoie plus des compteurs par joueur mais le
-- compte rendu complet : score, effectif réel (titulaires / remplaçants /
-- joueurs retirés) et liste exacte des buts. Le serveur en **dérive** les
-- statistiques (buts, passes décisives, clean sheet, présences) puis rejoue le
-- pipeline de finalisation existant, sans rien y retirer.

-- ---------------------------------------------------------------------------
-- 1. Finalisation : une correction des faits force une nouvelle version
-- ---------------------------------------------------------------------------
--
-- Corps identique à 20260827160100, avec une seule différence : le raccourci
-- d'idempotence (rejeu réseau) ne doit pas avaler une correction qui ne touche
-- que les faits du match — par exemple une minute ou un passeur corrigé sans
-- changement de compteur.

create or replace function private.finalize_match_sport_postgame(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
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
  v_assist_total integer;
  v_clean_sheet_count integer;
  v_permanent_present uuid[];
  v_permanent_scorers jsonb;
  v_permanent_clean_sheet uuid;
  v_snapshot jsonb;
  v_kind text;
  v_facts_changed boolean := coalesce(
    current_setting('as_grinta.sport_report_facts_changed', true), 'off'
  ) = 'on';
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin()
     and not (
       current_setting('as_grinta.allow_coach_live_finalize', true) = 'on'
       and private.is_match_coach_or_admin(p_match_id)
     ) then
    raise exception 'Active administrator role or validated Live coach context required'
      using errcode = '42501';
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
  if now() < v_kickoff_at and not exists (
    select 1
    from public.match_live_sessions live_session
    where live_session.match_id = p_match_id
      and live_session.state = 'finished'
  ) then
    raise exception 'The match cannot be finalized before kickoff' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.sport_final_input (
    participant_id uuid primary key,
    present boolean not null,
    final_selection_status public.sport_selection_status not null,
    goals integer not null,
    assists integer not null,
    clean_sheet boolean not null
  ) on commit drop;
  truncate table pg_temp.sport_final_input;

  begin
    insert into pg_temp.sport_final_input(
      participant_id, present, final_selection_status, goals, assists, clean_sheet
    )
    select
      (item ->> 'participant_id')::uuid,
      coalesce((item ->> 'present')::boolean, false),
      (item ->> 'final_selection_status')::public.sport_selection_status,
      coalesce((item ->> 'goals')::integer, 0),
      coalesce((item ->> 'assists')::integer, 0),
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
      or input.assists < 0 or input.assists > 99
      or input.final_selection_status = 'undecided'
      or (
        not input.present and (
          input.final_selection_status <> 'not_selected'
          or input.goals <> 0
          or input.assists <> 0
          or input.clean_sheet
        )
      )
      or (input.goals > 0 and not input.present)
      or (input.assists > 0 and not input.present)
  ) then
    raise exception 'Final presence, role and statistics are inconsistent' using errcode = '22023';
  end if;

  select
    count(*) filter (where present),
    count(*) filter (where present and final_selection_status = 'starter'),
    coalesce(sum(goals), 0),
    coalesce(sum(assists), 0),
    count(*) filter (where clean_sheet)
  into v_present_count, v_starter_count, v_goal_total, v_assist_total, v_clean_sheet_count
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
  -- Un but ne peut porter qu'une passe décisive : le total des passes ne peut
  -- donc jamais dépasser le nombre de buts marqués par AS Grinta.
  if v_assist_total > p_score_as_grinta then
    raise exception 'Attributed assists exceed the AS Grinta score' using errcode = '22023';
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

  -- AS_GRINTA_FINALIZATION_RETRY_IDEMPOTENCY_V1
  -- Un paquet rejoué après perte de l'accusé réseau ne doit pas fabriquer une
  -- correction : même score, même composition, mêmes participants et même motif
  -- => on renvoie l'état courant sans aucune écriture supplémentaire.
  -- Une correction qui ne touche que les faits du match (minute, passeur) ne
  -- passe jamais par ce raccourci : `v_facts_changed` le neutralise.
  if not v_facts_changed
     and v_existing_version > 0
     and exists (
       select 1
       from public.match_sport_finalizations finalization
       where finalization.match_id = p_match_id
         and finalization.version = v_existing_version
         and finalization.score_as_grinta = p_score_as_grinta
         and finalization.score_adverse = p_score_adverse
         and finalization.composition_version = v_composition_version
     )
     and not exists (
       select 1
       from pg_temp.sport_final_input input
       join public.match_sport_participants participant
         on participant.id = input.participant_id
       where participant.match_id = p_match_id
         and (
           participant.final_presence_status is distinct from case
             when input.present then 'present'::public.sport_final_presence_status
             else 'actual_absent'::public.sport_final_presence_status
           end
           or participant.final_selection_status is distinct from input.final_selection_status
           or participant.final_goals is distinct from input.goals
           or participant.final_assists is distinct from input.assists
           or participant.final_clean_sheet is distinct from input.clean_sheet
         )
     )
     and (
       select audit.reason
       from private.sport_admin_audit_log audit
       where audit.match_id = p_match_id
         and audit.action in ('validate_final_attendance', 'correct_final_attendance')
       order by audit.id desc
       limit 1
     ) is not distinct from v_reason
  then
    return private.match_sport_finalization_snapshot(p_match_id)
      || jsonb_build_object('validation_kind', 'unchanged');
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

  perform public.staff_set_match_attendance(p_match_id, v_permanent_present);
  perform public.staff_set_match_mvp(p_match_id, '{}'::uuid[]);
  perform public.finalize_match_postgame(
    p_match_id,
    p_score_adverse,
    v_permanent_scorers,
    v_permanent_clean_sheet,
    p_score_as_grinta
  );

  -- `finalize_match_postgame` reconstruit intégralement les lignes de buts et
  -- de clean sheet du match ; les passes décisives sont reposées juste après,
  -- sur les mêmes lignes, en créant celles des passeurs qui n'ont ni marqué ni
  -- gardé leur cage inviolée.
  insert into public.match_player_stats(
    match_id, season_player_id, goals, clean_sheet, assists
  )
  select p_match_id, participant.season_player_id, 0, false, input.assists
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.assists > 0
    and participant.season_player_id is not null
  on conflict (match_id, season_player_id) do update
  set assists = excluded.assists,
      updated_at = now();

  create temporary table if not exists pg_temp.old_sport_final (
    participant_id uuid primary key,
    presence_status public.sport_final_presence_status not null,
    selection_status public.sport_selection_status not null,
    goals integer not null,
    assists integer not null,
    clean_sheet boolean not null
  ) on commit drop;
  truncate table pg_temp.old_sport_final;
  insert into pg_temp.old_sport_final
  select participant.id, participant.final_presence_status,
    participant.final_selection_status, participant.final_goals,
    participant.final_assists, participant.final_clean_sheet
  from public.match_sport_participants participant
  where participant.match_id = p_match_id;

  update public.match_sport_participants participant
  set final_presence_status = case
        when input.present then 'present'::public.sport_final_presence_status
        else 'actual_absent'::public.sport_final_presence_status
      end,
      final_selection_status = input.final_selection_status,
      final_goals = input.goals,
      final_assists = input.assists,
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
      'assists', old.assists,
      'clean_sheet', old.clean_sheet
    ),
    jsonb_build_object(
      'presence_status', participant.final_presence_status,
      'selection_status', participant.final_selection_status,
      'goals', participant.final_goals,
      'assists', participant.final_assists,
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
      or old.assists is distinct from participant.final_assists
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
      'attributed_goals', v_goal_total,
      'attributed_assists', v_assist_total
    )
  );

  return v_snapshot;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Validation du compte rendu complet
-- ---------------------------------------------------------------------------

create or replace function private.submit_match_sport_report(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_lineup jsonb,
  p_goal_actions jsonb,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_is_admin boolean;
  v_formation_code text;
  v_field_count integer;
  v_present_count integer;
  v_us_goals integer;
  v_them_goals integer;
  v_clean_sheet_participant uuid;
  v_participants jsonb;
  v_facts_changed boolean;
  v_composition_changed boolean;
  v_current_version integer;
  v_next_version integer;
  v_squad_limit integer;
  v_snapshot jsonb;
  v_finalize_result jsonb;
begin
  perform private.require_sports_management_enabled();

  v_is_admin := private.is_admin();
  if not v_is_admin and not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  -- Un coach non administrateur ne valide que le compte rendu du match qu'il
  -- vient de suivre en direct, comme aujourd'hui à l'export du Live.
  if not v_is_admin and not exists (
    select 1
    from public.match_live_sessions session
    where session.match_id = p_match_id
      and session.state = 'finished'
  ) then
    raise exception 'End the live match before publishing its report' using errcode = '22023';
  end if;

  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_as_grinta not between 0 and 99
     or p_score_adverse is null or p_score_adverse not between 0 and 99 then
    raise exception 'Scores must be between 0 and 99' using errcode = '22023';
  end if;
  if p_lineup is null or jsonb_typeof(p_lineup) <> 'object'
     or jsonb_typeof(p_lineup -> 'entries') <> 'array' then
    raise exception 'Lineup payload must carry a JSON array of entries' using errcode = '22023';
  end if;
  if p_goal_actions is null or jsonb_typeof(p_goal_actions) <> 'array' then
    raise exception 'Goal actions payload must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_goal_actions) > 198 then
    raise exception 'Too many goal actions' using errcode = '22023';
  end if;

  v_formation_code := nullif(btrim(p_lineup ->> 'formation_code'), '');
  if v_formation_code is not null and char_length(v_formation_code) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;

  -- ---------------------------------------------------------------- effectif
  create temporary table if not exists pg_temp.sport_report_lineup (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.sport_report_lineup;

  begin
    insert into pg_temp.sport_report_lineup(
      participant_id, zone, x, y, slot_label, sort_order
    )
    select
      (item ->> 'participant_id')::uuid,
      case item ->> 'zone'
        when 'field' then 'field'::public.sport_composition_zone
        when 'bench' then 'bench'::public.sport_composition_zone
        else 'not_selected'::public.sport_composition_zone
      end,
      case when item ->> 'zone' = 'field'
        then round((item ->> 'x')::numeric, 6) else null end,
      case when item ->> 'zone' = 'field'
        then round((item ->> 'y')::numeric, 6) else null end,
      left(nullif(btrim(item ->> 'slot_label'), ''), 16),
      greatest(coalesce((item ->> 'sort_order')::integer, 0), 0)
    from jsonb_array_elements(p_lineup -> 'entries') item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once' using errcode = '22023';
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid lineup entry' using errcode = '22023';
  end;

  if exists (
    select 1
    from pg_temp.sport_report_lineup entry
    left join public.match_sport_participants participant
      on participant.id = entry.participant_id
     and participant.match_id = p_match_id
     and (
       participant.is_eligible
       or participant.final_presence_status <> 'pending'
     )
    where participant.id is null
  ) then
    raise exception 'The report contains an unknown participant' using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_report_lineup entry
    where entry.zone = 'field'
      and (
        entry.x is null or entry.y is null
        or entry.x < 0 or entry.x > 1
        or entry.y < 0 or entry.y > 1
      )
  ) then
    raise exception 'Every starter needs a position on the pitch' using errcode = '22023';
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone in ('field', 'bench'))
  into v_field_count, v_present_count
  from pg_temp.sport_report_lineup;

  if v_field_count > 11 then
    raise exception 'A match cannot have more than eleven actual starters' using errcode = '22023';
  end if;
  if v_present_count = 0 then
    raise exception 'At least one present participant is required' using errcode = '22023';
  end if;

  -- ---------------------------------------------------------- faits du match
  create temporary table if not exists pg_temp.sport_report_goals (
    ordinal integer primary key,
    minute smallint,
    team_side text not null,
    scorer_participant_id uuid,
    assist_participant_id uuid,
    assist_kind text not null,
    is_own_goal boolean not null,
    source text not null,
    source_live_event_id uuid
  ) on commit drop;
  truncate table pg_temp.sport_report_goals;

  begin
    insert into pg_temp.sport_report_goals(
      ordinal, minute, team_side, scorer_participant_id, assist_participant_id,
      assist_kind, is_own_goal, source, source_live_event_id
    )
    select
      (position - 1)::integer,
      nullif(item ->> 'minute', '')::smallint,
      case item ->> 'team_side'
        when 'opponent' then 'opponent'
        else 'as_grinta'
      end,
      nullif(item ->> 'scorer_participant_id', '')::uuid,
      nullif(item ->> 'assist_participant_id', '')::uuid,
      case
        when nullif(item ->> 'assist_participant_id', '') is not null then 'player'
        when item ->> 'assist_kind' = 'none' then 'none'
        else 'unknown'
      end,
      coalesce((item ->> 'is_own_goal')::boolean, false),
      case item ->> 'source'
        when 'live' then 'live'
        when 'legacy' then 'legacy'
        else 'manual'
      end,
      nullif(item ->> 'source_live_event_id', '')::uuid
    from jsonb_array_elements(p_goal_actions) with ordinality as t(item, position);
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid goal action entry' using errcode = '22023';
  end;

  -- Ni un but adverse ni un CSC ne peut porter une passe décisive.
  update pg_temp.sport_report_goals
  set assist_kind = 'none'
  where team_side = 'opponent' or is_own_goal;

  if exists (
    select 1 from pg_temp.sport_report_goals goal
    where goal.minute is not null and (goal.minute < 0 or goal.minute > 90)
  ) then
    raise exception 'A goal minute must be between 0 and 90' using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_report_goals goal
    where goal.team_side = 'opponent'
      and (goal.scorer_participant_id is not null or goal.assist_participant_id is not null)
  ) then
    raise exception 'An opponent goal cannot be credited to an AS Grinta player'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_report_goals goal
    where goal.is_own_goal
      and (goal.scorer_participant_id is not null or goal.assist_participant_id is not null)
  ) then
    raise exception 'An own goal cannot be credited to a player' using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_report_goals goal
    where goal.assist_participant_id is not null
      and (
        goal.scorer_participant_id is null
        or goal.assist_participant_id = goal.scorer_participant_id
      )
  ) then
    raise exception 'An assist requires a different scorer' using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_report_goals goal
    where (
        goal.scorer_participant_id is not null
        and not exists (
          select 1 from pg_temp.sport_report_lineup entry
          where entry.participant_id = goal.scorer_participant_id
            and entry.zone in ('field', 'bench')
        )
      )
      or (
        goal.assist_participant_id is not null
        and not exists (
          select 1 from pg_temp.sport_report_lineup entry
          where entry.participant_id = goal.assist_participant_id
            and entry.zone in ('field', 'bench')
        )
      )
  ) then
    raise exception 'A scorer or assist must be part of the match squad' using errcode = '22023';
  end if;

  select
    count(*) filter (where team_side = 'as_grinta'),
    count(*) filter (where team_side = 'opponent')
  into v_us_goals, v_them_goals
  from pg_temp.sport_report_goals;

  -- Le score est la conséquence exacte des faits enregistrés.
  if v_us_goals <> p_score_as_grinta or v_them_goals <> p_score_adverse then
    raise exception 'The score must match the recorded goals exactly' using errcode = '22023';
  end if;

  -- ------------------------------------------------------- clean sheet auto
  -- Aucune saisie manuelle : la cage inviolée se déduit du score adverse et du
  -- gardien réellement aligné. Le titulaire prime sur le remplaçant.
  if p_score_adverse = 0 then
    select entry.participant_id
    into v_clean_sheet_participant
    from pg_temp.sport_report_lineup entry
    join public.match_sport_participants participant on participant.id = entry.participant_id
    left join public.season_players player on player.id = participant.season_player_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where entry.zone in ('field', 'bench')
      and coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
    order by
      case when entry.zone = 'field' then 0 else 1 end,
      entry.sort_order,
      entry.participant_id
    limit 1;
  end if;

  -- ------------------------------------- compteurs dérivés des faits du match
  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id', participant.id,
    'present', coalesce(entry.zone in ('field', 'bench'), false),
    'final_selection_status', case
      when entry.zone = 'field' then 'starter'
      when entry.zone = 'bench' then 'substitute'
      else 'not_selected'
    end,
    'goals', coalesce(scored.total, 0),
    'assists', coalesce(assisted.total, 0),
    'clean_sheet', v_clean_sheet_participant is not null
      and participant.id = v_clean_sheet_participant
  )), '[]'::jsonb)
  into v_participants
  from public.match_sport_participants participant
  left join pg_temp.sport_report_lineup entry on entry.participant_id = participant.id
  left join lateral (
    select count(*)::integer as total
    from pg_temp.sport_report_goals goal
    where goal.scorer_participant_id = participant.id
  ) scored on true
  left join lateral (
    select count(*)::integer as total
    from pg_temp.sport_report_goals goal
    where goal.assist_participant_id = participant.id
  ) assisted on true
  where participant.match_id = p_match_id
    and (
      participant.is_eligible
      or participant.final_presence_status <> 'pending'
    );

  -- ------------------------------------------------ écriture des faits du match
  select
    exists (
      select ordinal, minute, team_side, scorer_participant_id,
             assist_participant_id, assist_kind, is_own_goal
      from pg_temp.sport_report_goals
      except
      select ordinal, minute, team_side, scorer_participant_id,
             assist_participant_id, assist_kind, is_own_goal
      from public.match_sport_goal_actions
      where match_id = p_match_id
    )
    or exists (
      select ordinal, minute, team_side, scorer_participant_id,
             assist_participant_id, assist_kind, is_own_goal
      from public.match_sport_goal_actions
      where match_id = p_match_id
      except
      select ordinal, minute, team_side, scorer_participant_id,
             assist_participant_id, assist_kind, is_own_goal
      from pg_temp.sport_report_goals
    )
  into v_facts_changed;

  delete from public.match_sport_goal_actions where match_id = p_match_id;
  insert into public.match_sport_goal_actions(
    match_id, ordinal, minute, team_side, scorer_participant_id,
    assist_participant_id, assist_kind, is_own_goal, source,
    source_live_event_id, created_by, updated_by
  )
  select
    p_match_id, goal.ordinal, goal.minute, goal.team_side,
    goal.scorer_participant_id, goal.assist_participant_id, goal.assist_kind,
    goal.is_own_goal, goal.source, goal.source_live_event_id, v_actor, v_actor
  from pg_temp.sport_report_goals goal;

  perform set_config(
    'as_grinta.sport_report_facts_changed',
    case when v_facts_changed then 'on' else 'off' end,
    true
  );
  if not v_is_admin then
    perform set_config('as_grinta.allow_coach_live_finalize', 'on', true);
  end if;

  v_finalize_result := private.finalize_match_sport_postgame(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse,
    v_participants,
    v_reason
  );

  -- ------------------------------------------- composition réellement alignée
  select
    exists (
      select 1
      from pg_temp.sport_report_lineup entry
      full outer join public.match_composition_entries existing
        on existing.match_id = p_match_id
       and existing.participant_id = entry.participant_id
      where entry.participant_id is null
         or existing.participant_id is null
         or existing.zone is distinct from entry.zone
         or existing.x is distinct from entry.x
         or existing.y is distinct from entry.y
    )
    or exists (
      select 1
      from public.match_compositions composition
      where composition.match_id = p_match_id
        and composition.formation_code is distinct from v_formation_code
    )
  into v_composition_changed;

  if v_composition_changed then
    select composition.version, workflow.squad_size_limit
    into v_current_version, v_squad_limit
    from public.match_compositions composition
    join public.match_sport_workflows workflow
      on workflow.match_id = composition.match_id
    where composition.match_id = p_match_id
    for update of composition, workflow;

    if found then
      perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

      insert into public.match_composition_entries(
        match_id, participant_id, zone, x, y, slot_label, sort_order
      )
      select p_match_id, entry.participant_id, entry.zone, entry.x, entry.y,
             entry.slot_label, entry.sort_order
      from pg_temp.sport_report_lineup entry
      on conflict (match_id, participant_id) do update
      set zone = excluded.zone,
          x = excluded.x,
          y = excluded.y,
          slot_label = excluded.slot_label,
          sort_order = excluded.sort_order;

      -- Un participant absent du compte rendu n'est plus dans l'effectif.
      update public.match_composition_entries existing
      set zone = 'not_selected'::public.sport_composition_zone,
          x = null,
          y = null,
          slot_label = null
      where existing.match_id = p_match_id
        and existing.zone <> 'not_selected'
        and not exists (
          select 1 from pg_temp.sport_report_lineup entry
          where entry.participant_id = existing.participant_id
        );

      update public.match_sport_participants participant
      set selection_status = case entry.zone
            when 'field' then 'starter'::public.sport_selection_status
            when 'bench' then 'substitute'::public.sport_selection_status
            else 'not_selected'::public.sport_selection_status
          end,
          selection_updated_at = now(),
          selection_updated_by = v_actor,
          updated_at = now()
      from public.match_composition_entries entry
      where participant.match_id = p_match_id
        and entry.match_id = p_match_id
        and entry.participant_id = participant.id;

      v_next_version := v_current_version + 1;

      update public.match_compositions
      set formation_code = coalesce(v_formation_code, formation_code),
          status = 'published',
          version = v_next_version,
          has_unpublished_changes = false,
          squad_size_exception_approved = v_present_count > v_squad_limit,
          published_at = now(),
          published_by = v_actor,
          last_modified_at = now(),
          last_modified_by = v_actor
      where match_id = p_match_id;

      update public.match_sport_workflows
      set composition_state = 'published',
          composition_version = v_next_version,
          updated_by = v_actor,
          updated_at = now()
      where match_id = p_match_id;

      update public.match_sport_finalizations
      set composition_version = v_next_version,
          updated_at = now()
      where match_id = p_match_id;

      v_snapshot := private.composition_snapshot(p_match_id)
        || jsonb_build_object(
          'published_at', now(),
          'publication_kind', 'postmatch'
        );

      insert into public.match_composition_publications(
        match_id, version, formation_code, snapshot, publication_kind, published_by
      )
      select p_match_id, v_next_version, composition.formation_code, v_snapshot,
             'postmatch', v_actor
      from public.match_compositions composition
      where composition.match_id = p_match_id;

      insert into private.sport_admin_audit_log(
        match_id, action, actor_profile_id, reason, metadata
      ) values (
        p_match_id,
        'publish_match_report_composition',
        v_actor,
        v_reason,
        jsonb_build_object(
          'composition_version', v_next_version,
          'field_count', v_field_count,
          'present_count', v_present_count,
          'source', 'match_report'
        )
      );
    end if;
  end if;

  if v_facts_changed then
    insert into private.sport_admin_audit_log(
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id,
      'update_match_goal_actions',
      v_actor,
      v_reason,
      jsonb_build_object(
        'as_grinta_goals', v_us_goals,
        'opponent_goals', v_them_goals,
        'attributed_scorers', (
          select count(*) from pg_temp.sport_report_goals
          where scorer_participant_id is not null
        ),
        'attributed_assists', (
          select count(*) from pg_temp.sport_report_goals
          where assist_participant_id is not null
        )
      )
    );
  end if;

  -- Le suivi en direct est consommé : sa chronologie reste lisible, mais le
  -- compte rendu est désormais la référence.
  update public.match_live_sessions session
  set exported = true,
      exported_at = coalesce(session.exported_at, now()),
      score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      updated_by = v_actor,
      updated_at = now()
  where session.match_id = p_match_id
    and session.state = 'finished';

  return private.get_match_sport_report(p_match_id)
    || jsonb_build_object(
      'validation_kind', coalesce(v_finalize_result ->> 'validation_kind', 'initial')
    );
end;
$function$;

alter function private.submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  owner to postgres;
revoke all on function private.submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  from public;
grant execute on function private.submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  to authenticated;
grant execute on function private.submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  to service_role;

create or replace function public.admin_submit_match_sport_report(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_lineup jsonb,
  p_goal_actions jsonb,
  p_reason text default null::text
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_result jsonb;
  v_vote_state public.sport_vote_state;
begin
  v_result := private.submit_match_sport_report(
    p_match_id, p_score_as_grinta, p_score_adverse, p_lineup, p_goal_actions, p_reason
  );

  select workflow.vote_state
  into v_vote_state
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  return v_result || jsonb_build_object('vote_state', v_vote_state);
end;
$function$;

alter function public.admin_submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  owner to postgres;
revoke all on function public.admin_submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  from public;
grant execute on function public.admin_submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  to authenticated;
grant execute on function public.admin_submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text)
  to service_role;

comment on function public.admin_submit_match_sport_report(uuid, integer, integer, jsonb, jsonb, text) is
  'Valide ou corrige le compte rendu complet en une seule opération : effectif réel, faits du match, score et statistiques dérivées.';

-- ---------------------------------------------------------------------------
-- 3. Ajouter un joueur à l'effectif du compte rendu
-- ---------------------------------------------------------------------------
--
-- Les joueurs du roster ont déjà une participation : les remettre dans le
-- compte rendu ne demande rien au serveur. Cette fonction ne sert qu'aux cas
-- où la participation n'existe pas encore : joueur du roster jamais rattaché,
-- invité connu, ou invité créé après coup.

create or replace function private.attach_match_sport_report_player(
  p_match_id uuid,
  p_season_player_id uuid default null::uuid,
  p_guest_player_id uuid default null::uuid,
  p_first_name text default null::text,
  p_last_name text default null::text,
  p_is_goalkeeper boolean default false,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_first_name text := nullif(btrim(p_first_name), '');
  v_last_name text := nullif(btrim(p_last_name), '');
  v_season_id uuid;
  v_status text;
  v_guest public.guest_players%rowtype;
  v_participant_id uuid;
  v_bench_order integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() and not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;
  if num_nonnulls(p_season_player_id, p_guest_player_id, v_first_name) <> 1 then
    raise exception 'Provide exactly one player to add' using errcode = '22023';
  end if;

  select match.season_id, match.status::text
  into v_season_id, v_status
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;
  if v_status = 'archive' then
    raise exception 'La fenêtre de correction du match est fermée.' using errcode = '22023';
  end if;
  if v_status = 'termine' then
    perform private.assert_match_postgame_correction_open(p_match_id);
  end if;

  if p_season_player_id is not null then
    perform 1
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    where player.id = p_season_player_id
      and player.season_id = v_season_id
      and player.is_active
      and (player.profile_id is null or profile.status = 'active')
    for update of player;
    if not found then
      raise exception 'Roster player is not active for this match season' using errcode = '22023';
    end if;

    insert into public.match_sport_participants(
      match_id, season_player_id, is_eligible, availability_status,
      convocation_status, convocation_manual_override, selection_status
    ) values (
      p_match_id, p_season_player_id, true, 'available', 'convoked', true, 'substitute'
    )
    on conflict (match_id, season_player_id) do update
    set is_eligible = true,
        convocation_status = 'convoked',
        convocation_manual_override = true,
        updated_at = now()
    returning id into v_participant_id;
  else
    if p_guest_player_id is not null then
      select guest.* into v_guest
      from public.guest_players guest
      where guest.id = p_guest_player_id
        and guest.is_reusable
        and guest.archived_at is null
      for update;
      if not found then
        raise exception 'Guest player is unavailable or archived' using errcode = '22023';
      end if;
    else
      if char_length(v_first_name) > 80
         or (v_last_name is not null and char_length(v_last_name) > 80) then
        raise exception 'Guest name cannot exceed 80 characters per field' using errcode = '22023';
      end if;

      select guest.* into v_guest
      from public.guest_players guest
      where guest.is_reusable
        and guest.archived_at is null
        and lower(btrim(guest.first_name)) = lower(v_first_name)
        and lower(coalesce(btrim(guest.last_name), '')) = lower(coalesce(v_last_name, ''))
        and guest.is_goalkeeper = coalesce(p_is_goalkeeper, false)
      order by guest.created_at
      limit 1
      for update;

      if not found then
        insert into public.guest_players(
          first_name, last_name, is_goalkeeper, created_by, updated_by
        )
        values (
          v_first_name, v_last_name, coalesce(p_is_goalkeeper, false),
          v_actor, v_actor
        )
        returning * into v_guest;
      end if;
    end if;

    insert into public.match_sport_participants(
      match_id, guest_player_id, is_eligible, availability_status,
      convocation_status, convocation_manual_override, selection_status,
      waitlist_turn_state
    ) values (
      p_match_id, v_guest.id, true, 'not_applicable', 'convoked', true,
      'substitute', 'not_applicable'
    )
    -- L'unicité invité est un index partiel : le prédicat doit être répété
    -- pour que PostgreSQL reconnaisse la contrainte visée.
    on conflict (match_id, guest_player_id) where guest_player_id is not null
    do update
    set is_eligible = true,
        convocation_status = 'convoked',
        convocation_manual_override = true,
        updated_at = now()
    returning id into v_participant_id;
  end if;

  -- Le joueur rejoint l'effectif sur le banc : l'administrateur le place
  -- ensuite sur le terrain s'il le souhaite.
  if exists (
    select 1 from public.match_compositions composition
    where composition.match_id = p_match_id
  ) then
    select coalesce(max(entry.sort_order), -1) + 1
    into v_bench_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id;

    if v_status in ('termine', 'archive') then
      perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);
    end if;

    insert into public.match_composition_entries(
      match_id, participant_id, zone, sort_order
    ) values (
      p_match_id, v_participant_id, 'bench', coalesce(v_bench_order, 0)
    )
    on conflict (match_id, participant_id) do update
    -- Un joueur déjà titulaire le reste ; sinon il rejoint le banc.
    set zone = case
          when public.match_composition_entries.zone = 'field'
            then 'field'::public.sport_composition_zone
          else 'bench'::public.sport_composition_zone
        end,
        updated_at = now();
  end if;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'add_match_report_player',
    v_actor,
    v_reason,
    jsonb_build_object(
      'participant_id', v_participant_id,
      'season_player_id', p_season_player_id,
      'guest_player_id', v_guest.id
    )
  );

  return private.get_match_sport_report(p_match_id)
    || jsonb_build_object('added_participant_id', v_participant_id);
end;
$function$;

alter function private.attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  owner to postgres;
revoke all on function private.attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  from public;
grant execute on function private.attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  to authenticated;
grant execute on function private.attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  to service_role;

create or replace function public.admin_attach_match_sport_report_player(
  p_match_id uuid,
  p_season_player_id uuid default null::uuid,
  p_guest_player_id uuid default null::uuid,
  p_first_name text default null::text,
  p_last_name text default null::text,
  p_is_goalkeeper boolean default false,
  p_reason text default null::text
)
returns jsonb
language sql
set search_path to ''
as $function$
  select private.attach_match_sport_report_player(
    p_match_id, p_season_player_id, p_guest_player_id,
    p_first_name, p_last_name, p_is_goalkeeper, p_reason
  );
$function$;

alter function public.admin_attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  owner to postgres;
revoke all on function public.admin_attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  from public;
grant execute on function public.admin_attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  to authenticated;
grant execute on function public.admin_attach_match_sport_report_player(uuid, uuid, uuid, text, text, boolean, text)
  to service_role;

commit;
