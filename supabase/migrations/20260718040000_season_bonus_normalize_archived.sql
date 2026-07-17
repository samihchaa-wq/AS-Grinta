-- Cohérence avec v_season_prediction_points : le bonus « bon ordre des buteurs »
-- normalise lui aussi les buts réels sur une base de 30 matchs, saison en cours
-- comme archivée (évite les cas limites d'arrondi qui pourraient inverser un
-- ex æquo).
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
                case
                    when coalesce(mc.matches_played, 0) > 0 then round(st.goals::numeric * 30.0 / mc.matches_played::numeric)
                    else null::numeric
                end as target
           from season_players pl
             join eligible_seasons es on es.id = pl.season_id
             join v_player_season_stats st on st.season_player_id = pl.id
             left join v_season_match_count mc on mc.season_id = pl.season_id
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
