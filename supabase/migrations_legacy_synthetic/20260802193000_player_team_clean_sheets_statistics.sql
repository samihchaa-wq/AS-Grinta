alter table public.historical_player_statistics
  add column if not exists team_clean_sheets integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'historical_player_statistics_team_clean_sheets_check'
      and conrelid = 'public.historical_player_statistics'::regclass
  ) then
    alter table public.historical_player_statistics
      add constraint historical_player_statistics_team_clean_sheets_check
      check (team_clean_sheets >= 0);
  end if;
end
$$;

update public.historical_player_statistics h
set team_clean_sheets = v.team_clean_sheets,
    updated_at = now()
from (
  values
    ('previous', 'Milan Couzin', 6),
    ('previous', 'Allan Bamokena', 7),
    ('previous', 'Flo Arnauduc', 7),
    ('previous', 'Stéphane Fernandez', 6),
    ('previous', 'Alban Ricard', 5),
    ('previous', 'Luka Brunel', 7),
    ('previous', 'Samuel Granier', 5),
    ('previous', 'Romain Spigolon', 5),
    ('previous', 'Samih Châa', 6),
    ('previous', 'Alyoun Cherfi', 5),
    ('previous', 'Nicolas Belmonte', 5),
    ('previous', 'Julio Vignard', 4),
    ('previous', 'Amine Salhi', 5),
    ('previous', 'Julien Cesar', 4),
    ('previous', 'Aki Salabee', 3),
    ('previous', 'Olivier Millet', 3),
    ('previous', 'François De La Bourdonnaye', 3),
    ('previous', 'Hakim Cherfi', 3),
    ('previous', 'Simon Reis', 1),
    ('all_time', 'Milan Couzin', 23),
    ('all_time', 'Allan Bamokena', 7),
    ('all_time', 'Flo Arnauduc', 45),
    ('all_time', 'Stéphane Fernandez', 44),
    ('all_time', 'Alban Ricard', 5),
    ('all_time', 'Luka Brunel', 16),
    ('all_time', 'Samuel Granier', 41),
    ('all_time', 'Romain Spigolon', 36),
    ('all_time', 'Samih Châa', 20),
    ('all_time', 'Alyoun Cherfi', 7),
    ('all_time', 'Nicolas Belmonte', 5),
    ('all_time', 'Julio Vignard', 22),
    ('all_time', 'Amine Salhi', 5),
    ('all_time', 'Julien Cesar', 18),
    ('all_time', 'Aki Salabee', 3),
    ('all_time', 'Olivier Millet', 39),
    ('all_time', 'François De La Bourdonnaye', 20),
    ('all_time', 'Hakim Cherfi', 8),
    ('all_time', 'Simon Reis', 5)
) as v(scope, player_name, team_clean_sheets)
where h.scope = v.scope
  and lower(btrim(h.player_name)) = lower(btrim(v.player_name));

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
  select s.id, s.name
  from public.seasons s
  cross join open_season o
  where s.name < o.name
  order by s.name desc
  limit 1
),
app_present as (
  select present.match_id,
         present.season_player_id,
         m.season_id,
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
),
app_results as (
  select
    app_present.season_player_id,
    count(*)::integer as matches_played,
    count(*) filter (where app_present.score_as_grinta > app_present.score_adverse)::integer as wins,
    count(*) filter (where app_present.score_as_grinta = app_present.score_adverse)::integer as draws,
    count(*) filter (where app_present.score_as_grinta < app_present.score_adverse)::integer as losses,
    count(*) filter (where app_present.score_adverse = 0)::integer as team_clean_sheets
  from app_present
  group by app_present.season_player_id
),
app_pstats as (
  select
    st.season_player_id,
    coalesce(sum(st.goals), 0::bigint)::integer as goals,
    count(*) filter (where st.clean_sheet)::integer as clean_sheets
  from public.match_player_stats st
  join public.matches m
    on m.id = st.match_id
   and m.status in ('termine', 'archive')
  group by st.season_player_id
),
app_mvp as (
  select
    mvp.season_player_id,
    count(distinct mvp.match_id)::integer as hdm
  from public.match_man_of_match mvp
  join public.matches m
    on m.id = mvp.match_id
   and m.status in ('termine', 'archive')
  group by mvp.season_player_id
),
app_season_player as (
  select
    sp.season_id,
    sp.profile_id,
    sp.position as display_order,
    coalesce(nullif(btrim(pr.surnom), ''), sp.first_name) as display_name,
    concat_ws(' ', sp.first_name, nullif(sp.last_name, '')) as full_name,
    sp.is_goalkeeper,
    coalesce(r.matches_played, 0) as matches_played,
    coalesce(r.wins, 0) as wins,
    coalesce(r.draws, 0) as draws,
    coalesce(r.losses, 0) as losses,
    coalesce(g.goals, 0) as goals,
    coalesce(mv.hdm, 0) as hdm,
    coalesce(g.clean_sheets, 0) as clean_sheets,
    coalesce(r.team_clean_sheets, 0) as team_clean_sheets,
    case when sp.is_goalkeeper then coalesce(g.clean_sheets, 0) else coalesce(g.goals, 0) end as ranking_metric
  from public.season_players sp
  left join public.profiles pr on pr.id = sp.profile_id
  left join app_results r on r.season_player_id = sp.id
  left join app_pstats g on g.season_player_id = sp.id
  left join app_mvp mv on mv.season_player_id = sp.id
  where sp.is_active
),
prev_has_app as (
  select exists (
    select 1
    from app_season_player asp
    join prev_ref pr on pr.id = asp.season_id
  ) as has_app
),
current_ranked as (
  select 'current'::text as period_key, os.name as period_label,
    rank() over (partition by asp.is_goalkeeper order by asp.ranking_metric desc)::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.display_name as player_name, asp.is_goalkeeper, asp.matches_played,
    asp.wins, asp.draws, asp.losses, asp.goals, asp.hdm, asp.clean_sheets,
    asp.profile_id, asp.team_clean_sheets
  from app_season_player asp
  join open_season os on os.id = asp.season_id
),
previous_from_app as (
  select 'previous'::text as period_key, pr.name as period_label,
    rank() over (partition by asp.is_goalkeeper order by asp.ranking_metric desc)::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.display_name as player_name, asp.is_goalkeeper, asp.matches_played,
    asp.wins, asp.draws, asp.losses, asp.goals, asp.hdm, asp.clean_sheets,
    asp.profile_id, asp.team_clean_sheets
  from app_season_player asp
  join prev_ref pr on pr.id = asp.season_id
  cross join prev_has_app ph
  where ph.has_app
),
previous_from_import as (
  select 'previous'::text as period_key, h.season_name as period_label,
    h.display_rank, h.display_rank as display_order,
    coalesce(nullif(btrim(pr.surnom), ''), h.player_name) as player_name,
    h.is_goalkeeper, h.matches_played, h.wins, h.draws, h.losses,
    h.goals, h.hdm, coalesce(h.clean_sheets, 0) as clean_sheets,
    h.profile_id, coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  left join public.profiles pr on pr.id = h.profile_id
  cross join prev_has_app ph
  where h.scope = 'previous' and not ph.has_app
),
historical_all_time as (
  select h.player_name, h.profile_id,
    coalesce(nullif(btrim(pr.surnom), ''), h.player_name) as player_display,
    h.is_goalkeeper, h.matches_played, h.wins, h.draws, h.losses,
    h.goals, h.hdm, coalesce(h.clean_sheets, 0) as clean_sheets,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  left join public.profiles pr on pr.id = h.profile_id
  where h.scope = 'all_time'
),
app_all as (
  select app_season_player.full_name, app_season_player.is_goalkeeper,
    max(app_season_player.profile_id::text)::uuid as profile_id,
    max(app_season_player.display_name) as display_name,
    sum(app_season_player.matches_played)::integer as matches_played,
    sum(app_season_player.wins)::integer as wins,
    sum(app_season_player.draws)::integer as draws,
    sum(app_season_player.losses)::integer as losses,
    sum(app_season_player.goals)::integer as goals,
    sum(app_season_player.hdm)::integer as hdm,
    sum(app_season_player.clean_sheets)::integer as clean_sheets,
    sum(app_season_player.team_clean_sheets)::integer as team_clean_sheets
  from app_season_player
  group by app_season_player.full_name, app_season_player.is_goalkeeper
  having sum(app_season_player.matches_played) > 0
),
all_time_combined as (
  select coalesce(history.player_display, app.display_name, history.player_name, app.full_name) as player_name,
    coalesce(history.profile_id, app.profile_id) as profile_id,
    coalesce(history.is_goalkeeper, app.is_goalkeeper) as is_goalkeeper,
    coalesce(history.matches_played, 0) + coalesce(app.matches_played, 0) as matches_played,
    coalesce(history.wins, 0) + coalesce(app.wins, 0) as wins,
    coalesce(history.draws, 0) + coalesce(app.draws, 0) as draws,
    coalesce(history.losses, 0) + coalesce(app.losses, 0) as losses,
    coalesce(history.goals, 0) + coalesce(app.goals, 0) as goals,
    coalesce(history.hdm, 0) + coalesce(app.hdm, 0) as hdm,
    coalesce(history.clean_sheets, 0) + coalesce(app.clean_sheets, 0) as clean_sheets,
    coalesce(history.team_clean_sheets, 0) + coalesce(app.team_clean_sheets, 0) as team_clean_sheets
  from historical_all_time history
  full join app_all app
    on lower(btrim(history.player_name)) = lower(btrim(app.full_name))
   and history.is_goalkeeper = app.is_goalkeeper
),
all_time_ranked as (
  select 'all_time'::text as period_key, 'Toutes saisons'::text as period_label,
    rank() over (partition by all_time_combined.is_goalkeeper order by all_time_combined.matches_played desc, all_time_combined.goals desc, all_time_combined.player_name)::integer as display_rank,
    rank() over (partition by all_time_combined.is_goalkeeper order by all_time_combined.matches_played desc, all_time_combined.goals desc, all_time_combined.player_name)::integer as display_order,
    all_time_combined.player_name, all_time_combined.is_goalkeeper,
    all_time_combined.matches_played, all_time_combined.wins,
    all_time_combined.draws, all_time_combined.losses,
    all_time_combined.goals, all_time_combined.hdm,
    all_time_combined.clean_sheets, all_time_combined.profile_id,
    all_time_combined.team_clean_sheets
  from all_time_combined
)
select current_ranked.period_key, current_ranked.period_label, current_ranked.display_rank,
  current_ranked.display_order, current_ranked.player_name, current_ranked.is_goalkeeper,
  current_ranked.matches_played, current_ranked.wins, current_ranked.draws,
  current_ranked.losses, current_ranked.goals, current_ranked.hdm,
  current_ranked.clean_sheets, current_ranked.profile_id, current_ranked.team_clean_sheets
