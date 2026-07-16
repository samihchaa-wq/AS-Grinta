-- Phase 4 : titres de fin de saison + palmarès.
-- Un registre season_awards note, pour chaque saison, qui remporte chaque titre
-- (et qui a fait une saison complète). Les métriques de palmarès comptent ces
-- titres ; le moteur décerne alors les paliers correspondants.

create table if not exists public.season_awards (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  award_type text not null,
  created_at timestamptz not null default now(),
  unique (season_id, profile_id, award_type)
);

-- Lecture/écriture réservées aux fonctions SECURITY DEFINER (pas d'accès direct).
alter table public.season_awards enable row level security;

-- Attribution des titres d'une saison (idempotent). Appelée par le trigger de
-- clôture (season -> 'archived').
create or replace function public.award_season_titles(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.season_awards(season_id, profile_id, award_type)
  with tot as (
    select count(*)::int as c from public.matches
    where season_id = p_season_id and status in ('termine', 'archive')
  ),
  sp_prof as (
    select id, profile_id from public.season_players
    where season_id = p_season_id and profile_id is not null
  ),
  present as (
    select distinct spp.profile_id, u.match_id
    from sp_prof spp
    join lateral (
      select ma.match_id from public.match_attendance ma where ma.season_player_id = spp.id
      union select s.match_id from public.match_player_stats s where s.season_player_id = spp.id
      union select v.match_id from public.match_man_of_match v where v.season_player_id = spp.id
    ) u on true
    join public.matches m on m.id = u.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
  ),
  played as (
    select pr.profile_id, count(*)::int as n,
           count(*) filter (where m.score_as_grinta > m.score_adverse)::int as w
    from present pr join public.matches m on m.id = pr.match_id
    group by pr.profile_id
  ),
  goals as (
    select spp.profile_id, sum(s.goals)::int as g
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m on m.id = s.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  mvp as (
    select spp.profile_id, count(*)::int as c
    from sp_prof spp
    join public.match_man_of_match v on v.season_player_id = spp.id
    join public.matches m on m.id = v.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  pmatch_pts as (
    select vp.profile_id, sum(vp.points) as pts
    from public.v_match_prediction_points vp
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
  ),
  pmatch_cnt as (
    select mp.profile_id, count(*) filter (where mp.is_filled) as cnt
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by mp.profile_id
  ),
  pplayer_pts as (
    select predictor_profile_id as profile_id, sum(points)::numeric as pts
    from public.v_season_prediction_points where season_id = p_season_id
    group by predictor_profile_id
  ),
  poverall as (
    select coalesce(pm.profile_id, pp.profile_id) as profile_id,
           coalesce(pm.pts, 0) + coalesce(pp.pts, 0) as total
    from pmatch_pts pm
    full outer join pplayer_pts pp on pp.profile_id = pm.profile_id
  ),
  w_complete as (
    select p.profile_id, 'season_complete'::text as at
    from played p, tot where tot.c > 0 and p.n = tot.c
  ),
  w_present as (
    select profile_id, 'most_present' from (
      select profile_id, rank() over (order by n desc) rk from played where n > 0
    ) z where rk = 1
  ),
  w_scorer as (
    select profile_id, 'top_scorer' from (
      select profile_id, rank() over (order by g desc) rk from goals where g > 0
    ) z where rk = 1
  ),
  w_mvp as (
    select profile_id, 'mvp_king' from (
      select profile_id, rank() over (order by c desc) rk from mvp where c > 0
    ) z where rk = 1
  ),
  w_winrate as (
    select profile_id, 'best_winrate' from (
      select profile_id, rank() over (order by (w::numeric / n) desc) rk
      from played where n >= 5
    ) z where rk = 1
  ),
  w_pred_match as (
    select profile_id, 'best_pred_match' from (
      select pm.profile_id, rank() over (order by pm.pts desc) rk
      from pmatch_pts pm join pmatch_cnt pc on pc.profile_id = pm.profile_id
      where pc.cnt >= 5 and pm.pts > 0
    ) z where rk = 1
  ),
  w_pred_player as (
    select profile_id, 'best_pred_player' from (
      select profile_id, rank() over (order by pts desc) rk from pplayer_pts where pts > 0
    ) z where rk = 1
  ),
  w_pred_overall as (
    select profile_id, 'best_pred_overall' from (
      select profile_id, rank() over (order by total desc) rk from poverall where total > 0
    ) z where rk = 1
  )
  select p_season_id, profile_id, at from (
    select * from w_complete
    union all select * from w_present
    union all select * from w_scorer
    union all select * from w_mvp
    union all select * from w_winrate
    union all select * from w_pred_match
    union all select * from w_pred_player
    union all select * from w_pred_overall
  ) allw
  where profile_id is not null
  on conflict (season_id, profile_id, award_type) do nothing;

  perform public.recalculate_all_badges();
end;
$function$;

-- Métriques : on ajoute les compteurs de titres (palmarès) lus depuis
-- season_awards, en plus des métriques joueur/pronos existantes.
drop function if exists public.profile_badge_metrics(uuid);

create function public.profile_badge_metrics(p_profile_id uuid)
returns table(
  matches_played_season integer, wins_season integer, goals_season integer,
  clean_sheets_season integer,
  matches_played integer, wins integer, goals integer,
  doubles integer, max_match_goals integer, mvp integer, clean_sheets integer,
  pred_good_result integer, pred_exact_score integer,
  seasons_complete integer, title_most_present integer, title_top_scorer integer,
  title_mvp_king integer, title_best_winrate integer,
  title_best_pred_player integer, title_best_pred_match integer,
  title_best_pred_overall integer
)
language sql
security definer
set search_path to 'public'
as $$
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
      coalesce(max(mp), 0)::int as matches_played_season,
      coalesce(max(w), 0)::int as wins_season,
      coalesce(max(gg), 0)::int as goals_season,
      coalesce(max(csn), 0)::int as clean_sheets_season,
      coalesce(sum(mp), 0)::int as matches_played,
      coalesce(sum(w), 0)::int as wins,
      coalesce(sum(gg), 0)::int as goals,
      coalesce(sum(dbl), 0)::int as doubles,
      coalesce(sum(mvpn), 0)::int as mvp,
      coalesce(sum(csn), 0)::int as clean_sheets
    from ps
  ), pmax as (
    select coalesce(max(g), 0)::int as max_match_goals from pm
  ), mpred as (
    select
      (mp.is_filled and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int as bon,
      (mp.is_filled and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse)::int as ex
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ), mpred_a as (
    select coalesce(sum(bon), 0)::int as pred_good_result,
           coalesce(sum(ex), 0)::int as pred_exact_score
    from mpred
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
    player.matches_played, player.wins, player.goals,
    player.doubles, pmax.max_match_goals, player.mvp, player.clean_sheets,
    mpred_a.pred_good_result, mpred_a.pred_exact_score,
    aw.seasons_complete, aw.title_most_present, aw.title_top_scorer,
    aw.title_mvp_king, aw.title_best_winrate,
    aw.title_best_pred_player, aw.title_best_pred_match, aw.title_best_pred_overall
  from player, pmax, mpred_a, aw;
$$;

revoke execute on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated;
