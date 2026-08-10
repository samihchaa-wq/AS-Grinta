-- Toutes saisons = historique termine + saison ouverte en temps reel.
-- Les lignes historiques sont rapprochees de l'effectif courant par nom complet.

create or replace view public.v_statistics_players
with (security_invoker = true)
as
with current_season as (
  select id, name
  from public.seasons
  where status = 'open'
  order by created_at desc
  limit 1
),
current_appearances as (
  select
    present.season_player_id,
    m.id as match_id,
    m.score_as_grinta,
    m.score_adverse
  from (
    select match_id, season_player_id from public.match_attendance
    union
    select match_id, season_player_id from public.match_player_stats
    union
    select match_id, season_player_id from public.match_man_of_match
  ) present
  join public.matches m
    on m.id = present.match_id
   and m.status in ('termine', 'archive')
  join current_season cs
    on cs.id = m.season_id
),
current_results as (
  select
    season_player_id,
    count(*)::integer as matches_played,
    count(*) filter (
      where score_as_grinta > score_adverse
    )::integer as wins,
    count(*) filter (
      where score_as_grinta = score_adverse
    )::integer as draws,
    count(*) filter (
      where score_as_grinta < score_adverse
    )::integer as losses
  from current_appearances
  group by season_player_id
),
current_player_stats as (
  select
    stats.season_player_id,
    coalesce(sum(stats.goals), 0)::integer as goals,
    count(*) filter (where stats.clean_sheet)::integer as clean_sheets
  from public.match_player_stats stats
  join public.matches m
    on m.id = stats.match_id
   and m.status in ('termine', 'archive')
  join current_season cs
    on cs.id = m.season_id
  group by stats.season_player_id
),
current_mvp as (
  select
    mvp.season_player_id,
    count(distinct mvp.match_id)::integer as hdm
  from public.match_man_of_match mvp
  join public.matches m
    on m.id = mvp.match_id
   and m.status in ('termine', 'archive')
  join current_season cs
    on cs.id = m.season_id
  group by mvp.season_player_id
),
current_base as (
  select
    cs.name as period_label,
    sp.position as display_order,
    sp.first_name as current_player_name,
    concat_ws(' ', sp.first_name, nullif(sp.last_name, '')) as full_name,
    sp.is_goalkeeper,
    coalesce(results.matches_played, 0)::integer as matches_played,
    coalesce(results.wins, 0)::integer as wins,
    coalesce(results.draws, 0)::integer as draws,
    coalesce(results.losses, 0)::integer as losses,
    coalesce(stats.goals, 0)::integer as goals,
    coalesce(mvp.hdm, 0)::integer as hdm,
    coalesce(stats.clean_sheets, 0)::integer as clean_sheets,
    case
      when sp.is_goalkeeper then coalesce(stats.clean_sheets, 0)
      else coalesce(stats.goals, 0)
    end::integer as ranking_metric
  from current_season cs
  join public.season_players sp
    on sp.season_id = cs.id
   and sp.is_active
  left join current_results results
    on results.season_player_id = sp.id
  left join current_player_stats stats
    on stats.season_player_id = sp.id
  left join current_mvp mvp
    on mvp.season_player_id = sp.id
),
current_ranked as (
  select
    'current'::text as period_key,
    period_label,
    rank() over (
      partition by is_goalkeeper
      order by ranking_metric desc
    )::integer as display_rank,
    coalesce(display_order, 9999)::integer as display_order,
    current_player_name as player_name,
    is_goalkeeper,
    matches_played,
    wins,
    draws,
    losses,
    goals,
    hdm,
    clean_sheets
  from current_base
),
previous_season as (
  select
    'previous'::text as period_key,
    season_name as period_label,
    display_rank,
    display_rank as display_order,
    player_name,
    is_goalkeeper,
    matches_played,
    wins,
    draws,
    losses,
    goals,
    hdm,
    clean_sheets
  from public.historical_player_statistics
  where scope = 'previous'
),
historical_all_time as (
  select
    player_name,
    is_goalkeeper,
    matches_played,
    wins,
    draws,
    losses,
    goals,
    hdm,
    coalesce(clean_sheets, 0)::integer as clean_sheets
  from public.historical_player_statistics
  where scope = 'all_time'
),
all_time_combined as (
  select
    coalesce(history.player_name, current.full_name) as player_name,
    coalesce(history.is_goalkeeper, current.is_goalkeeper) as is_goalkeeper,
    (coalesce(history.matches_played, 0) + coalesce(current.matches_played, 0))::integer
      as matches_played,
    (coalesce(history.wins, 0) + coalesce(current.wins, 0))::integer as wins,
    (coalesce(history.draws, 0) + coalesce(current.draws, 0))::integer as draws,
    (coalesce(history.losses, 0) + coalesce(current.losses, 0))::integer as losses,
    (coalesce(history.goals, 0) + coalesce(current.goals, 0))::integer as goals,
    (coalesce(history.hdm, 0) + coalesce(current.hdm, 0))::integer as hdm,
    (coalesce(history.clean_sheets, 0) + coalesce(current.clean_sheets, 0))::integer
      as clean_sheets
  from historical_all_time history
  full join current_base current
    on lower(btrim(history.player_name)) = lower(btrim(current.full_name))
   and history.is_goalkeeper = current.is_goalkeeper
),
all_time_ranked as (
  select
    'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    rank() over (
      partition by is_goalkeeper
      order by matches_played desc, goals desc, player_name
    )::integer as display_rank,
    rank() over (
      partition by is_goalkeeper
      order by matches_played desc, goals desc, player_name
    )::integer as display_order,
    player_name,
    is_goalkeeper,
    matches_played,
    wins,
    draws,
    losses,
    goals,
    hdm,
    clean_sheets
  from all_time_combined
)
select * from current_ranked
union all
select * from previous_season
union all
select * from all_time_ranked;

revoke all privileges on table public.v_statistics_players from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_statistics_players from authenticated;
grant select on table public.v_statistics_players to authenticated;

comment on view public.v_statistics_players is
  'Statistiques saison actuelle, saison precedente et toutes saisons incluant la saison ouverte en temps reel.';
