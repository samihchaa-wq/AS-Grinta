-- Barème saison dynamique et classement général additif.
--
-- Pour chaque joueur pronostiqué :
--   points = (N - rang_de_proximite + 1) * 3
--   nombre exact = points * 2
-- Les ex aequo utilisent RANK(): chacun obtient le meilleur rang commun et
-- le rang suivant saute les places correspondantes (1, 1, 3...).
--
-- Bonus d'ordre des buteurs : comparaison de chaque paire de joueurs de champ.
-- Aucune récompense jusqu'à 50 % de duels corrects, puis progression linéaire
-- jusqu'à N * 30 points pour un ordre entièrement correct.
--
-- Classement général : total = points matchs + points saison.

create or replace view public.v_season_prediction_points as
with eligible_seasons as (
  select id, status
  from public.seasons
  where season_predictions_locked_at is not null
     or status = 'archived'
), expected_predictions as (
  select sp.season_id, count(*)::bigint as expected_count
  from public.season_players sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id
), predictor_completion as (
  select sp.season_id,
         sp.predictor_profile_id,
         count(*) filter (
           where sp.is_filled
             and sp.category in ('buts', 'clean_sheets')
         )::bigint as filled_count
  from public.season_predictions sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id, sp.predictor_profile_id
), eligible_predictors as (
  select pc.season_id, pc.predictor_profile_id
  from predictor_completion pc
  join expected_predictions ep on ep.season_id = pc.season_id
  where ep.expected_count > 0
    and pc.filled_count = ep.expected_count
), base as (
  select sp.id,
         sp.season_id,
         sp.predictor_profile_id,
         sp.season_player_id,
         sp.category,
         sp.predicted_value_30,
         case sp.category
           when 'buts' then st.goals
           when 'clean_sheets' then st.clean_sheets
           else 0
         end as metric,
         es.status as season_status,
         mc.matches_played
  from public.season_predictions sp
  join eligible_predictors ep
    on ep.season_id = sp.season_id
   and ep.predictor_profile_id = sp.predictor_profile_id
  join eligible_seasons es on es.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.is_filled
    and sp.category in ('buts', 'clean_sheets')
), targeted as (
  select base.*,
         case
           when season_status = 'archived' then metric::numeric
           when coalesce(matches_played, 0) > 0
             then round(metric::numeric * 30.0 / matches_played::numeric)
           else null::numeric
         end as target
  from base
), ranked as (
  select targeted.*,
         count(*) over (
           partition by season_id, season_player_id, category
         ) as participant_count,
         rank() over (
           partition by season_id, season_player_id, category
           order by abs(predicted_value_30::numeric - target)
         ) as proximity_rank
  from targeted
  where target is not null
)
select id,
       season_id,
       predictor_profile_id,
       season_player_id,
       category,
       (
         (participant_count - proximity_rank + 1)
         * 3
         * case when predicted_value_30::numeric = target then 2 else 1 end
       )::integer as points
from ranked;

alter view public.v_season_prediction_points set (security_invoker = true);
revoke all privileges on table public.v_season_prediction_points from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_points from authenticated;
grant select on table public.v_season_prediction_points to authenticated;

create or replace view public.v_season_prediction_flags as
with eligible_seasons as (
  select id, status
  from public.seasons
  where season_predictions_locked_at is not null
     or status = 'archived'
), expected_predictions as (
  select sp.season_id, count(*)::bigint as expected_count
  from public.season_players sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id
), predictor_completion as (
  select sp.season_id,
         sp.predictor_profile_id,
         count(*) filter (
           where sp.is_filled
             and sp.category in ('buts', 'clean_sheets')
         )::bigint as filled_count
  from public.season_predictions sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id, sp.predictor_profile_id
), eligible_predictors as (
  select pc.season_id, pc.predictor_profile_id
  from predictor_completion pc
  join expected_predictions ep on ep.season_id = pc.season_id
  where ep.expected_count > 0
    and pc.filled_count = ep.expected_count
), base as (
  select sp.season_id,
         sp.predictor_profile_id,
         sp.season_player_id,
         sp.category,
         sp.predicted_value_30,
         case sp.category
           when 'buts' then st.goals
           when 'clean_sheets' then st.clean_sheets
           else 0
         end as metric,
         es.status as season_status,
         mc.matches_played
  from public.season_predictions sp
  join eligible_predictors ep
    on ep.season_id = sp.season_id
   and ep.predictor_profile_id = sp.predictor_profile_id
  join eligible_seasons es on es.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.is_filled
    and sp.category in ('buts', 'clean_sheets')
), targeted as (
  select base.*,
         case
           when season_status = 'archived' then metric::numeric
           when coalesce(matches_played, 0) > 0
             then round(metric::numeric * 30.0 / matches_played::numeric)
           else null::numeric
         end as target
  from base
), ranked as (
  select targeted.*,
         rank() over (
           partition by season_id, season_player_id, category
           order by abs(predicted_value_30::numeric - target)
         ) as proximity_rank
  from targeted
  where target is not null
)
select season_id,
       predictor_profile_id,
       (proximity_rank = 1)::integer as bon_pari,
       (predicted_value_30::numeric = target)::integer as exact
from ranked;

alter view public.v_season_prediction_flags set (security_invoker = true);
revoke all privileges on table public.v_season_prediction_flags from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_flags from authenticated;
grant select on table public.v_season_prediction_flags to authenticated;

