-- « Saison précédente » et « Toutes saisons » deviennent DYNAMIQUES : elles
-- basculent toutes seules à chaque clôture de saison (ouverture d'une nouvelle).
--
--  • Saison actuelle  : la saison au statut « open » (données app).
--  • Saison précédente: la saison juste avant l'ouverte (par nom, chronologique).
--                       Calculée depuis les matchs de l'app si cette saison en a,
--                       sinon repli sur l'import historique (scope = 'previous',
--                       cas de 2025-2026 tant qu'aucune saison n'a été jouée dans
--                       l'app).
--  • Toutes saisons   : import figé (pré-app) + TOUTES les saisons jouées dans
--                       l'app (une saison clôturée reste donc comptée).
create or replace view public.v_statistics_players as
with open_season as (
  select id, name from public.seasons
  where status = 'open' order by created_at desc limit 1
),
prev_ref as (
  -- Saison immédiatement avant l'ouverte (les noms « YYYY-YYYY » se trient
  -- chronologiquement).
  select s.id, s.name
  from public.seasons s
  cross join open_season o
  where s.name < o.name
  order by s.name desc
  limit 1
),
app_present as (
  select present.match_id, present.season_player_id, m.season_id,
         m.score_as_grinta, m.score_adverse
  from (
    select match_id, season_player_id from public.match_attendance
    union
    select match_id, season_player_id from public.match_player_stats
    union
    select match_id, season_player_id from public.match_man_of_match
  ) present
  join public.matches m on m.id = present.match_id
    and m.status = any (array['termine'::text, 'archive'::text])
),
app_results as (
  select season_player_id,
    count(*)::int as matches_played,
    count(*) filter (where score_as_grinta > score_adverse)::int as wins,
    count(*) filter (where score_as_grinta = score_adverse)::int as draws,
    count(*) filter (where score_as_grinta < score_adverse)::int as losses
  from app_present group by season_player_id
),
app_pstats as (
  select st.season_player_id,
    coalesce(sum(st.goals), 0)::int as goals,
    count(*) filter (where st.clean_sheet)::int as clean_sheets
  from public.match_player_stats st
  join public.matches m on m.id = st.match_id
    and m.status = any (array['termine'::text, 'archive'::text])
  group by st.season_player_id
),
app_mvp as (
  select mvp.season_player_id,
    count(distinct mvp.match_id)::int as hdm
  from public.match_man_of_match mvp
  join public.matches m on m.id = mvp.match_id
    and m.status = any (array['termine'::text, 'archive'::text])
  group by mvp.season_player_id
),
-- Une ligne par (saison, joueur) à partir des données de l'app (effectif
-- complet, y compris les joueurs à 0 match).
app_season_player as (
  select sp.season_id,
    sp."position" as display_order,
    sp.first_name as current_player_name,
    concat_ws(' '::text, sp.first_name, nullif(sp.last_name, ''::text)) as full_name,
    sp.is_goalkeeper,
    coalesce(r.matches_played, 0) as matches_played,
    coalesce(r.wins, 0) as wins,
    coalesce(r.draws, 0) as draws,
    coalesce(r.losses, 0) as losses,
    coalesce(g.goals, 0) as goals,
    coalesce(mv.hdm, 0) as hdm,
    coalesce(g.clean_sheets, 0) as clean_sheets,
    case when sp.is_goalkeeper then coalesce(g.clean_sheets, 0)
         else coalesce(g.goals, 0) end as ranking_metric
  from public.season_players sp
  left join app_results r on r.season_player_id = sp.id
  left join app_pstats g on g.season_player_id = sp.id
  left join app_mvp mv on mv.season_player_id = sp.id
  where sp.is_active
),
prev_has_app as (
  -- La saison précédente a-t-elle de vraies stats joueur saisies dans l'app ?
  select exists (
    select 1 from public.match_player_stats st
    join public.matches m on m.id = st.match_id
      and m.status = any (array['termine'::text, 'archive'::text])
    join prev_ref pr on pr.id = m.season_id
  ) as has_app
),
current_ranked as (
  select 'current'::text as period_key,
    os.name as period_label,
    rank() over (partition by asp.is_goalkeeper order by asp.ranking_metric desc)::int as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.current_player_name as player_name,
    asp.is_goalkeeper, asp.matches_played, asp.wins, asp.draws, asp.losses,
    asp.goals, asp.hdm, asp.clean_sheets
  from app_season_player asp
  join open_season os on os.id = asp.season_id
),
previous_from_app as (
  select 'previous'::text as period_key,
    pr.name as period_label,
    rank() over (partition by asp.is_goalkeeper order by asp.ranking_metric desc)::int as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper, asp.matches_played, asp.wins, asp.draws, asp.losses,
    asp.goals, asp.hdm, asp.clean_sheets
  from app_season_player asp
  join prev_ref pr on pr.id = asp.season_id
  cross join prev_has_app ph
  where ph.has_app
),
previous_from_import as (
  select 'previous'::text as period_key,
    h.season_name as period_label,
    h.display_rank,
    h.display_rank as display_order,
    h.player_name, h.is_goalkeeper,
    h.matches_played, h.wins, h.draws, h.losses, h.goals, h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets
  from public.historical_player_statistics h
  cross join prev_has_app ph
  where h.scope = 'previous'::text and not ph.has_app
),
historical_all_time as (
  select player_name, is_goalkeeper, matches_played, wins, draws, losses, goals, hdm,
    coalesce(clean_sheets, 0) as clean_sheets
  from public.historical_player_statistics where scope = 'all_time'::text
),
-- Totaux app toutes saisons confondues (seulement les joueurs ayant réellement
-- joué dans l'app), à additionner à l'import figé.
app_all as (
  select full_name, is_goalkeeper,
    sum(matches_played)::int as matches_played,
    sum(wins)::int as wins,
    sum(draws)::int as draws,
    sum(losses)::int as losses,
    sum(goals)::int as goals,
    sum(hdm)::int as hdm,
    sum(clean_sheets)::int as clean_sheets
  from app_season_player
  group by full_name, is_goalkeeper
  having sum(matches_played) > 0
),
all_time_combined as (
  select coalesce(history.player_name, app.full_name) as player_name,
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
    rank() over (partition by is_goalkeeper order by matches_played desc, goals desc, player_name)::int as display_rank,
    rank() over (partition by is_goalkeeper order by matches_played desc, goals desc, player_name)::int as display_order,
    player_name, is_goalkeeper, matches_played, wins, draws, losses, goals, hdm, clean_sheets
  from all_time_combined
)
select period_key, period_label, display_rank, display_order, player_name, is_goalkeeper,
       matches_played, wins, draws, losses, goals, hdm, clean_sheets from current_ranked
union all
select period_key, period_label, display_rank, display_order, player_name, is_goalkeeper,
       matches_played, wins, draws, losses, goals, hdm, clean_sheets from previous_from_app
union all
select period_key, period_label, display_rank, display_order, player_name, is_goalkeeper,
       matches_played, wins, draws, losses, goals, hdm, clean_sheets from previous_from_import
union all
select period_key, period_label, display_rank, display_order, player_name, is_goalkeeper,
       matches_played, wins, draws, losses, goals, hdm, clean_sheets from all_time_ranked;
