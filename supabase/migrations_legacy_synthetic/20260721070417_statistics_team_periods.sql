-- Statistiques collectives dynamiques, avec le même roulement que les
-- statistiques joueurs :
--   • Actuelle   = saison ouverte ;
--   • Précédente = saison immédiatement antérieure ;
--   • Toutes     = somme de tous les matchs terminés ou archivés.
--
-- Lorsqu'une nouvelle saison est ouverte, l'ancienne saison actuelle devient
-- automatiquement la précédente et la nouvelle saison repart à zéro.
create or replace view public.v_statistics_team
with (security_invoker = true)
as
with open_season as (
  select id, name
  from public.seasons
  where status = 'open'
  order by created_at desc
  limit 1
),
previous_season as (
  select s.id, s.name
  from public.seasons s
  cross join open_season current
  where s.name < current.name
  order by s.name desc
  limit 1
),
scored_matches as (
  select
    m.season_id,
    m.score_as_grinta as goals_for,
    m.score_adverse as goals_against
  from public.matches m
  where m.status = any (array['termine'::text, 'archive'::text])
    and m.score_as_grinta is not null
    and m.score_adverse is not null
),
season_totals as (
  select
    s.id as season_id,
    s.name as season_name,
    count(m.season_id)::int as matches_played,
    count(*) filter (where m.goals_for > m.goals_against)::int as wins,
    count(*) filter (where m.goals_for = m.goals_against)::int as draws,
    count(*) filter (where m.goals_for < m.goals_against)::int as losses,
    coalesce(sum(m.goals_for), 0)::int as goals_for,
    coalesce(sum(m.goals_against), 0)::int as goals_against,
    count(*) filter (where m.goals_against = 0)::int as clean_sheets
  from public.seasons s
  left join scored_matches m on m.season_id = s.id
  group by s.id, s.name
),
current_period as (
  select
    'current'::text as period_key,
    current.name as period_label,
    totals.matches_played,
    totals.wins,
    totals.draws,
    totals.losses,
    totals.goals_for,
    totals.goals_against,
    totals.clean_sheets
  from open_season current
  join season_totals totals on totals.season_id = current.id
),
previous_period as (
  select
    'previous'::text as period_key,
    previous.name as period_label,
    totals.matches_played,
    totals.wins,
    totals.draws,
    totals.losses,
    totals.goals_for,
    totals.goals_against,
    totals.clean_sheets
  from previous_season previous
  join season_totals totals on totals.season_id = previous.id
),
all_time_period as (
  select
    'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    coalesce(sum(matches_played), 0)::int as matches_played,
    coalesce(sum(wins), 0)::int as wins,
    coalesce(sum(draws), 0)::int as draws,
    coalesce(sum(losses), 0)::int as losses,
    coalesce(sum(goals_for), 0)::int as goals_for,
    coalesce(sum(goals_against), 0)::int as goals_against,
    coalesce(sum(clean_sheets), 0)::int as clean_sheets
  from season_totals
)
select
  period_key,
  period_label,
  matches_played,
  wins,
  draws,
  losses,
  goals_for,
  goals_against,
  goals_for - goals_against as goal_difference,
  clean_sheets
from current_period
union all
select
  period_key,
  period_label,
  matches_played,
  wins,
  draws,
  losses,
  goals_for,
  goals_against,
  goals_for - goals_against,
  clean_sheets
from previous_period
union all
select
  period_key,
  period_label,
  matches_played,
  wins,
  draws,
  losses,
  goals_for,
  goals_against,
  goals_for - goals_against,
  clean_sheets
from all_time_period;

revoke all on public.v_statistics_team from public, anon;
grant select on public.v_statistics_team to authenticated;
