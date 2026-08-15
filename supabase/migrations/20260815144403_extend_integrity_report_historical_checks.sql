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

    union all

    select 'historical_multiple_motm', count(*)::bigint
    from (
      select hmp.match_id
      from public.historical_match_players hmp
      where hmp.is_motm
      group by hmp.match_id
      having count(*) > 1
    ) matches_with_multiple_motm

    union all

    select 'historical_goals_exceed_team_score', count(*)::bigint
    from (
      select hms.id
      from public.historical_match_scores hms
      left join public.historical_match_players hmp on hmp.match_id = hms.id
      where hms.score_as_grinta is not null
      group by hms.id, hms.score_as_grinta
      having coalesce(sum(hmp.goals), 0) > hms.score_as_grinta
    ) matches_with_excess_goals

    union all

    select 'historical_matches_without_players', count(*)::bigint
    from public.historical_match_scores hms
    where not exists (
      select 1
      from public.historical_match_players hmp
      where hmp.match_id = hms.id
    )

    union all

    select 'historical_unattributed_goals', count(*)::bigint
    from (
      select hms.id
      from public.historical_match_scores hms
      left join public.historical_match_players hmp on hmp.match_id = hms.id
      where hms.score_as_grinta is not null
      group by hms.id, hms.score_as_grinta
      having coalesce(sum(hmp.goals), 0) < hms.score_as_grinta
    ) matches_with_unattributed_goals
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
