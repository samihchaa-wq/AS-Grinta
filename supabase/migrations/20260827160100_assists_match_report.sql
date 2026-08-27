begin;

-- Passes décisives : compte rendu de match et statistiques joueurs.
--
-- Le compte rendu (feuille de match après coup comme export du Live) transporte
-- désormais `assists` par participant, au même titre que `goals`. Les invités
-- restent hors des statistiques permanentes, comme pour les buts.

-- ---------------------------------------------------------------------------
-- 1. Instantané du compte rendu : exposer les passes décisives
-- ---------------------------------------------------------------------------

create or replace function private.match_sport_finalization_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
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
    'is_home', match.location = 'domicile',
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
          else coalesce(
            nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
            nullif(btrim(player.first_name), ''),
            btrim(concat_ws(' ', player.first_name, player.last_name))
          )
        end,
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
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
        'assists', participant.final_assists,
        'clean_sheet', participant.final_clean_sheet,
        'is_motm', exists (
          select 1
          from public.match_sport_motm_results result
          where result.match_id = p_match_id
            and result.participant_id = participant.id
            and result.is_winner
            and result.finalization_version = (
              select max(latest.finalization_version)
              from public.match_sport_motm_results latest
              where latest.match_id = p_match_id
            )
        )
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(profile.surnom, profile.first_name, player.first_name, guest.first_name)),
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
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Validation du compte rendu : accepter et enregistrer les passes décisives
-- ---------------------------------------------------------------------------

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
  if v_existing_version > 0
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
-- 3. Contrôle d'intégrité : les passes décisives suivent le même chemin
-- ---------------------------------------------------------------------------

create or replace function private.get_match_sport_statistics_integrity(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', finalization.match_id,
    'finalization_version', finalization.version,
    'permanent_present_expected', expected.present_count,
    'attendance_rows', actual.attendance_count,
    'goals_expected', expected.goals_count,
    'goals_in_statistics', actual.goals_count,
    'assists_expected', expected.assists_count,
    'assists_in_statistics', actual.assists_count,
    'clean_sheets_expected', expected.clean_sheet_count,
    'clean_sheets_in_statistics', actual.clean_sheet_count,
    'permanent_motm_expected', expected.motm_count,
    'motm_rows', actual.motm_count,
    'attendance_ok', expected.present_count = actual.attendance_count,
    'goals_ok', expected.goals_count = actual.goals_count,
    'assists_ok', expected.assists_count = actual.assists_count,
    'clean_sheets_ok', expected.clean_sheet_count = actual.clean_sheet_count,
    'motm_ok', expected.motm_count = actual.motm_count,
    'all_ok', expected.present_count = actual.attendance_count
      and expected.goals_count = actual.goals_count
      and expected.assists_count = actual.assists_count
      and expected.clean_sheet_count = actual.clean_sheet_count
      and expected.motm_count = actual.motm_count
  ) into v_result
  from public.match_sport_finalizations finalization
  cross join lateral (
    select
      count(*) filter (
        where participant.final_presence_status = 'present'
          and participant.season_player_id is not null
      )::integer as present_count,
      coalesce(sum(participant.final_goals) filter (
        where participant.season_player_id is not null
      ), 0)::integer as goals_count,
      coalesce(sum(participant.final_assists) filter (
        where participant.season_player_id is not null
      ), 0)::integer as assists_count,
      count(*) filter (
        where participant.season_player_id is not null
          and participant.final_clean_sheet
      )::integer as clean_sheet_count,
      (
        select count(*)::integer
        from public.match_sport_motm_results result
        join public.match_sport_participants winner
          on winner.id = result.participant_id and winner.match_id = result.match_id
        where result.match_id = finalization.match_id
          and result.is_winner
          and winner.season_player_id is not null
      ) as motm_count
    from public.match_sport_participants participant
    where participant.match_id = finalization.match_id
  ) expected
  cross join lateral (
    select
      (select count(*)::integer from public.match_attendance attendance
       where attendance.match_id = finalization.match_id) as attendance_count,
      (select coalesce(sum(stats.goals), 0)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id) as goals_count,
      (select coalesce(sum(stats.assists), 0)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id) as assists_count,
      (select count(*)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id and stats.clean_sheet) as clean_sheet_count,
      (select count(*)::integer from public.match_man_of_match motm
       where motm.match_id = finalization.match_id) as motm_count
  ) actual
  where finalization.match_id = p_match_id;

  if v_result is null then
    raise exception 'Final attendance must be validated first' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

commit;
