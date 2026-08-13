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
  current_season_matches as (
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
  current_seasons as (
    select
      season_id,
      count(*)::int as matches_played,
      count(*) filter (where win)::int as wins,
      coalesce(sum(goals), 0)::int as goals,
      count(*) filter (where clean_sheet)::int as clean_sheets
    from current_season_matches
    group by season_id
  ),
  canonical_player as (
    select player_id
    from public.profiles
    where id = p_profile_id
  ),
  historical_seasons as (
    select
      case
        when extract(month from hms.match_date) >= 7
          then extract(year from hms.match_date)::int
        else extract(year from hms.match_date)::int - 1
      end as season_start_year,
      count(*) filter (where hmp.is_present)::int as matches_played,
      count(*) filter (
        where hmp.is_present and hms.score_as_grinta > hms.score_adverse
      )::int as wins,
      coalesce(sum(hmp.goals) filter (where hmp.is_present), 0)::int as goals,
      count(*) filter (
        where hmp.is_present
          and coalesce(hmp.is_goalkeeper, false)
          and hms.score_adverse = 0
      )::int as clean_sheets
    from public.historical_match_players hmp
    join public.historical_match_scores hms on hms.id = hmp.match_id
    join canonical_player cp on cp.player_id = hmp.player_id
    group by 1
  ),
  all_seasons as (
    select matches_played, wins, goals, clean_sheets from current_seasons
    union all
    select matches_played, wins, goals, clean_sheets from historical_seasons
  ),
  season_best as (
    select
      coalesce(max(matches_played), 0)::int as matches_played_season,
      coalesce(max(wins), 0)::int as wins_season,
      coalesce(max(goals), 0)::int as goals_season,
      coalesce(max(clean_sheets), 0)::int as clean_sheets_season
    from all_seasons
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

revoke all on function public.profile_badge_display_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_display_metrics(uuid) to authenticated, service_role;

drop function public.featured_badges();

create function public.featured_badges()
returns table(
  profile_id uuid,
  code text,
  emoji text,
  image_url text,
  color text,
  metric text,
  threshold integer,
  display_value integer,
  has_star boolean,
  stars integer,
  category text,
  sort_order integer
)
language sql
stable
set search_path = ''
as $function$
  with featured_profiles as materialized (
    select distinct pb.profile_id
    from public.profile_badges pb
    where pb.featured
  ),
  profile_display_metrics as materialized (
    select
      fp.profile_id,
      dm.metric,
      dm.display_value
    from featured_profiles fp
    cross join lateral public.profile_badge_display_metrics(fp.profile_id) dm
  ),
  starred_featured as materialized (
    select distinct
      pb.profile_id,
      b.code
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.featured
      and b.has_star
  ),
  starred_profiles as materialized (
    select distinct sf.profile_id
    from starred_featured sf
  ),
  featured_stars as materialized (
    select
      sp.profile_id,
      bs.badge_code,
      bs.stars
    from starred_profiles sp
    cross join lateral public.profile_badge_stars(sp.profile_id) bs
    join starred_featured sf
      on sf.profile_id = sp.profile_id
     and sf.code = bs.badge_code
  )
  select
    pb.profile_id,
    b.code,
    b.emoji,
    b.image_url,
    b.color,
    b.metric,
    b.threshold,
    case
      when b.metric is null then null
      else coalesce(pdm.display_value, 0)
    end as display_value,
    b.has_star,
    coalesce(fs.stars, 1) as stars,
    b.category,
    b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  left join profile_display_metrics pdm
    on pdm.profile_id = pb.profile_id
   and pdm.metric = b.metric
  left join featured_stars fs
    on fs.profile_id = pb.profile_id
   and fs.badge_code = b.code
  where pb.featured
  order by pb.profile_id, b.sort_order;
$function$;

revoke all on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges() to authenticated, service_role;
