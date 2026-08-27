begin;

-- Passes décisives : classement joueurs et badges automatiques.
--
-- Les saisons importées (historical_player_statistics) ne portent aucune passe
-- décisive : elles comptent zéro et ne sont jamais reconstituées.

-- ---------------------------------------------------------------------------
-- 1. Classement joueurs
-- ---------------------------------------------------------------------------

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
    coalesce(sum(st.assists), 0::bigint)::integer as assists,
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
    concat_ws(' ', sp.first_name, nullif(sp.last_name, '')) as full_name,
    sp.is_goalkeeper,
    sp.is_active,
    coalesce(r.matches_played, 0) as matches_played,
    coalesce(r.wins, 0) as wins,
    coalesce(r.draws, 0) as draws,
    coalesce(r.losses, 0) as losses,
    coalesce(g.goals, 0) as goals,
    coalesce(g.assists, 0) as assists,
    coalesce(mv.hdm, 0) as hdm,
    coalesce(g.clean_sheets, 0) as clean_sheets,
    coalesce(r.team_clean_sheets, 0) as team_clean_sheets,
    case
      when sp.is_goalkeeper then coalesce(g.clean_sheets, 0)
      else coalesce(g.goals, 0)
    end as ranking_metric
  from public.season_players sp
  left join app_results r on r.season_player_id = sp.id
  left join app_pstats g on g.season_player_id = sp.id
  left join app_mvp mv on mv.season_player_id = sp.id
),
prev_has_app as (
  select exists (
    select 1
    from app_season_player asp
    join prev_ref pr on pr.id = asp.season_id
  ) as has_app
),
current_ranked as (
  select
    'current'::text as period_key,
    os.name as period_label,
    rank() over (
      partition by asp.is_goalkeeper
      order by asp.ranking_metric desc
    )::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper,
    asp.matches_played,
    asp.wins,
    asp.draws,
    asp.losses,
    asp.goals,
    asp.assists,
    asp.hdm,
    asp.clean_sheets,
    asp.profile_id,
    asp.team_clean_sheets
  from app_season_player asp
  join open_season os on os.id = asp.season_id
  where asp.is_active
),
previous_from_app as (
  select
    'previous'::text as period_key,
    pr.name as period_label,
    rank() over (
      partition by asp.is_goalkeeper
      order by asp.ranking_metric desc
    )::integer as display_rank,
    coalesce(asp.display_order, 9999) as display_order,
    asp.full_name as player_name,
    asp.is_goalkeeper,
    asp.matches_played,
    asp.wins,
    asp.draws,
    asp.losses,
    asp.goals,
    asp.assists,
    asp.hdm,
    asp.clean_sheets,
    asp.profile_id,
    asp.team_clean_sheets
  from app_season_player asp
  join prev_ref pr on pr.id = asp.season_id
  cross join prev_has_app ph
  where ph.has_app
),
previous_from_import as (
  select
    'previous'::text as period_key,
    h.season_name as period_label,
    h.display_rank,
    h.display_rank as display_order,
    h.player_name,
    h.is_goalkeeper,
    h.matches_played,
    h.wins,
    h.draws,
    h.losses,
    h.goals,
    0 as assists,
    h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets,
    h.profile_id,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  cross join prev_has_app ph
  where h.scope = 'previous'
    and not ph.has_app
),
historical_all_time as (
  select
    h.player_name,
    h.profile_id,
    h.is_goalkeeper,
    h.matches_played,
    h.wins,
    h.draws,
    h.losses,
    h.goals,
    h.hdm,
    coalesce(h.clean_sheets, 0) as clean_sheets,
    coalesce(h.team_clean_sheets, 0) as team_clean_sheets
  from public.historical_player_statistics h
  where h.scope = 'all_time'
),
app_all as (
  select
    app_season_player.full_name,
    app_season_player.is_goalkeeper,
    max(app_season_player.profile_id::text)::uuid as profile_id,
    sum(app_season_player.matches_played)::integer as matches_played,
    sum(app_season_player.wins)::integer as wins,
    sum(app_season_player.draws)::integer as draws,
    sum(app_season_player.losses)::integer as losses,
    sum(app_season_player.goals)::integer as goals,
    sum(app_season_player.assists)::integer as assists,
    sum(app_season_player.hdm)::integer as hdm,
    sum(app_season_player.clean_sheets)::integer as clean_sheets,
    sum(app_season_player.team_clean_sheets)::integer as team_clean_sheets
  from app_season_player
  group by app_season_player.full_name, app_season_player.is_goalkeeper
  having sum(app_season_player.matches_played) > 0
),
all_time_combined as (
  select
    coalesce(history.player_name, app.full_name) as player_name,
    coalesce(history.profile_id, app.profile_id) as profile_id,
    coalesce(history.is_goalkeeper, app.is_goalkeeper) as is_goalkeeper,
    coalesce(history.matches_played, 0) + coalesce(app.matches_played, 0) as matches_played,
    coalesce(history.wins, 0) + coalesce(app.wins, 0) as wins,
    coalesce(history.draws, 0) + coalesce(app.draws, 0) as draws,
    coalesce(history.losses, 0) + coalesce(app.losses, 0) as losses,
    coalesce(history.goals, 0) + coalesce(app.goals, 0) as goals,
    coalesce(app.assists, 0) as assists,
    coalesce(history.hdm, 0) + coalesce(app.hdm, 0) as hdm,
    coalesce(history.clean_sheets, 0) + coalesce(app.clean_sheets, 0) as clean_sheets,
    coalesce(history.team_clean_sheets, 0) + coalesce(app.team_clean_sheets, 0) as team_clean_sheets
  from historical_all_time history
  full join app_all app
    on lower(btrim(history.player_name)) = lower(btrim(app.full_name))
   and history.is_goalkeeper = app.is_goalkeeper
),
all_time_ranked as (
  select
    'all_time'::text as period_key,
    'Toutes saisons'::text as period_label,
    rank() over (
      partition by all_time_combined.is_goalkeeper
      order by all_time_combined.matches_played desc,
               all_time_combined.goals desc,
               all_time_combined.player_name
    )::integer as display_rank,
    rank() over (
      partition by all_time_combined.is_goalkeeper
      order by all_time_combined.matches_played desc,
               all_time_combined.goals desc,
               all_time_combined.player_name
    )::integer as display_order,
    all_time_combined.player_name,
    all_time_combined.is_goalkeeper,
    all_time_combined.matches_played,
    all_time_combined.wins,
    all_time_combined.draws,
    all_time_combined.losses,
    all_time_combined.goals,
    all_time_combined.assists,
    all_time_combined.hdm,
    all_time_combined.clean_sheets,
    all_time_combined.profile_id,
    all_time_combined.team_clean_sheets
  from all_time_combined
)
select
  current_ranked.period_key,
  current_ranked.period_label,
  current_ranked.display_rank,
  current_ranked.display_order,
  current_ranked.player_name,
  current_ranked.is_goalkeeper,
  current_ranked.matches_played,
  current_ranked.wins,
  current_ranked.draws,
  current_ranked.losses,
  current_ranked.goals,
  current_ranked.hdm,
  current_ranked.clean_sheets,
  current_ranked.profile_id,
  current_ranked.team_clean_sheets,
  current_ranked.assists
