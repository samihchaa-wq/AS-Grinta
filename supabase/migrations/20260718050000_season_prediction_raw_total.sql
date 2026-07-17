-- Simplification : on parie le TOTAL du joueur sur la saison, comparé au total
-- réel — sans normalisation « sur 30 matchs » ni projection. Peu importe le
-- nombre de matchs de la saison.
create or replace view public.v_season_prediction_points as
 with eligible_seasons as (
         select seasons.id,
            seasons.status
           from seasons
          where seasons.season_predictions_locked_at is not null or seasons.status = 'archived'::text
        ), expected_predictions as (
         select sp.season_id,
            count(*) as expected_count
           from season_players sp
             join eligible_seasons es on es.id = sp.season_id
          group by sp.season_id
        ), predictor_completion as (
         select sp.season_id,
            sp.predictor_profile_id,
            count(*) filter (where sp.is_filled and (sp.category = any (array['buts'::text, 'clean_sheets'::text]))) as filled_count
           from season_predictions sp
             join eligible_seasons es on es.id = sp.season_id
          group by sp.season_id, sp.predictor_profile_id
        ), eligible_predictors as (
         select pc.season_id,
            pc.predictor_profile_id
           from predictor_completion pc
             join expected_predictions ep on ep.season_id = pc.season_id
          where ep.expected_count > 0 and pc.filled_count = ep.expected_count
        ), base as (
         select sp.id,
            sp.season_id,
            sp.predictor_profile_id,
            sp.season_player_id,
            sp.category,
            sp.predicted_value_30,
                case sp.category
                    when 'buts'::text then st.goals
                    when 'clean_sheets'::text then st.clean_sheets
                    else 0
                end as metric
           from season_predictions sp
             join eligible_predictors ep on ep.season_id = sp.season_id and ep.predictor_profile_id = sp.predictor_profile_id
             join eligible_seasons es on es.id = sp.season_id
             join v_player_season_stats st on st.season_player_id = sp.season_player_id
          where sp.is_filled and (sp.category = any (array['buts'::text, 'clean_sheets'::text]))
        ), targeted as (
         select base.id,
            base.season_id,
            base.predictor_profile_id,
            base.season_player_id,
            base.category,
            base.predicted_value_30,
            base.metric,
            base.metric::numeric as target
           from base
        ), ranked as (
         select targeted.id,
            targeted.season_id,
            targeted.predictor_profile_id,
            targeted.season_player_id,
            targeted.category,
            targeted.predicted_value_30,
            targeted.target,
            count(*) over (partition by targeted.season_id, targeted.season_player_id, targeted.category) as participant_count,
            rank() over (partition by targeted.season_id, targeted.season_player_id, targeted.category order by (abs(targeted.predicted_value_30::numeric - targeted.target))) as proximity_rank
           from targeted
          where targeted.target is not null
        )
 select id,
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    ((participant_count - proximity_rank + 1) * 3 *
        case
            when predicted_value_30::numeric = target then 2
            else 1
        end)::integer as points
   from ranked;

-- Bonus « bon ordre des buteurs » : ordre basé sur les buts RÉELS (bruts).
create or replace view public.v_season_prediction_bonus as
 with eligible_seasons as (
         select seasons.id,
            seasons.status
           from seasons
          where seasons.season_predictions_locked_at is not null or seasons.status = 'archived'::text
        ), expected_predictions as (
         select sp.season_id,
            count(*) as expected_count
           from season_players sp
             join eligible_seasons es on es.id = sp.season_id
          group by sp.season_id
        ), predictor_completion as (
         select sp.season_id,
            sp.predictor_profile_id,
            count(*) filter (where sp.is_filled and (sp.category = any (array['buts'::text, 'clean_sheets'::text]))) as filled_count
           from season_predictions sp
             join eligible_seasons es on es.id = sp.season_id
          group by sp.season_id, sp.predictor_profile_id
        ), eligible_predictors as (
         select pc_1.season_id,
            pc_1.predictor_profile_id
           from predictor_completion pc_1
             join expected_predictions ep on ep.season_id = pc_1.season_id
          where ep.expected_count > 0 and pc_1.filled_count = ep.expected_count
        ), participant_count as (
         select eligible_predictors.season_id,
            count(*)::integer as participant_count
           from eligible_predictors
          group by eligible_predictors.season_id
        ), target_goals as (
         select pl.season_id,
            pl.id as season_player_id,
            st.goals::numeric as target
           from season_players pl
             join eligible_seasons es on es.id = pl.season_id
             join v_player_season_stats st on st.season_player_id = pl.id
          where not pl.is_goalkeeper
        ), goal_predictions as (
         select sp.season_id,
            sp.predictor_profile_id,
            sp.season_player_id,
            sp.predicted_value_30
           from season_predictions sp
             join eligible_predictors ep on ep.season_id = sp.season_id and ep.predictor_profile_id = sp.predictor_profile_id
             join season_players pl on pl.id = sp.season_player_id
          where sp.category = 'buts'::text and sp.is_filled and not pl.is_goalkeeper
        ), pair_scores as (
         select a.season_id,
            a.predictor_profile_id,
            count(*)::integer as total_pairs,
            count(*) filter (where sign((a.predicted_value_30 - b.predicted_value_30)::double precision) = sign(ta.target - tb.target)::double precision)::integer as correct_pairs
           from goal_predictions a
             join goal_predictions b on b.season_id = a.season_id and b.predictor_profile_id = a.predictor_profile_id and a.season_player_id < b.season_player_id
             join target_goals ta on ta.season_id = a.season_id and ta.season_player_id = a.season_player_id
             join target_goals tb on tb.season_id = b.season_id and tb.season_player_id = b.season_player_id
          where ta.target is not null and tb.target is not null
          group by a.season_id, a.predictor_profile_id
        )
 select ps.season_id,
    ps.predictor_profile_id,
        case
            when ps.total_pairs = 0 or (ps.correct_pairs * 2) <= ps.total_pairs then 0
            else least(pc.participant_count * 30, round(pc.participant_count::numeric * 30.0 * (2 * ps.correct_pairs - ps.total_pairs)::numeric / ps.total_pairs::numeric)::integer)
        end as bonus_points
   from pair_scores ps
     join participant_count pc on pc.season_id = ps.season_id;
