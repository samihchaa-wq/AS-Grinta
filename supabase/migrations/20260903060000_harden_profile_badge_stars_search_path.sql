-- private.profile_badge_stars est la seule fonction SECURITY DEFINER encore
-- sur search_path=public qu'un compte connecte puisse executer.
--
-- Le detournement classique du search_path suppose de pouvoir creer un objet
-- dans un schema consulte avant le bon. Ni anon ni authenticated n'ont le
-- droit CREATE sur public, private ou extensions, donc rien n'etait
-- exploitable ici. La fonction passe malgre tout au search_path vide, comme
-- le reste de la surface exposee : c'est une defense qui ne depend plus d'un
-- droit accorde ailleurs.
--
-- Le corps est deja entierement qualifie, public. ou private. sur chaque
-- table. Seule la clause SET change ; le resultat de la fonction est
-- inchange. Les fonctions et types utilises sans qualification appartiennent
-- tous a pg_catalog, qui reste resolu meme avec un search_path vide.

create or replace function private.profile_badge_stars(p_profile_id uuid)
returns table(badge_code text, stars integer)
language sql
security definer
set search_path to ''
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
