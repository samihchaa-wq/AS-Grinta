-- Étoiles des paliers étoilés CARRIÈRE : chaque multiple du seuil ajoute une
-- étoile. Ex. « 100 buts » → 1 étoile ; 200 buts → 2 ; 300 → 3. Idem pour les
-- clean sheets, victoires, etc. (paliers cumulatifs joueur_all_time /
-- pronos_all_time).
--
-- Les paliers « saison » gardent leur logique (une étoile par saison où le
-- palier est atteint) et les titres/palmarès une étoile par titre gagné.
create or replace function public.profile_badge_stars(p_profile_id uuid)
 returns table(badge_code text, stars integer)
 language sql
 security definer
 set search_path to 'public'
as $function$
  with metrics as (
    select to_jsonb(t) as v from public.profile_badge_metrics(p_profile_id) t
  ), pm as (
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
  ), career as (
    -- Une étoile par multiple du seuil atteint (100 buts → 1, 200 → 2, …).
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

grant execute on function public.profile_badge_stars(uuid) to authenticated;
