-- Les titres se gagnent une seule fois (à vie), pas une fois par saison.
-- On les décerne désormais dans profile_badges (comme les paliers et les
-- badges custom), et on supprime la table profile_titles devenue inutile.

create or replace function public.award_season_titles(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_total integer;
begin
  select count(*) into v_total
  from public.matches
  where season_id = p_season_id and status in ('termine', 'archive');

  -- 1) Meilleurs buteurs (top 3).
  insert into public.profile_badges(profile_id, badge_id, source)
  select r.profile_id, b.id, 'auto'
  from (
    select sp.profile_id, dense_rank() over (order by sum(mps.goals) desc) rk
    from public.match_player_stats mps
    join public.season_players sp on sp.id = mps.season_player_id and sp.profile_id is not null
    join public.matches m on m.id = mps.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by sp.profile_id
    having sum(mps.goals) > 0
  ) r
  join public.badges b on b.code = 'title_top_scorer_' || r.rk
  where r.rk <= 3
  on conflict (profile_id, badge_id) do nothing;

  -- 2) Plus d'HDM.
  insert into public.profile_badges(profile_id, badge_id, source)
  select r.profile_id, b.id, 'auto'
  from (
    select sp.profile_id, dense_rank() over (order by count(*) desc) rk
    from public.match_man_of_match v
    join public.season_players sp on sp.id = v.season_player_id and sp.profile_id is not null
    join public.matches m on m.id = v.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by sp.profile_id
    having count(*) > 0
  ) r
  join public.badges b on b.code = 'title_most_mvp'
  where r.rk = 1
  on conflict (profile_id, badge_id) do nothing;

  -- 3) Meilleur taux de victoire (>= 50 % des matchs joués).
  insert into public.profile_badges(profile_id, badge_id, source)
  select r.profile_id, b.id, 'auto'
  from (
    select profile_id,
           dense_rank() over (order by (w::numeric / nullif(p, 0)) desc) rk
    from (
      select sp.profile_id,
             count(*) as p,
             count(*) filter (where m.score_as_grinta > m.score_adverse) as w
      from public.match_attendance ma
      join public.season_players sp on sp.id = ma.season_player_id and sp.profile_id is not null
      join public.matches m on m.id = ma.match_id
        and m.season_id = p_season_id and m.status in ('termine', 'archive')
      group by sp.profile_id
    ) t
    where p > 0 and p * 2 >= v_total
  ) r
  join public.badges b on b.code = 'title_best_winrate'
  where r.rk = 1
  on conflict (profile_id, badge_id) do nothing;

  -- 4) Meilleur pronostiqueur — matchs.
  insert into public.profile_badges(profile_id, badge_id, source)
  select r.profile_id, b.id, 'auto'
  from (
    select vp.profile_id, dense_rank() over (order by sum(vp.points) desc) rk
    from public.v_match_prediction_points vp
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
    having sum(vp.points) > 0
  ) r
  join public.badges b on b.code = 'title_prono_match'
  where r.rk = 1
  on conflict (profile_id, badge_id) do nothing;

  -- 5) Meilleur pronostiqueur — saison.
  insert into public.profile_badges(profile_id, badge_id, source)
  select r.profile_id, b.id, 'auto'
  from (
    select predictor_profile_id as profile_id,
           dense_rank() over (order by sum(points) desc) rk
    from public.v_season_prediction_points
    where season_id = p_season_id
    group by predictor_profile_id
    having sum(points) > 0
  ) r
  join public.badges b on b.code = 'title_prono_season'
  where r.rk = 1
  on conflict (profile_id, badge_id) do nothing;

  -- 6) Top 1/2/3 pronostiqueur général.
  insert into public.profile_badges(profile_id, badge_id, source)
  select r.profile_id, b.id, 'auto'
  from (
    with mp as (
      select vp.profile_id, sum(vp.points) pts
      from public.v_match_prediction_points vp
      join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
      group by vp.profile_id
    ), sp as (
      select predictor_profile_id profile_id, sum(points)::numeric pts
      from public.v_season_prediction_points where season_id = p_season_id
      group by predictor_profile_id
    ), bn as (
      select predictor_profile_id profile_id, sum(bonus_points)::numeric pts
      from public.v_season_prediction_bonus where season_id = p_season_id
      group by predictor_profile_id
    ), tot as (
      select pr.id profile_id,
             coalesce(mp.pts, 0) m,
             coalesce(sp.pts, 0) + coalesce(bn.pts, 0) s
      from public.profiles pr
      left join mp on mp.profile_id = pr.id
      left join sp on sp.profile_id = pr.id
      left join bn on bn.profile_id = pr.id
      where pr.status = 'active'
    ), mx as (select max(m) mm, max(s) ms from tot)
    select tot.profile_id,
           dense_rank() over (order by
             (case when mx.mm > 0 then tot.m / mx.mm else 0 end) * 70
             + (case when mx.ms > 0 then tot.s / mx.ms else 0 end) * 30 desc) rk,
           (case when mx.mm > 0 then tot.m / mx.mm else 0 end) * 70
             + (case when mx.ms > 0 then tot.s / mx.ms else 0 end) * 30 score
    from tot cross join mx
  ) r
  join public.badges b on b.code = 'title_general_' || r.rk
  where r.rk <= 3 and r.score > 0
  on conflict (profile_id, badge_id) do nothing;
end;
$function$;

-- La table profile_titles n'est plus utilisée : les titres vivent dans
-- profile_badges avec la contrainte unique (profile_id, badge_id) qui garantit
-- « une seule fois, à vie ».
drop table if exists public.profile_titles;
