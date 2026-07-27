begin;

create or replace view public.v_statistics_players
with (security_invoker = true)
as
with open_season as (
  select id, name
  from public.seasons
  where status = 'open'
  order by created_at desc
  limit 1
),
prev_ref as (
  select season.id, season.name
  from public.seasons season
  cross join open_season current
  where season.name < current.name
  order by season.name desc
  limit 1
),
app_present as (
  select present.match_id, present.season_player_id, match.season_id,
         match.score_as_grinta, match.score_adverse
  from (
    select match_id, season_player_id from public.match_attendance
    union
    select match_id, season_player_id from public.match_player_stats
    union
    select match_id, season_player_id from public.match_man_of_match
  ) present
  join public.matches match on match.id = present.match_id
    and match.status in ('termine', 'archive')
),
app_results as (
  select season_player_id,
    count(*)::integer as matches_played,
    count(*) filter (where score_as_grinta > score_adverse)::integer as wins,
    count(*) filter (where score_as_grinta = score_adverse)::integer as draws,
    count(*) filter (where score_as_grinta < score_adverse)::integer as losses
  from app_present
  group by season_player_id
),
app_pstats as (
  select stats.season_player_id,
    coalesce(sum(stats.goals), 0)::integer as goals,
    count(*) filter (where stats.clean_sheet)::integer as clean_sheets
  from public.match_player_stats stats
  join public.matches match on match.id = stats.match_id
    and match.status in ('termine', 'archive')
  group by stats.season_player_id
),
app_mvp as (
  select mvp.season_player_id,
    count(distinct mvp.match_id)::integer as hdm
  from public.match_man_of_match mvp
  join public.matches match on match.id = mvp.match_id
    and match.status in ('termine', 'archive')
  group by mvp.season_player_id
),
app_season_player as (
  select season_player.season_id,
    season_player.profile_id,
    season_player.position as display_order,
    coalesce(nullif(btrim(profile.surnom), ''), season_player.first_name) as display_name,
    concat_ws(' ', season_player.first_name, nullif(season_player.last_name, '')) as full_name,
    season_player.is_goalkeeper,
    coalesce(results.matches_played, 0) as matches_played,
    coalesce(results.wins, 0) as wins,
    coalesce(results.draws, 0) as draws,
    coalesce(results.losses, 0) as losses,
    coalesce(player_stats.goals, 0) as goals,
    coalesce(mvp.hdm, 0) as hdm,
    coalesce(player_stats.clean_sheets, 0) as clean_sheets,
    case when season_player.is_goalkeeper then coalesce(player_stats.clean_sheets, 0)
         else coalesce(player_stats.goals, 0) end as ranking_metric
  from public.season_players season_player
  left join public.profiles profile on profile.id = season_player.profile_id
  left join app_results results on results.season_player_id = season_player.id
  left join app_pstats player_stats on player_stats.season_player_id = season_player.id
  left join app_mvp mvp on mvp.season_player_id = season_player.id
  where season_player.is_active
),
prev_has_app as (
  select exists (
    select 1
    from app_season_player player
    join prev_ref previous on previous.id = player.season_id
  ) as has_app
),
current_ranked as (
  select 'current'::text as period_key,
    current.name as period_label,
    rank() over (partition by player.is_goalkeeper order by player.ranking_metric desc)::integer as display_rank,
    coalesce(player.display_order, 9999)::integer as display_order,
    player.display_name as player_name,
    player.is_goalkeeper,
    player.matches_played, player.wins, player.draws, player.losses,
    player.goals, player.hdm, player.clean_sheets, player.profile_id
  from app_season_player player
  join open_season current on current.id = player.season_id
),
previous_from_app as (
  select 'previous'::text as period_key,
    previous.name as period_label,
    rank() over (partition by player.is_goalkeeper order by player.ranking_metric desc)::integer as display_rank,
    coalesce(player.display_order, 9999)::integer as display_order,
    player.display_name as player_name,
    player.is_goalkeeper,
    player.matches_played, player.wins, player.draws, player.losses,
    player.goals, player.hdm, player.clean_sheets, player.profile_id
  from app_season_player player
  join prev_ref previous on previous.id = player.season_id
  cross join prev_has_app app
  where app.has_app
),
previous_from_import as (
  select 'previous'::text as period_key,
    history.season_name as period_label,
    history.display_rank,
    history.display_rank as display_order,
    coalesce(nullif(btrim(profile.surnom), ''), history.player_name) as player_name,
    history.is_goalkeeper,
    history.matches_played, history.wins, history.draws, history.losses,
    history.goals, history.hdm, coalesce(history.clean_sheets, 0) as clean_sheets,
    history.profile_id
  from public.historical_player_statistics history
  left join public.profiles profile on profile.id = history.profile_id
  cross join prev_has_app app
  where history.scope = 'previous' and not app.has_app
),
historical_all_time as (
  select history.player_name,
    history.profile_id,
    coalesce(nullif(btrim(profile.surnom), ''), history.player_name) as player_display,
    history.is_goalkeeper,
    history.matches_played, history.wins, history.draws, history.losses,
    history.goals, history.hdm, coalesce(history.clean_sheets, 0) as clean_sheets
  from public.historical_player_statistics history
  left join public.profiles profile on profile.id = history.profile_id
  where history.scope = 'all_time'
),
app_all as (
  select full_name, is_goalkeeper,
    max(profile_id::text)::uuid as profile_id,
    max(display_name) as display_name,
    sum(matches_played)::integer as matches_played,
    sum(wins)::integer as wins,
    sum(draws)::integer as draws,
    sum(losses)::integer as losses,
    sum(goals)::integer as goals,
    sum(hdm)::integer as hdm,
    sum(clean_sheets)::integer as clean_sheets
  from app_season_player
  group by full_name, is_goalkeeper
  having sum(matches_played) > 0
),
all_time_combined as (
  select coalesce(history.player_display, app.display_name,
                  history.player_name, app.full_name) as player_name,
    coalesce(history.profile_id, app.profile_id) as profile_id,
    coalesce(history.is_goalkeeper, app.is_goalkeeper) as is_goalkeeper,
    coalesce(history.matches_played, 0) + coalesce(app.matches_played, 0) as matches_played,
    coalesce(history.wins, 0) + coalesce(app.wins, 0) as wins,
    coalesce(history.draws, 0) + coalesce(app.draws, 0) as draws,
    coalesce(history.losses, 0) + coalesce(app.losses, 0) as losses,
    coalesce(history.goals, 0) + coalesce(app.goals, 0) as goals,
    coalesce(history.hdm, 0) + coalesce(app.hdm, 0) as hdm,
    coalesce(history.clean_sheets, 0) + coalesce(app.clean_sheets, 0) as clean_sheets
  from historical_all_time history
  full join app_all app
    on lower(btrim(history.player_name)) = lower(btrim(app.full_name))
   and history.is_goalkeeper = app.is_goalkeeper
),
all_time_ranked as (
  select 'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    rank() over (partition by is_goalkeeper
      order by matches_played desc, goals desc, player_name)::integer as display_rank,
    rank() over (partition by is_goalkeeper
      order by matches_played desc, goals desc, player_name)::integer as display_order,
    player_name, is_goalkeeper,
    matches_played, wins, draws, losses, goals, hdm, clean_sheets, profile_id
  from all_time_combined
)
select period_key, period_label, display_rank, display_order, player_name,
       is_goalkeeper, matches_played, wins, draws, losses, goals, hdm,
       clean_sheets, profile_id
from current_ranked
union all
select period_key, period_label, display_rank, display_order, player_name,
       is_goalkeeper, matches_played, wins, draws, losses, goals, hdm,
       clean_sheets, profile_id
from previous_from_app
union all
select period_key, period_label, display_rank, display_order, player_name,
       is_goalkeeper, matches_played, wins, draws, losses, goals, hdm,
       clean_sheets, profile_id
from previous_from_import
union all
select period_key, period_label, display_rank, display_order, player_name,
       is_goalkeeper, matches_played, wins, draws, losses, goals, hdm,
       clean_sheets, profile_id
from all_time_ranked;

revoke all privileges on table public.v_statistics_players from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_statistics_players from authenticated;
grant select on table public.v_statistics_players to authenticated;

commit;
