-- Badge « Prophète » : un joueur a parié sur SON PROPRE nombre de buts sur la
-- saison (prono de saison, catégorie « buts ») et est tombé pile juste, sur une
-- saison archivée (total définitif). Autonome, non secret, fond violet.
-- L'attribution passe par le moteur automatique existant, recalculé à la
-- clôture (archivage) de la saison via award_season_titles().

-- Nouvelle métrique perfect_own_goals_prediction : on remplace la fonction pour
-- ajouter la colonne (le type de retour change).
drop function if exists public.profile_badge_metrics(uuid);

create function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer, wins_season integer, goals_season integer,
  clean_sheets_season integer, matches_played integer, wins integer,
  goals integer, doubles integer, max_match_goals integer, mvp integer,
  clean_sheets integer, pred_good_result integer, pred_exact_score integer,
  bet_against_grinta integer, perfect_own_goals_prediction integer,
  seasons_complete integer, title_most_present integer, title_top_scorer integer,
  title_mvp_king integer, title_best_winrate integer,
  title_best_pred_player integer, title_best_pred_match integer,
  title_best_pred_overall integer
)
language sql
security definer
set search_path to 'public'
as $function$
  with pm as (
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
           count(*) filter (where g = 2) as dbl
    from pm group by season_id
  ), player as (
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
  ), hist as (
    select
      coalesce(sum(h.matches_played), 0)::int as h_mp,
      coalesce(sum(h.wins), 0)::int as h_w,
      coalesce(sum(h.goals), 0)::int as h_g,
      coalesce(sum(h.clean_sheets), 0)::int as h_cs,
      coalesce(sum(h.hdm), 0)::int as h_mvp
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and (
        h.profile_id = p_profile_id
        or (
          h.profile_id is null
          and lower(btrim(h.player_name)) in (
            select distinct lower(btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, ''))))
            from public.season_players sp
            where sp.profile_id = p_profile_id
              and coalesce(btrim(sp.first_name), '') <> ''
          )
        )
      )
  ), pmax as (
    select coalesce(max(g), 0)::int as max_match_goals from pm
  ), mpred as (
    select
      (mp.is_filled and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int as bon,
      (mp.is_filled and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse)::int as ex,
      (mp.is_filled and mp.predicted_score_as_grinta < mp.predicted_score_adverse)::int as against
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ), mpred_a as (
    select coalesce(sum(bon), 0)::int as pred_good_result,
           coalesce(sum(ex), 0)::int as pred_exact_score,
           coalesce(sum(against), 0)::int as bet_against_grinta
    from mpred
  ), own_goal_pred as (
    -- Prono de saison où le joueur a parié sur ses PROPRES buts et est tombé
    -- pile juste (>= 1), sur une saison archivée (total définitif).
    select coalesce(count(*), 0)::int as perfect_own_goals_prediction
    from public.season_predictions sp
    join public.season_players spl on spl.id = sp.season_player_id
    join public.seasons se on se.id = sp.season_id and se.status = 'archived'
    join lateral (
      select coalesce(sum(s.goals), 0)::int as g
      from public.match_player_stats s
      join public.matches m on m.id = s.match_id
        and m.season_id = sp.season_id and m.status in ('termine', 'archive')
      where s.season_player_id = sp.season_player_id
    ) tot on true
    where sp.predictor_profile_id = p_profile_id
      and spl.profile_id = p_profile_id
      and sp.category = 'buts'
      and sp.is_filled
      and sp.predicted_value_30 >= 1
      and sp.predicted_value_30 = tot.g
  ), aw as (
    select
      count(*) filter (where award_type = 'season_complete')::int as seasons_complete,
      count(*) filter (where award_type = 'most_present')::int as title_most_present,
      count(*) filter (where award_type = 'top_scorer')::int as title_top_scorer,
      count(*) filter (where award_type = 'mvp_king')::int as title_mvp_king,
      count(*) filter (where award_type = 'best_winrate')::int as title_best_winrate,
      count(*) filter (where award_type = 'best_pred_player')::int as title_best_pred_player,
      count(*) filter (where award_type = 'best_pred_match')::int as title_best_pred_match,
      count(*) filter (where award_type = 'best_pred_overall')::int as title_best_pred_overall
    from public.season_awards where profile_id = p_profile_id
  )
  select
    player.matches_played_season, player.wins_season, player.goals_season,
    player.clean_sheets_season,
    (player.matches_played + hist.h_mp)::int as matches_played,
    (player.wins + hist.h_w)::int as wins,
    (player.goals + hist.h_g)::int as goals,
    player.doubles, pmax.max_match_goals,
    (player.mvp + hist.h_mvp)::int as mvp,
    (player.clean_sheets + hist.h_cs)::int as clean_sheets,
    mpred_a.pred_good_result, mpred_a.pred_exact_score,
    mpred_a.bet_against_grinta, own_goal_pred.perfect_own_goals_prediction,
    aw.seasons_complete, aw.title_most_present, aw.title_top_scorer,
    aw.title_mvp_king, aw.title_best_winrate,
    aw.title_best_pred_player, aw.title_best_pred_match, aw.title_best_pred_overall
  from player, hist, pmax, mpred_a, own_goal_pred, aw;
$function$;

revoke all on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated, service_role;

insert into public.badges(
  code, name, description, emoji, family, category, kind, auto,
  metric, threshold, sort_order, color, has_star, standalone, secret
) values (
  'perfect_own_goals_prediction__1',
  'Prophète',
  'Tu as prédit ton propre total de buts sur la saison… au but près. Chapeau.',
  '🔮',
  'pronostiqueur',
  'pronos_all_time',
  'tier',
  true,
  'perfect_own_goals_prediction',
  1,
  901,
  '#7C3AED',
  false,
  true,
  false
)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  emoji = excluded.emoji,
  family = excluded.family,
  category = excluded.category,
  kind = excluded.kind,
  auto = excluded.auto,
  metric = excluded.metric,
  threshold = excluded.threshold,
  color = excluded.color,
  standalone = excluded.standalone,
  secret = excluded.secret;

select public.recalculate_all_badges();
