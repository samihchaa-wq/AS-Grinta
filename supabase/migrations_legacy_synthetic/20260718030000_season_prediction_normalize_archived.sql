-- Pronos joueurs : les stats réelles sont toujours ramenées sur une base de
-- 30 matchs pour être comparées aux pronostics (eux-mêmes exprimés sur 30).
-- Avant, une saison ARCHIVÉE comparait au total brut (non normalisé), ce qui
-- faussait les points si la saison ne faisait pas exactement 30 matchs. On
-- applique désormais la même normalisation, en cours comme archivée.
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
                end as metric,
            es.status as season_status,
            mc.matches_played
           from season_predictions sp
             join eligible_predictors ep on ep.season_id = sp.season_id and ep.predictor_profile_id = sp.predictor_profile_id
             join eligible_seasons es on es.id = sp.season_id
             join v_player_season_stats st on st.season_player_id = sp.season_player_id
             left join v_season_match_count mc on mc.season_id = sp.season_id
          where sp.is_filled and (sp.category = any (array['buts'::text, 'clean_sheets'::text]))
        ), targeted as (
         select base.id,
            base.season_id,
            base.predictor_profile_id,
            base.season_player_id,
            base.category,
            base.predicted_value_30,
            base.metric,
            base.season_status,
            base.matches_played,
                case
                    when coalesce(base.matches_played, 0) > 0 then round(base.metric::numeric * 30.0 / base.matches_played::numeric)
                    else null::numeric
                end as target
           from base
        ), ranked as (
         select targeted.id,
            targeted.season_id,
            targeted.predictor_profile_id,
            targeted.season_player_id,
            targeted.category,
            targeted.predicted_value_30,
            targeted.metric,
            targeted.season_status,
            targeted.matches_played,
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