from current_ranked
union all
select previous_from_app.period_key, previous_from_app.period_label, previous_from_app.display_rank,
  previous_from_app.display_order, previous_from_app.player_name, previous_from_app.is_goalkeeper,
  previous_from_app.matches_played, previous_from_app.wins, previous_from_app.draws,
  previous_from_app.losses, previous_from_app.goals, previous_from_app.hdm,
  previous_from_app.clean_sheets, previous_from_app.profile_id, previous_from_app.team_clean_sheets
from previous_from_app
union all
select previous_from_import.period_key, previous_from_import.period_label, previous_from_import.display_rank,
  previous_from_import.display_order, previous_from_import.player_name, previous_from_import.is_goalkeeper,
  previous_from_import.matches_played, previous_from_import.wins, previous_from_import.draws,
  previous_from_import.losses, previous_from_import.goals, previous_from_import.hdm,
  previous_from_import.clean_sheets, previous_from_import.profile_id, previous_from_import.team_clean_sheets
from previous_from_import
union all
select all_time_ranked.period_key, all_time_ranked.period_label, all_time_ranked.display_rank,
  all_time_ranked.display_order, all_time_ranked.player_name, all_time_ranked.is_goalkeeper,
  all_time_ranked.matches_played, all_time_ranked.wins, all_time_ranked.draws,
  all_time_ranked.losses, all_time_ranked.goals, all_time_ranked.hdm,
  all_time_ranked.clean_sheets, all_time_ranked.profile_id, all_time_ranked.team_clean_sheets
from all_time_ranked;

comment on column public.historical_player_statistics.team_clean_sheets is
  'Matchs sans but encaissé auxquels le joueur a participé, tous postes confondus.';

comment on view public.v_statistics_players is
  'Statistiques joueurs Actuelle/Précédente/Toutes. team_clean_sheets compte les matchs joués avec score_adverse = 0, indépendamment du clean sheet gardien.';