set local lock_timeout = '5s';

create or replace function public.profile_badge_display_metrics(p_profile_id uuid)
returns table(metric text, current_value integer, display_value integer)
language sql
stable
set search_path = ''
as $function$
  with raw_metrics as (
    select to_jsonb(m) as metrics
    from public.profile_badge_metrics(p_profile_id) m
  ),
  tracked_matches as (
    select
      m.season_id,
      (m.score_as_grinta > m.score_adverse) as win,
      coalesce(st.goals, 0) as goals,
      coalesce(st.clean_sheet, false) as clean_sheet
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id
     and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id
     and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id
     and att.match_id = m.id
    left join public.match_man_of_match motm
      on motm.season_player_id = sp.id
     and motm.match_id = m.id
    where sp.profile_id = p_profile_id
      and (st.match_id is not null or att.match_id is not null or motm.match_id is not null)
  ),
  tracked_seasons as (
    select
      season_id,
      count(*)::int as matches_played,
      count(*) filter (where win)::int as wins,
      coalesce(sum(goals), 0)::int as goals,
      count(*) filter (where clean_sheet)::int as clean_sheets
    from tracked_matches
    group by season_id
  ),
  season_best as (
    select
      coalesce(max(matches_played), 0)::int as matches_played_season,
      coalesce(max(wins), 0)::int as wins_season,
      coalesce(max(goals), 0)::int as goals_season,
      coalesce(max(clean_sheets), 0)::int as clean_sheets_season
    from tracked_seasons
  ),
  badge_metrics as (
    select distinct b.metric
    from public.badges b
    where b.metric is not null
  )
  select
    bm.metric,
    coalesce((rm.metrics ->> bm.metric)::int, 0) as current_value,
    case bm.metric
      when 'matches_played_season' then sb.matches_played_season
      when 'wins_season' then sb.wins_season
      when 'goals_season' then sb.goals_season
      when 'clean_sheets_season' then sb.clean_sheets_season
      else coalesce((rm.metrics ->> bm.metric)::int, 0)
    end as display_value
  from badge_metrics bm
  cross join raw_metrics rm
  cross join season_best sb;
$function$;
