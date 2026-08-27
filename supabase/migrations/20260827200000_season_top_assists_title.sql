begin;

-- Titre de fin de saison « Passe d'or » : le meilleur passeur de la saison,
-- exactement sur le modèle du Soulier d'or.
--
-- Comme pour les buts, une égalité en tête récompense tous les ex æquo, et une
-- saison sans aucune passe décisive ne décerne pas le titre — ce qui laisse
-- naturellement les saisons antérieures au suivi des passes sans lauréat.

-- ---------------------------------------------------------------------------
-- 1. Attribution du titre à la clôture de la saison
-- ---------------------------------------------------------------------------

create or replace function public.award_season_titles(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.season_awards(season_id, profile_id, award_type)
  with eligible_profiles as (
    select profile.id
    from public.profiles profile
    where not profile.is_test_account
  ),
  tot as (
    select count(*)::int as c
    from public.matches
    where season_id = p_season_id
      and status in ('termine', 'archive')
  ),
  sp_prof as (
    select player.id, player.profile_id
    from public.season_players player
    join eligible_profiles eligible on eligible.id = player.profile_id
    where player.season_id = p_season_id
      and player.profile_id is not null
  ),
  present as (
    select distinct spp.profile_id, u.match_id
    from sp_prof spp
    join lateral (
      select ma.match_id from public.match_attendance ma
        where ma.season_player_id = spp.id
      union
      select s.match_id from public.match_player_stats s
        where s.season_player_id = spp.id
      union
      select v.match_id from public.match_man_of_match v
        where v.season_player_id = spp.id
    ) u on true
    join public.matches m
      on m.id = u.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
  ),
  played as (
    select pr.profile_id,
           count(*)::int as n,
           count(*) filter (where m.score_as_grinta > m.score_adverse)::int as w
    from present pr
    join public.matches m on m.id = pr.match_id
    group by pr.profile_id
  ),
  goals as (
    select spp.profile_id, sum(s.goals)::int as g
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m
      on m.id = s.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  assists as (
    select spp.profile_id, sum(s.assists)::int as a
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m
      on m.id = s.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  mvp as (
    select spp.profile_id, count(*)::int as c
    from sp_prof spp
    join public.match_man_of_match v on v.season_player_id = spp.id
    join public.matches m
      on m.id = v.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  pmatch_pts as (
    select vp.profile_id, sum(vp.points)::numeric as pts
    from public.v_match_prediction_points vp
    join eligible_profiles eligible on eligible.id = vp.profile_id
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
  ),
  pmatch_cnt as (
    select mp.profile_id, count(*) filter (where mp.is_filled) as cnt
    from public.match_predictions mp
    join eligible_profiles eligible on eligible.id = mp.profile_id
    join public.matches m
      on m.id = mp.match_id
     and m.season_id = p_season_id
     and m.status in ('termine', 'archive')
    group by mp.profile_id
  ),
  pplayer_base as (
    select points.predictor_profile_id as profile_id,
           sum(points.points)::numeric as pts
    from public.v_season_prediction_points points
    join eligible_profiles eligible on eligible.id = points.predictor_profile_id
    where points.season_id = p_season_id
    group by points.predictor_profile_id
  ),
  pplayer_bonus as (
    select bonus.predictor_profile_id as profile_id,
           sum(bonus.bonus_points)::numeric as bonus_pts
    from public.v_season_prediction_bonus bonus
    join eligible_profiles eligible on eligible.id = bonus.predictor_profile_id
    where bonus.season_id = p_season_id
    group by bonus.predictor_profile_id
  ),
  pplayer_pts as (
    select coalesce(base.profile_id, bonus.profile_id) as profile_id,
           coalesce(base.pts, 0::numeric) + coalesce(bonus.bonus_pts, 0::numeric) as pts
    from pplayer_base base
    full outer join pplayer_bonus bonus on bonus.profile_id = base.profile_id
  ),
  poverall as (
    select coalesce(pm.profile_id, pp.profile_id) as profile_id,
           coalesce(pm.pts, 0::numeric) * 100::numeric + coalesce(pp.pts, 0::numeric) as total
    from pmatch_pts pm
    full outer join pplayer_pts pp on pp.profile_id = pm.profile_id
  ),
  w_complete as (
    select p.profile_id, 'season_complete'::text as at
    from played p, tot
    where tot.c > 0 and p.n = tot.c
  ),
  w_present as (
    select profile_id, 'most_present'
    from (select profile_id, rank() over (order by n desc) rk from played where n > 0) z
    where rk = 1
  ),
  w_scorer as (
    select profile_id, 'top_scorer'
    from (select profile_id, rank() over (order by g desc) rk from goals where g > 0) z
    where rk = 1
  ),
  w_passer as (
    select profile_id, 'top_assists'
    from (select profile_id, rank() over (order by a desc) rk from assists where a > 0) z
    where rk = 1
  ),
  w_mvp as (
    select profile_id, 'mvp_king'
    from (select profile_id, rank() over (order by c desc) rk from mvp where c > 0) z
    where rk = 1
  ),
  w_winrate as (
    select profile_id, 'best_winrate'
    from (
      select profile_id, rank() over (order by (w::numeric / n) desc) rk
      from played where n >= 5
    ) z
    where rk = 1
  ),
  w_pred_match as (
    select profile_id, 'best_pred_match'
    from (
      select pm.profile_id, rank() over (order by pm.pts desc) rk
      from pmatch_pts pm
      join pmatch_cnt pc on pc.profile_id = pm.profile_id
      where pc.cnt >= 5 and pm.pts > 0
    ) z
    where rk = 1
  ),
  w_pred_player as (
    select profile_id, 'best_pred_player'
    from (select profile_id, rank() over (order by pts desc) rk from pplayer_pts where pts > 0) z
    where rk = 1
  ),
  w_pred_overall as (
    select profile_id, 'best_pred_overall'
    from (select profile_id, rank() over (order by total desc) rk from poverall where total > 0) z
    where rk = 1
  )
  select p_season_id, allw.profile_id, allw.at
  from (
    select * from w_complete
    union all select * from w_present
    union all select * from w_scorer
    union all select * from w_passer
    union all select * from w_mvp
    union all select * from w_winrate
    union all select * from w_pred_match
    union all select * from w_pred_player
    union all select * from w_pred_overall
  ) allw
  where allw.profile_id is not null
  on conflict (season_id, profile_id, award_type) do nothing;

  perform public.recalculate_all_badges();
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Métrique du badge : compter le titre gagné
-- ---------------------------------------------------------------------------
--
-- Les étoiles se calculent déjà toutes seules : private.profile_badge_stars
-- déduit le type de titre du nom de la métrique, donc « title_top_assists »
-- trouve « top_assists » sans modification.

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
  max_match_assists integer,
  title_top_assists integer
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
      count(*) filter (where award_type = 'top_assists')::int as title_top_assists,
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
    pmax.max_match_assists,
    aw.title_top_assists
  from player, hist, pmax, mpred_a, own_goal_pred, aw;
$function$;

alter function private.profile_badge_metrics(uuid) owner to postgres;
revoke all on function private.profile_badge_metrics(uuid)
  from public, anon, authenticated;
grant execute on function private.profile_badge_metrics(uuid) to service_role;

comment on function private.profile_badge_metrics(uuid) is
  'Implementation reelle des metriques de badges. Reservee aux appelants internes : passer par public.profile_badge_metrics() qui controle l''identite.';

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
  max_match_assists integer,
  title_top_assists integer
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
revoke all on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Le badge « Passe d'or »
-- ---------------------------------------------------------------------------
--
-- Mêmes couleur, étoile et rareté que le Soulier d'or : c'est son équivalent
-- pour les passes décisives.

insert into public.badges(
  code, name, description, emoji, family, auto, metric, threshold,
  sort_order, kind, category, color, has_star, standalone, secret
) values (
  'title_top_assists__1', 'Passe d''or',
  'Terminer une saison en étant le joueur ayant délivré le plus grand nombre de passes décisives.',
  '🎯', 'joueur', true, 'title_top_assists', 1, 195, 'tier', 'palmares',
  '#B9F2FF', true, false, false
)
on conflict (code) do nothing;

commit;