from current_ranked
union all
select
  previous_from_app.period_key,
  previous_from_app.period_label,
  previous_from_app.display_rank,
  previous_from_app.display_order,
  previous_from_app.player_name,
  previous_from_app.is_goalkeeper,
  previous_from_app.matches_played,
  previous_from_app.wins,
  previous_from_app.draws,
  previous_from_app.losses,
  previous_from_app.goals,
  previous_from_app.hdm,
  previous_from_app.clean_sheets,
  previous_from_app.profile_id,
  previous_from_app.team_clean_sheets,
  previous_from_app.assists
from previous_from_app
union all
select
  previous_from_import.period_key,
  previous_from_import.period_label,
  previous_from_import.display_rank,
  previous_from_import.display_order,
  previous_from_import.player_name,
  previous_from_import.is_goalkeeper,
  previous_from_import.matches_played,
  previous_from_import.wins,
  previous_from_import.draws,
  previous_from_import.losses,
  previous_from_import.goals,
  previous_from_import.hdm,
  previous_from_import.clean_sheets,
  previous_from_import.profile_id,
  previous_from_import.team_clean_sheets,
  previous_from_import.assists
from previous_from_import
union all
select
  all_time_ranked.period_key,
  all_time_ranked.period_label,
  all_time_ranked.display_rank,
  all_time_ranked.display_order,
  all_time_ranked.player_name,
  all_time_ranked.is_goalkeeper,
  all_time_ranked.matches_played,
  all_time_ranked.wins,
  all_time_ranked.draws,
  all_time_ranked.losses,
  all_time_ranked.goals,
  all_time_ranked.hdm,
  all_time_ranked.clean_sheets,
  all_time_ranked.profile_id,
  all_time_ranked.team_clean_sheets,
  all_time_ranked.assists
