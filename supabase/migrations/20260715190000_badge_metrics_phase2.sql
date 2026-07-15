-- Phase 2 : métriques réelles des badges (joueur + pronos, saison + carrière).
-- « saison » = meilleure valeur atteinte sur une seule saison ; « carrière » =
-- cumul sur toutes les saisons. Les métriques de palmarès (titres, saisons
-- complètes/parfaites) restent à 0 jusqu'à la phase 4 (attribuées à la clôture).
-- Le type de retour change : on drop puis recrée, et on réapplique le verrou.
drop function if exists public.profile_badge_metrics(uuid);

create function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer, wins_season integer, goals_season integer,
  mvp_season integer, clean_sheets_season integer,
  matches_played integer, wins integer, goals integer,
  doubles integer, hattricks integer, mvp integer, clean_sheets integer,
  pred_validated_season integer, pred_good_result_season integer,
  pred_exact_score_season integer, pred_player_exact_season integer,
  pred_validated integer, pred_good_result integer,
  pred_exact_score integer, pred_player_exact integer
)
language sql
security definer
set search_path to 'public'
as $$
  with pm as (
    -- une ligne par match où ce profil (via son season_player) était présent
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.clean_sheet, false) as cs,
           (mv.season_player_id is not null) as is_mvp
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
           count(*) filter (where cs) as csn,
           count(*) filter (where is_mvp) as mvpn,
           count(*) filter (where g = 2) as dbl,
           count(*) filter (where g >= 3) as hat
    from pm group by season_id
  ), player as (
    select
      coalesce(max(mp), 0)::int as matches_played_season,
      coalesce(max(w), 0)::int as wins_season,
      coalesce(max(gg), 0)::int as goals_season,
      coalesce(max(mvpn), 0)::int as mvp_season,
      coalesce(max(csn), 0)::int as clean_sheets_season,
      coalesce(sum(mp), 0)::int as matches_played,
      coalesce(sum(w), 0)::int as wins,
      coalesce(sum(gg), 0)::int as goals,
      coalesce(sum(dbl), 0)::int as doubles,
      coalesce(sum(hat), 0)::int as hattricks,
      coalesce(sum(mvpn), 0)::int as mvp,
      coalesce(sum(csn), 0)::int as clean_sheets
    from ps
  ), mpred as (
    select m.season_id,
      (mp.is_filled)::int as filled,
      (mp.is_filled and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int as bon,
      (mp.is_filled and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse)::int as ex
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ), mpred_s as (
    select season_id, sum(filled) f, sum(bon) b, sum(ex) e from mpred group by season_id
  ), mpred_a as (
    select
      coalesce(max(f), 0)::int as pred_validated_season,
      coalesce(max(b), 0)::int as pred_good_result_season,
      coalesce(max(e), 0)::int as pred_exact_score_season,
      coalesce(sum(f), 0)::int as pred_validated,
      coalesce(sum(b), 0)::int as pred_good_result,
      coalesce(sum(e), 0)::int as pred_exact_score
    from mpred_s
  ), spred as (
    select season_id, sum(exact) e
    from public.v_season_prediction_flags
    where predictor_profile_id = p_profile_id group by season_id
  ), spred_a as (
    select coalesce(max(e), 0)::int as pred_player_exact_season,
           coalesce(sum(e), 0)::int as pred_player_exact
    from spred
  )
  select
    player.matches_played_season, player.wins_season, player.goals_season,
    player.mvp_season, player.clean_sheets_season,
    player.matches_played, player.wins, player.goals,
    player.doubles, player.hattricks, player.mvp, player.clean_sheets,
    mpred_a.pred_validated_season, mpred_a.pred_good_result_season,
    mpred_a.pred_exact_score_season, spred_a.pred_player_exact_season,
    mpred_a.pred_validated, mpred_a.pred_good_result,
    mpred_a.pred_exact_score, spred_a.pred_player_exact
  from player, mpred_a, spred_a;
$$;

revoke execute on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated;