create or replace view public.v_season_prediction_bonus as
with eligible_seasons as (
  select id, status
  from public.seasons
  where season_predictions_locked_at is not null
     or status = 'archived'
), expected_predictions as (
  select sp.season_id, count(*)::bigint as expected_count
  from public.season_players sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id
), predictor_completion as (
  select sp.season_id,
         sp.predictor_profile_id,
         count(*) filter (
           where sp.is_filled
             and sp.category in ('buts', 'clean_sheets')
         )::bigint as filled_count
  from public.season_predictions sp
  join eligible_seasons es on es.id = sp.season_id
  group by sp.season_id, sp.predictor_profile_id
), eligible_predictors as (
  select pc.season_id, pc.predictor_profile_id
  from predictor_completion pc
  join expected_predictions ep on ep.season_id = pc.season_id
  where ep.expected_count > 0
    and pc.filled_count = ep.expected_count
), participant_count as (
  select season_id, count(*)::integer as participant_count
  from eligible_predictors
  group by season_id
), target_goals as (
  select pl.season_id,
         pl.id as season_player_id,
         case
           when es.status = 'archived' then st.goals::numeric
           when coalesce(mc.matches_played, 0) > 0
             then round(st.goals::numeric * 30.0 / mc.matches_played::numeric)
           else null::numeric
         end as target
  from public.season_players pl
  join eligible_seasons es on es.id = pl.season_id
  join public.v_player_season_stats st on st.season_player_id = pl.id
  left join public.v_season_match_count mc on mc.season_id = pl.season_id
  where not pl.is_goalkeeper
), goal_predictions as (
  select sp.season_id,
         sp.predictor_profile_id,
         sp.season_player_id,
         sp.predicted_value_30
  from public.season_predictions sp
  join eligible_predictors ep
    on ep.season_id = sp.season_id
   and ep.predictor_profile_id = sp.predictor_profile_id
  join public.season_players pl on pl.id = sp.season_player_id
  where sp.category = 'buts'
    and sp.is_filled
    and not pl.is_goalkeeper
), pair_scores as (
  select a.season_id,
         a.predictor_profile_id,
         count(*)::integer as total_pairs,
         count(*) filter (
           where sign(a.predicted_value_30 - b.predicted_value_30)
               = sign(ta.target - tb.target)
         )::integer as correct_pairs
  from goal_predictions a
  join goal_predictions b
    on b.season_id = a.season_id
   and b.predictor_profile_id = a.predictor_profile_id
   and a.season_player_id < b.season_player_id
  join target_goals ta
    on ta.season_id = a.season_id
   and ta.season_player_id = a.season_player_id
  join target_goals tb
    on tb.season_id = b.season_id
   and tb.season_player_id = b.season_player_id
  where ta.target is not null
    and tb.target is not null
  group by a.season_id, a.predictor_profile_id
)
select ps.season_id,
       ps.predictor_profile_id,
       case
         when ps.total_pairs = 0
           or ps.correct_pairs * 2 <= ps.total_pairs then 0
         else least(
           pc.participant_count * 30,
           round(
             pc.participant_count::numeric
             * 30.0
             * (2 * ps.correct_pairs - ps.total_pairs)::numeric
             / ps.total_pairs::numeric
           )::integer
         )
       end as bonus_points
from pair_scores ps
join participant_count pc on pc.season_id = ps.season_id;

alter view public.v_season_prediction_bonus set (security_invoker = true);
revoke all privileges on table public.v_season_prediction_bonus from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_bonus from authenticated;
grant select on table public.v_season_prediction_bonus to authenticated;

create or replace view public.v_classement_general as
with match_totals as (
  select profile_id, coalesce(sum(points), 0::numeric) as match_points
  from public.v_match_prediction_points
  group by profile_id
), match_flags as (
  select profile_id,
         coalesce(sum(bon_pari), 0) as match_bons,
         coalesce(sum(exact), 0) as match_exacts
  from public.v_match_prediction_flags
  group by profile_id
), season_totals as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points), 0::bigint)::numeric as season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
), season_bonus as (
  select predictor_profile_id as profile_id,
         coalesce(sum(bonus_points), 0::bigint)::numeric as bonus_points
  from public.v_season_prediction_bonus
  group by predictor_profile_id
), season_flags as (
  select predictor_profile_id as profile_id,
         coalesce(sum(bon_pari), 0) as season_bons,
         coalesce(sum(exact), 0) as season_exacts
  from public.v_season_prediction_flags
  group by predictor_profile_id
), totals as (
  select p.id as profile_id,
         p.first_name,
         p.surnom,
         coalesce(mt.match_points, 0::numeric) as match_points,
         coalesce(st.season_points, 0::numeric)
           + coalesce(sb.bonus_points, 0::numeric) as season_points,
         coalesce(mf.match_bons, 0) as match_bons,
         coalesce(mf.match_exacts, 0) as match_exacts,
         coalesce(sf.season_bons, 0) as season_bons,
         coalesce(sf.season_exacts, 0) as season_exacts
  from public.profiles p
  left join match_totals mt on mt.profile_id = p.id
  left join match_flags mf on mf.profile_id = p.id
  left join season_totals st on st.profile_id = p.id
  left join season_bonus sb on sb.profile_id = p.id
  left join season_flags sf on sf.profile_id = p.id
  where p.status = 'active'
)
select profile_id,
       first_name,
       surnom,
       match_points,
       season_points,
       match_points + season_points as total_points,
       match_bons,
       match_exacts,
       season_bons,
       season_exacts
from totals;

alter view public.v_classement_general set (security_invoker = true);
revoke all privileges on table public.v_classement_general from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_classement_general from authenticated;
grant select on table public.v_classement_general to authenticated;