from all_time_ranked;

comment on view public.v_statistics_players is
  'Statistiques joueurs Actuelle/Précédente/Toutes : la saison courante masque les effectifs inactifs, les périodes historiques conservent toute adhésion ayant participé à un match ; les joueurs sont nommés par leur vrai nom, team_clean_sheets compte les matchs joués avec score_adverse = 0 et assists ne couvre que les saisons suivies dans l''application.';

-- ---------------------------------------------------------------------------
-- 2. Métriques de badges : passes décisives saison, carrière et record de match
-- ---------------------------------------------------------------------------

drop function if exists public.profile_badge_metrics(uuid);
drop function if exists private.profile_badge_metrics(uuid);

create function private.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer,
  wins_season integer,
  goals_season integer,
  clean_sheets_season integer,
  matches_played integer,
  wins integer,
  goals integer,
  doubles integer,
  max_match_goals integer,
  mvp integer,
  clean_sheets integer,
  pred_good_result integer,
  pred_exact_score integer,
  bet_against_grinta integer,
  perfect_own_goals_prediction integer,
  seasons_complete integer,
  title_most_present integer,
  title_top_scorer integer,
  title_mvp_king integer,
  title_best_winrate integer,
  title_best_pred_player integer,
  title_best_pred_match integer,
  title_best_pred_overall integer,
  assists_season integer,
  assists integer,
  max_match_assists integer
)
language sql
security definer
set search_path to ''
as $function$
  with pm as (
    select
      m.season_id,
      (m.score_as_grinta > m.score_adverse) as win,
      coalesce(st.goals, 0) as g,
      coalesce(st.assists, 0) as a,
      (m.score_adverse = 0) as cs,
      (mv.season_player_id is not null) as is_mvp
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
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id
     and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (
        st.match_id is not null
        or att.match_id is not null
        or mv.match_id is not null
      )
  ),
  ps as (
    select
      season_id,
      count(*) as mp,
      count(*) filter (where win) as w,
      sum(g) as gg,
      sum(a) as aa,
      count(*) filter (where cs) as csn,
      count(*) filter (where is_mvp) as mvpn,
      count(*) filter (where g = 2) as dbl
    from pm
    group by season_id
  ),
  player as (
    select
      coalesce(max(ps.mp) filter (where s.status = 'open'), 0)::int as matches_played_season,
      coalesce(max(ps.w) filter (where s.status = 'open'), 0)::int as wins_season,
      coalesce(max(ps.gg) filter (where s.status = 'open'), 0)::int as goals_season,
      coalesce(max(ps.aa) filter (where s.status = 'open'), 0)::int as assists_season,
      coalesce(max(ps.csn) filter (where s.status = 'open'), 0)::int as clean_sheets_season,
      coalesce(sum(ps.mp), 0)::int as matches_played,
      coalesce(sum(ps.w), 0)::int as wins,
      coalesce(sum(ps.gg), 0)::int as goals,
      coalesce(sum(ps.aa), 0)::int as assists,
      coalesce(sum(ps.dbl), 0)::int as doubles,
      coalesce(sum(ps.mvpn), 0)::int as mvp,
      coalesce(sum(ps.csn), 0)::int as clean_sheets
    from ps
    left join public.seasons s on s.id = ps.season_id
  ),
  hist as (
    select
      coalesce(sum(h.matches_played), 0)::int as h_mp,
      coalesce(sum(h.wins), 0)::int as h_w,
      coalesce(sum(h.goals), 0)::int as h_g,
      coalesce(sum(h.team_clean_sheets), 0)::int as h_cs,
      coalesce(sum(h.hdm), 0)::int as h_mvp
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and (
        h.profile_id = p_profile_id
        or (
          h.profile_id is null
          and lower(btrim(h.player_name)) in (
            select distinct lower(
              btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, '')))
            )
            from public.season_players sp
            where sp.profile_id = p_profile_id
              and coalesce(btrim(sp.first_name), '') <> ''
          )
        )
      )
  ),
  pmax as (
    select
      coalesce(max(g), 0)::int as max_match_goals,
      coalesce(max(a), 0)::int as max_match_assists
    from pm
  ),
  mpred as (
    select
      (
        mp.is_filled
        and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
          = sign((m.score_as_grinta - m.score_adverse)::numeric)
      )::int as bon,
      (
        mp.is_filled
        and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse
      )::int as ex,
      (
        mp.is_filled
        and mp.predicted_score_as_grinta < mp.predicted_score_adverse
      )::int as against
    from public.match_predictions mp
    join public.matches m
      on m.id = mp.match_id
     and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ),
  mpred_a as (
    select
      coalesce(sum(bon), 0)::int as pred_good_result,
      coalesce(sum(ex), 0)::int as pred_exact_score,
      coalesce(sum(against), 0)::int as bet_against_grinta
    from mpred
  ),
  own_goal_pred as (
    select coalesce(count(*), 0)::int as perfect_own_goals_prediction
    from public.season_predictions sp
    join public.season_players spl
      on spl.id = sp.season_player_id
    join public.seasons se
      on se.id = sp.season_id
     and se.status = 'archived'
    join lateral (
      select coalesce(sum(s.goals), 0)::int as g
      from public.match_player_stats s
      join public.matches m
        on m.id = s.match_id
       and m.season_id = sp.season_id
       and m.status in ('termine', 'archive')
      where s.season_player_id = sp.season_player_id
    ) tot on true
    where sp.predictor_profile_id = p_profile_id
      and spl.profile_id = p_profile_id
      and sp.category = 'buts'
      and sp.is_filled
      and sp.predicted_value_30 >= 1
      and sp.predicted_value_30 = tot.g
  ),
  aw as (
    select
      count(*) filter (where award_type = 'season_complete')::int as seasons_complete,
      count(*) filter (where award_type = 'most_present')::int as title_most_present,
      count(*) filter (where award_type = 'top_scorer')::int as title_top_scorer,
      count(*) filter (where award_type = 'mvp_king')::int as title_mvp_king,
      count(*) filter (where award_type = 'best_winrate')::int as title_best_winrate,
      count(*) filter (where award_type = 'best_pred_player')::int as title_best_pred_player,
      count(*) filter (where award_type = 'best_pred_match')::int as title_best_pred_match,
      count(*) filter (where award_type = 'best_pred_overall')::int as title_best_pred_overall
    from public.season_awards
    where profile_id = p_profile_id
  )
  select
    player.matches_played_season,
    player.wins_season,
    player.goals_season,
    player.clean_sheets_season,
    (player.matches_played + hist.h_mp)::int as matches_played,
    (player.wins + hist.h_w)::int as wins,
    (player.goals + hist.h_g)::int as goals,
    player.doubles,
    pmax.max_match_goals,
    (player.mvp + hist.h_mvp)::int as mvp,
    (player.clean_sheets + hist.h_cs)::int as clean_sheets,
    mpred_a.pred_good_result,
    mpred_a.pred_exact_score,
    mpred_a.bet_against_grinta,
    own_goal_pred.perfect_own_goals_prediction,
    aw.seasons_complete,
    aw.title_most_present,
    aw.title_top_scorer,
    aw.title_mvp_king,
    aw.title_best_winrate,
    aw.title_best_pred_player,
    aw.title_best_pred_match,
    aw.title_best_pred_overall,
    player.assists_season,
    player.assists,
    pmax.max_match_assists
  from player, hist, pmax, mpred_a, own_goal_pred, aw;
