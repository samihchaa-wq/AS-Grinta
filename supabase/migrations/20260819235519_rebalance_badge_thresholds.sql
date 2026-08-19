-- Rebalance badge thresholds against the full 2013-2026 club history.
-- Clean-sheet badges use the same definition as the Statistics "CS" column:
-- the player was present in a match where AS Grinta conceded 0 goals.

create or replace function private.profile_badge_metrics(p_profile_id uuid)
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
  title_best_pred_overall integer
)
language sql
security definer
set search_path = ''
as $function$
  with pm as (
    select
      m.season_id,
      (m.score_as_grinta > m.score_adverse) as win,
      coalesce(st.goals, 0) as g,
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
      coalesce(max(ps.csn) filter (where s.status = 'open'), 0)::int as clean_sheets_season,
      coalesce(sum(ps.mp), 0)::int as matches_played,
      coalesce(sum(ps.w), 0)::int as wins,
      coalesce(sum(ps.gg), 0)::int as goals,
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
    select coalesce(max(g), 0)::int as max_match_goals
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
    aw.title_best_pred_overall
  from player, hist, pmax, mpred_a, own_goal_pred, aw;
$function$;

create or replace function public.profile_badge_display_metrics(p_profile_id uuid)
returns table(metric text, current_value integer, display_value integer)
language sql
stable
set search_path = ''
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

update public.badges
set code = case code
  when 'goals__75' then '__rebalance_goals_75'
  when 'goals__100' then '__rebalance_goals_100'
end
where code in ('goals__75', 'goals__100');

update public.badges
set code = 'goals__100',
    name = 'Centurion',
    description = 'Atteindre la barre mythique des 100 buts avec le club.',
    threshold = 100,
    sort_order = 116,
    has_star = false
where code = '__rebalance_goals_75';

update public.badges
set code = 'goals__200',
    name = 'Chasseur de records',
    description = 'Atteindre 200 buts marqués avec le club.',
    threshold = 200,
    sort_order = 117,
    has_star = true
where code = '__rebalance_goals_100';

delete from public.profile_badges pb
using public.badges b
where pb.badge_id = b.id
  and b.code = 'goals__200'
  and not exists (
    select 1
    from private.profile_badge_metrics(pb.profile_id) m
    where m.goals >= 200
  );

update public.badges
set code = case code
  when 'wins_season__10' then '__rebalance_wins_season_10'
  when 'wins_season__15' then '__rebalance_wins_season_15'
  when 'wins_season__20' then '__rebalance_wins_season_20'
  when 'wins_season__25' then '__rebalance_wins_season_25'
end
where code in ('wins_season__10','wins_season__15','wins_season__20','wins_season__25');

update public.badges set code='wins_season__5', threshold=5, description='Remporter 5 matchs au cours d’une même saison.' where code='__rebalance_wins_season_10';
update public.badges set code='wins_season__10', threshold=10, description='Remporter 10 matchs au cours d’une même saison.' where code='__rebalance_wins_season_15';
update public.badges set code='wins_season__15', threshold=15, description='Remporter 15 matchs au cours d’une même saison.' where code='__rebalance_wins_season_20';
update public.badges set code='wins_season__20', threshold=20, description='Remporter 20 matchs au cours d’une même saison.' where code='__rebalance_wins_season_25';

update public.badges
set code = case code
  when 'mvp__10' then '__rebalance_mvp_10'
  when 'mvp__20' then '__rebalance_mvp_20'
  when 'mvp__30' then '__rebalance_mvp_30'
  when 'mvp__50' then '__rebalance_mvp_50'
end
where code in ('mvp__10','mvp__20','mvp__30','mvp__50');

update public.badges set code='mvp__5', threshold=5, description='Obtenir 5 distinctions d’Homme du match avec le club.' where code='__rebalance_mvp_10';
update public.badges set code='mvp__10', threshold=10, description='Obtenir 10 distinctions d’Homme du match avec le club.' where code='__rebalance_mvp_20';
update public.badges set code='mvp__20', threshold=20, description='Obtenir 20 distinctions d’Homme du match avec le club.' where code='__rebalance_mvp_30';
update public.badges set code='mvp__30', threshold=30, description='Obtenir 30 distinctions d’Homme du match avec le club.' where code='__rebalance_mvp_50';

update public.badges
set code='clean_sheets__40', threshold=40,
    description='Être présent lors de 40 matchs où l’AS Grinta n’encaisse aucun but.',
    has_star=true
where code='clean_sheets__50';

update public.badges
set description='Être présent lors de ' || threshold::text || ' matchs où l’AS Grinta n’encaisse aucun but.'
where metric='clean_sheets' and kind='tier';

update public.badges
set description='Être présent lors de ' || threshold::text || ' matchs où l’AS Grinta n’encaisse aucun but au cours d’une même saison.'
where metric='clean_sheets_season' and kind='tier';

do $do$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.recalculate_profile_badges(r.id);
  end loop;
end;
$do$;
