-- Barème gradué des pronostics de match :
--   score exact                                  → cote × 20
--   bon vainqueur + bon écart de buts            → cote × 15
--   bon vainqueur + score exact d'une des équipes → cote × 15
--   bon vainqueur seul                           → cote × 10
--   mauvais vainqueur ou pronostic non rempli    → 0
create or replace view public.v_match_prediction_points
with (security_invoker = true) as
select
  mp.id,
  mp.match_id,
  mp.profile_id,
  case
    when not mp.is_filled then 0::numeric
    when sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
         <> sign((m.score_as_grinta - m.score_adverse)::numeric) then 0::numeric
    else
      (case
        when m.score_as_grinta > m.score_adverse then mo.odds_victoire_as_grinta
        when m.score_as_grinta = m.score_adverse then mo.odds_nul
        else mo.odds_victoire_adverse
      end)
      * (case
        when mp.predicted_score_as_grinta = m.score_as_grinta
         and mp.predicted_score_adverse = m.score_adverse then 20
        when (mp.predicted_score_as_grinta - mp.predicted_score_adverse)
             = (m.score_as_grinta - m.score_adverse) then 15
        when mp.predicted_score_as_grinta = m.score_as_grinta
          or mp.predicted_score_adverse = m.score_adverse then 15
        else 10
      end)::numeric
  end as points
from match_predictions mp
join matches m
  on m.id = mp.match_id
 and m.status = any (array['termine'::text, 'archive'::text])
join match_odds mo on mo.match_id = m.id;

-- Le maximum théorique par match passe de cote×15 à cote×20.
create or replace view public.v_classement_general
with (security_invoker = true) as
with mt as (
  select profile_id, coalesce(sum(points), 0::numeric) as match_points
  from public.v_match_prediction_points
  group by profile_id
), st as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points), 0)::numeric as season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
), match_max as (
  select coalesce(sum((
    case
      when m.score_as_grinta > m.score_adverse then mo.odds_victoire_as_grinta
      when m.score_as_grinta = m.score_adverse then mo.odds_nul
      else mo.odds_victoire_adverse
    end) * 20::numeric), 0::numeric) as max_points
  from matches m
  join match_odds mo on mo.match_id = m.id
  where m.status = any (array['termine'::text, 'archive'::text])
    and m.score_as_grinta is not null
    and m.score_adverse is not null
), season_expected as (
  select sp.predictor_profile_id as profile_id,
         count(*)::numeric * 20::numeric as max_points
  from season_predictions sp
  join seasons s on s.id = sp.season_id
  left join public.v_player_season_stats stats
    on stats.season_id = sp.season_id
   and stats.profile_id = sp.player_profile_id
  where not (s.status = 'archived'::text and coalesce(stats.matches_played, 0) < 3)
  group by sp.predictor_profile_id
)
select
  p.id as profile_id,
  p.first_name,
  p.last_name,
  coalesce(mt.match_points, 0::numeric) as match_points,
  coalesce(st.season_points, 0::numeric) as season_points,
  coalesce(mt.match_points, 0::numeric) + coalesce(st.season_points, 0::numeric) as total_points,
  mm.max_points as match_max_points,
  coalesce(se.max_points, 0::numeric) as season_max_points,
  case
    when mm.max_points > 0::numeric
      then round(100::numeric * coalesce(mt.match_points, 0::numeric) / mm.max_points, 2)
    else 0::numeric
  end as match_percentage,
  case
    when coalesce(se.max_points, 0::numeric) > 0::numeric
      then round(100::numeric * coalesce(st.season_points, 0::numeric) / se.max_points, 2)
    else 0::numeric
  end as season_percentage,
  p.surnom
from profiles p
cross join match_max mm
left join mt on mt.profile_id = p.id
left join st on st.profile_id = p.id
left join season_expected se on se.profile_id = p.id
where p.status = 'active'::text;