$function$;

alter function private.profile_badge_metrics(uuid) owner to postgres;
revoke all on function private.profile_badge_metrics(uuid) from public;
grant execute on function private.profile_badge_metrics(uuid) to authenticated, service_role;

create function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer,
  wins_season integer,
  goals_season integer,
  clean_sheets_season integer,
  matches_played integer,
  wins integer,
  goals integer,
  doubles integer,
  max_match_goals integer,
  mvp integer,
  clean_sheets integer,
  pred_good_result integer,
  pred_exact_score integer,
  bet_against_grinta integer,
  perfect_own_goals_prediction integer,
  seasons_complete integer,
  title_most_present integer,
  title_top_scorer integer,
  title_mvp_king integer,
  title_best_winrate integer,
  title_best_pred_player integer,
  title_best_pred_match integer,
  title_best_pred_overall integer,
  assists_season integer,
  assists integer,
  max_match_assists integer
)
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_profile_id is null then
    return;
  end if;

  if p_profile_id is distinct from (select auth.uid())
     and not public.is_match_staff() then
    raise exception 'Forbidden' using errcode = '42501';
  end if;

  return query select * from private.profile_badge_metrics(p_profile_id);
end;
$function$;

alter function public.profile_badge_metrics(uuid) owner to postgres;
revoke all on function public.profile_badge_metrics(uuid) from public;
grant execute on function public.profile_badge_metrics(uuid) to authenticated, service_role;

