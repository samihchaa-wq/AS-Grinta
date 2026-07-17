-- Étoiles multiples : quand un joueur ré-atteint un palier étoilé, il gagne une
-- étoile supplémentaire (affichées côte à côte).
--
--  • Paliers étoilés « saison » (joueur_saison) : une étoile par saison où le
--    palier a été atteint (rejouable chaque saison).
--  • Titres / palmarès étoilés (palmares) : une étoile par titre gagné
--    (compteur des season_awards).
--  • Paliers carrière (joueur_all_time, pronos_all_time) : cumulatifs, atteints
--    une seule fois → 1 étoile (non renvoyés ici, défaut 1 côté app).
create or replace function public.profile_badge_stars(p_profile_id uuid)
 returns table(badge_code text, stars integer)
 language sql
 security definer
 set search_path to 'public'
as $function$
  with pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
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
           count(*) filter (where cs) as csn
    from pm group by season_id
  ), seasonal as (
    -- Une étoile par saison où le palier étoilé saisonnier est atteint.
    select b.code as badge_code, count(*)::int as stars
    from public.badges b
    join ps on (
         (b.metric = 'goals_season' and ps.gg >= b.threshold)
      or (b.metric = 'wins_season' and ps.w >= b.threshold)
      or (b.metric = 'matches_played_season' and ps.mp >= b.threshold)
      or (b.metric = 'clean_sheets_season' and ps.csn >= b.threshold)
    )
    where b.has_star and b.category = 'joueur_saison'
    group by b.code
  ), palmares as (
    -- Une étoile par titre gagné / saison complétée.
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
  )
  select badge_code, stars from seasonal
  union all
  select badge_code, stars from palmares;
$function$;

grant execute on function public.profile_badge_stars(uuid) to authenticated;
