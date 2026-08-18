-- Test accounts must not participate in the ranking that determines season
-- titles. Filtering only after rank() could otherwise remove the test winner
-- without promoting the best real predictor.

create or replace function public.award_season_titles(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $function$
begin
  insert into public.season_awards(season_id, profile_id, award_type)
  with eligible_profiles as (
    select profile.id
    from public.profiles profile
    where not profile.is_test_account
  ),
  tot as (
    select count(*)::int as c from public.matches
    where season_id = p_season_id and status in ('termine', 'archive')
  ),
  sp_prof as (
    select player.id, player.profile_id
    from public.season_players player
    join eligible_profiles eligible on eligible.id = player.profile_id
    where player.season_id = p_season_id and player.profile_id is not null
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
    join eligible_profiles eligible on eligible.id = vp.profile_id
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
  ),
  pmatch_cnt as (
    select mp.profile_id, count(*) filter (where mp.is_filled) as cnt
    from public.match_predictions mp
    join eligible_profiles eligible on eligible.id = mp.profile_id
    join public.matches m on m.id = mp.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by mp.profile_id
  ),
  pplayer_pts as (
    select points.predictor_profile_id as profile_id, sum(points.points)::numeric as pts
    from public.v_season_prediction_points points
    join eligible_profiles eligible on eligible.id = points.predictor_profile_id
    where points.season_id = p_season_id
    group by points.predictor_profile_id
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
  select p_season_id, allw.profile_id, allw.at
  from (
    select * from w_complete
    union all select * from w_present
    union all select * from w_scorer
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