create or replace function public.profile_badge_display_metrics(p_profile_id uuid)
returns table(metric text, current_value integer, display_value integer)
language sql
stable
set search_path to ''
as $function$
  with raw_metrics as (
    select to_jsonb(m) as metrics
    from private.profile_badge_metrics(p_profile_id) m
  ),
  tracked_matches as (
    select
      m.season_id,
      (m.score_as_grinta > m.score_adverse) as win,
      coalesce(st.goals, 0) as goals,
      coalesce(st.assists, 0) as assists,
      (m.score_adverse = 0) as clean_sheet
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
      and (
        st.match_id is not null
        or att.match_id is not null
        or motm.match_id is not null
      )
  ),
  tracked_seasons as (
    select
      season_id,
      count(*)::int as matches_played,
      count(*) filter (where win)::int as wins,
      coalesce(sum(goals), 0)::int as goals,
      coalesce(sum(assists), 0)::int as assists,
      count(*) filter (where clean_sheet)::int as clean_sheets
    from tracked_matches
    group by season_id
  ),
  season_best as (
    select
      coalesce(max(matches_played), 0)::int as matches_played_season,
      coalesce(max(wins), 0)::int as wins_season,
      coalesce(max(goals), 0)::int as goals_season,
      coalesce(max(assists), 0)::int as assists_season,
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
      when 'assists_season' then sb.assists_season
      when 'clean_sheets_season' then sb.clean_sheets_season
      else coalesce((rm.metrics ->> bm.metric)::int, 0)
    end as display_value
  from badge_metrics bm
  cross join raw_metrics rm
  cross join season_best sb;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Badges passes décisives
-- ---------------------------------------------------------------------------

insert into public.badges(
  code, name, description, emoji, family, auto, metric, threshold,
  sort_order, kind, category, color, has_star, standalone, secret
) values
  ('assists_season__3', 'Première passe',
   'Délivrer 3 passes décisives au cours d’une même saison.',
   '🎯', 'joueur', true, 'assists_season', 3, 140, 'tier', 'joueur_saison',
   '#7A858D', false, false, false),
  ('assists_season__5', 'Passeur',
   'Délivrer 5 passes décisives au cours d’une même saison.',
   '🎯', 'joueur', true, 'assists_season', 5, 141, 'tier', 'joueur_saison',
   '#CD7F32', false, false, false),
  ('assists_season__10', 'Créateur',
   'Délivrer 10 passes décisives au cours d’une même saison.',
   '🎯', 'joueur', true, 'assists_season', 10, 142, 'tier', 'joueur_saison',
   '#C0C0C0', false, false, false),
  ('assists_season__15', 'Chef d’orchestre',
   'Délivrer 15 passes décisives au cours d’une même saison.',
   '🎯', 'joueur', true, 'assists_season', 15, 143, 'tier', 'joueur_saison',
   '#D4AF37', true, false, false),
  ('assists__10', 'Faiseur de jeu',
   'Atteindre 10 passes décisives avec le club.',
   '🎯', 'joueur', true, 'assists', 10, 144, 'tier', 'joueur_all_time',
   '#4FA9E8', false, false, false),
  ('assists__25', 'Passeur confirmé',
   'Atteindre 25 passes décisives avec le club.',
   '🎯', 'joueur', true, 'assists', 25, 145, 'tier', 'joueur_all_time',
   '#1E3A8A', false, false, false),
  ('assists__50', 'Maestro',
   'Atteindre 50 passes décisives avec le club.',
   '🎯', 'joueur', true, 'assists', 50, 146, 'tier', 'joueur_all_time',
   '#7C3AED', false, false, false),
  ('assists__100', 'Architecte du jeu',
   'Atteindre 100 passes décisives avec le club.',
   '🎯', 'joueur', true, 'assists', 100, 147, 'tier', 'joueur_all_time',
   '#1C1C24', true, false, false),
  ('max_match_assists__3', 'Triple passe',
   'Délivrer trois passes décisives au cours d’un même match.',
   '🪄', 'joueur', true, 'max_match_assists', 3, 163, 'tier', 'joueur_all_time',
   '#F1706E', false, true, false)
on conflict (code) do nothing;

-- Les étoiles de saison sont recalculées saison par saison : sans ce cas
-- explicite, le badge à étoile « Chef d’orchestre » s’obtiendrait sans jamais
-- afficher son compteur d’étoiles.
create or replace function private.profile_badge_stars(p_profile_id uuid)
returns table(badge_code text, stars integer)
language sql
security definer
set search_path to 'public'
as $function$
  with metrics as (
    select to_jsonb(t) as v from private.profile_badge_metrics(p_profile_id) t
  ), pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.assists, 0) as a,
           coalesce(st.clean_sheet, false) as cs
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id and att.match_id = m.id
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (st.match_id is not null or att.match_id is not null or mv.match_id is not null)
  ), ps as (
    select season_id,
           count(*) as mp,
           count(*) filter (where win) as w,
           sum(g) as gg,
           sum(a) as aa,
           count(*) filter (where cs) as csn
    from pm group by season_id
  ), seasonal as (
    select b.code as badge_code, count(*)::int as stars
    from public.badges b
    join ps on (
         (b.metric = 'goals_season' and ps.gg >= b.threshold)
      or (b.metric = 'assists_season' and ps.aa >= b.threshold)
      or (b.metric = 'wins_season' and ps.w >= b.threshold)
      or (b.metric = 'matches_played_season' and ps.mp >= b.threshold)
      or (b.metric = 'clean_sheets_season' and ps.csn >= b.threshold)
    )
    where b.has_star and b.category = 'joueur_saison'
    group by b.code
  ), palmares as (
    select b.code as badge_code, count(sa.*)::int as stars
    from public.badges b
    join public.season_awards sa
      on sa.profile_id = p_profile_id
     and sa.award_type = case
           when b.metric = 'seasons_complete' then 'season_complete'
           else substring(b.metric from 7)
         end
    where b.has_star and b.category = 'palmares'
    group by b.code
  ), career as (
    select b.code as badge_code,
           (coalesce((m.v ->> b.metric)::int, 0) / b.threshold)::int as stars
    from public.badges b
    cross join metrics m
    where b.has_star
      and b.category in ('joueur_all_time', 'pronos_all_time')
      and b.metric is not null
      and b.threshold is not null and b.threshold > 0
      and coalesce((m.v ->> b.metric)::int, 0) >= b.threshold
  )
  select badge_code, stars from seasonal
  union all
  select badge_code, stars from palmares
  union all
  select badge_code, stars from career;
$function$;

commit;
