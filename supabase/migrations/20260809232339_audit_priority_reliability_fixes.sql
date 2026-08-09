-- Reliability and consistency fixes from the authenticated production audit.

-- MOTM must remain open until its planned 24h deadline.
create or replace function private.admin_close_match_motm_vote_early(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_version integer;
  v_closes_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select election.finalization_version, election.closes_at
  into v_version, v_closes_at
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
    and election.state = 'open'
  for update;

  if not found then
    raise exception 'Only an open MOTM vote can be closed' using errcode = '22023';
  end if;
  if v_closes_at is null then
    raise exception 'MOTM close deadline is missing' using errcode = '22023';
  end if;
  if now() < v_closes_at then
    raise exception 'MOTM vote must remain open until its 24-hour deadline'
      using errcode = '22023';
  end if;

  if not private.close_match_motm_election(p_match_id, false) then
    raise exception 'MOTM vote could not be closed' using errcode = '22023';
  end if;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'close_motm_vote_manual',
    v_actor,
    v_reason,
    jsonb_build_object(
      'finalization_version', v_version,
      'closes_at', v_closes_at
    )
  );

  return private.get_admin_match_motm_dashboard(p_match_id);
end;
$function$;

-- Non-player authenticated accounts are simply not concerned by availability.
create or replace function private.get_my_match_availability(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
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
  where participant.match_id = p_match_id
    and player.profile_id = v_actor;

  return v_result;
end;
$function$;

-- Restore the position-history RPC expected by the Flutter client.
create or replace function private.get_player_position_history(
  p_since timestamptz
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'player_id', identity.player_id,
        'x', entry.x,
        'y', entry.y,
        'kickoff_at', match.kickoff_at
      )
    ),
    '[]'::jsonb
  )
  into v_result
  from public.match_composition_entries entry
  join public.matches match on match.id = entry.match_id
  join public.match_sport_participants participant
    on participant.id = entry.participant_id
  left join public.season_players season_player
    on season_player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  cross join lateral (
    select coalesce(season_player.player_id, guest.player_id) as player_id
  ) identity
  where match.status in ('termine', 'archive')
    and match.kickoff_at >= p_since
    and entry.zone = 'field'::public.sport_composition_zone
    and entry.x is not null
    and entry.y is not null
    and identity.player_id is not null;

  return v_result;
end;
$function$;

create or replace function public.admin_get_player_position_history(
  p_since timestamptz
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_player_position_history(p_since);
$function$;

revoke execute on function private.get_player_position_history(timestamptz)
  from public, anon;
revoke execute on function public.admin_get_player_position_history(timestamptz)
  from public, anon;
grant execute on function private.get_player_position_history(timestamptz)
  to authenticated, service_role;
grant execute on function public.admin_get_player_position_history(timestamptz)
  to authenticated, service_role;

-- Save the whole season prediction form atomically.
create or replace function private.save_my_season_predictions(
  p_season_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_locked_at timestamptz;
  v_count integer;
  v_expected integer;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_season_id is null then
    raise exception 'Season is required' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Predictions must be an array' using errcode = '22023';
  end if;

  select season.season_predictions_locked_at
  into v_locked_at
  from public.seasons season
  where season.id = p_season_id
    and season.status = 'open'
  for update;

  if not found then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;
  if v_locked_at is not null then
    raise exception 'Season predictions are locked' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(p_items);

  if v_count < 1 or v_count > 100 then
    raise exception 'Invalid prediction item count' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(
      season_player_id uuid,
      category text,
      predicted_value_30 integer
    )
    where item.season_player_id is null
      or item.category not in ('buts', 'clean_sheets')
      or item.predicted_value_30 is null
      or item.predicted_value_30 < 0
      or item.predicted_value_30 > 99
  ) then
    raise exception 'Invalid season prediction value' using errcode = '22023';
  end if;

  if (
    select count(*)
    from (
      select item.season_player_id, item.category
      from jsonb_to_recordset(p_items) as item(
        season_player_id uuid,
        category text,
        predicted_value_30 integer
      )
      group by item.season_player_id, item.category
    ) unique_items
  ) <> v_count then
    raise exception 'Duplicate season prediction item' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_expected
  from public.season_players player
  where player.season_id = p_season_id
    and player.is_active;

  if v_count <> v_expected then
    raise exception 'The complete active roster must be submitted'
      using errcode = '22023';
  end if;

  if (
    select count(*)
    from jsonb_to_recordset(p_items) as item(
      season_player_id uuid,
      category text,
      predicted_value_30 integer
    )
    join public.season_players player
      on player.id = item.season_player_id
     and player.season_id = p_season_id
     and player.is_active
    where (player.is_goalkeeper and item.category = 'clean_sheets')
       or (not player.is_goalkeeper and item.category = 'buts')
  ) <> v_count then
    raise exception 'Prediction items do not match the active roster'
      using errcode = '22023';
  end if;

  insert into public.season_predictions(
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    predicted_value_30,
    is_filled,
    updated_at
  )
  select
    p_season_id,
    v_actor,
    item.season_player_id,
    item.category,
    item.predicted_value_30,
    true,
    now()
  from jsonb_to_recordset(p_items) as item(
    season_player_id uuid,
    category text,
    predicted_value_30 integer
  )
  on conflict (
    season_id,
    predictor_profile_id,
    season_player_id,
    category
  )
  do update set
    predicted_value_30 = excluded.predicted_value_30,
    is_filled = true,
    updated_at = now();

  return jsonb_build_object(
    'season_id', p_season_id,
    'saved', v_count
  );
end;
$function$;

create or replace function public.save_my_season_predictions(
  p_season_id uuid,
  p_items jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.save_my_season_predictions(p_season_id, p_items);
$function$;

revoke execute on function private.save_my_season_predictions(uuid, jsonb)
  from public, anon;
revoke execute on function public.save_my_season_predictions(uuid, jsonb)
  from public, anon;
grant execute on function private.save_my_season_predictions(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.save_my_season_predictions(uuid, jsonb)
  to authenticated, service_role;

-- Integrity report: internal matches intentionally have no odds/predictions.
create or replace function public.staff_app_integrity_report()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_checks jsonb;
  v_total bigint;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  with checks as (
    select 'matches_without_odds'::text as check_name, count(*)::bigint as issue_count
    from public.matches m
    left join public.match_odds mo on mo.match_id = m.id
    where m.match_type <> 'entre_nous'
      and mo.match_id is null

    union all

    select 'finished_without_scores', count(*)::bigint
    from public.matches
    where status in ('termine', 'archive')
      and (score_as_grinta is null or score_adverse is null)

    union all

    select 'upcoming_with_scores', count(*)::bigint
    from public.matches
    where status = 'a_venir'
      and (score_as_grinta is not null or score_adverse is not null)

    union all

    select 'duplicate_match_datetime', count(*)::bigint
    from (
      select match_date, match_time
      from public.matches
      group by match_date, match_time
      having count(*) > 1
    ) duplicates

    union all

    select 'multiple_open_seasons', greatest(count(*) - 1, 0)::bigint
    from public.seasons
    where status = 'open'

    union all

    select 'orphan_match_predictions', count(*)::bigint
    from public.match_predictions mp
    left join public.matches m on m.id = mp.match_id
    left join public.profiles p on p.id = mp.profile_id
    where m.id is null or p.id is null

    union all

    select 'filled_predictions_missing_scores', count(*)::bigint
    from public.match_predictions
    where is_filled
      and (
        predicted_score_as_grinta is null
        or predicted_score_adverse is null
      )

    union all

    select 'missing_upcoming_prediction_seeds', count(*)::bigint
    from public.matches m
    cross join public.profiles p
    left join public.match_predictions mp
      on mp.match_id = m.id
     and mp.profile_id = p.id
    where m.status = 'a_venir'
      and m.match_type <> 'entre_nous'
      and p.status = 'active'
      and mp.id is null

    union all

    select 'missing_open_season_prediction_seeds', count(*)::bigint
    from public.seasons s
    join public.season_players sp
      on sp.season_id = s.id
     and sp.is_active
    cross join public.profiles p
    left join public.season_predictions prediction
      on prediction.season_id = s.id
     and prediction.predictor_profile_id = p.id
     and prediction.season_player_id = sp.id
     and prediction.category = case
       when sp.is_goalkeeper then 'clean_sheets'
       else 'buts'
     end
    where s.status = 'open'
      and p.status = 'active'
      and prediction.id is null

    union all

    select 'kickoff_mismatch', count(*)::bigint
    from public.matches m
    where m.match_time is not null
      and m.kickoff_at is distinct from
        ((m.match_date + m.match_time) at time zone 'Europe/Paris')
  ), aggregated as (
    select
      coalesce(sum(issue_count), 0)::bigint as total_issues,
      jsonb_agg(
        jsonb_build_object(
          'check', check_name,
          'issues', issue_count
        )
        order by check_name
      ) as checks
    from checks
  )
  select total_issues, checks
  into v_total, v_checks
  from aggregated;

  return jsonb_build_object(
    'healthy', v_total = 0,
    'total_issues', v_total,
    'checked_at', now(),
    'checks', coalesce(v_checks, '[]'::jsonb)
  );
end;
$function$;

-- Prevent duplicate reusable guest identities under concurrent creation.
create unique index if not exists guest_players_reusable_identity_unique_idx
on public.guest_players (
  lower(btrim(first_name)),
  lower(coalesce(btrim(last_name), '')),
  is_goalkeeper
)
where is_reusable;

-- Align notification delivery kinds with the currently supported worker.
alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;

alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check
  check (
    kind in (
      'availability_open',
      'availability_j3',
      'availability_j1',
      'availability_manual',
      'motm_open',
      'prediction_j5',
      'match_cancelled',
      'match_rescheduled_date',
      'match_rescheduled_time',
      'convocation_promoted'
    )
  ) not valid;

alter table public.push_delivery_log
  validate constraint push_delivery_log_kind_check;

-- Harden registration throttling.
create or replace function public.consume_registration_rate_limit(p_origin_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_origin_hour integer;
  v_origin_day integer;
  v_global_hour integer;
begin
  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid origin hash' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('registration-rate-limit-global', 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_origin_hash, 0)
  );

  delete from private.registration_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer
  into v_origin_hour
  from private.registration_attempts
  where origin_hash = p_origin_hash
    and attempted_at >= now() - interval '1 hour';

  select count(*)::integer
  into v_origin_day
  from private.registration_attempts
  where origin_hash = p_origin_hash
    and attempted_at >= now() - interval '24 hours';

  select count(*)::integer
  into v_global_hour
  from private.registration_attempts
  where attempted_at >= now() - interval '1 hour';

  if v_origin_hour >= 5 or v_origin_day >= 15 or v_global_hour >= 120 then
    return false;
  end if;

  insert into private.registration_attempts(origin_hash)
  values (p_origin_hash);

  return true;
end;
$function$;
