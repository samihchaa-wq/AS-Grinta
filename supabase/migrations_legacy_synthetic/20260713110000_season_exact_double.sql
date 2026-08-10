-- Pronostics de saison : si un pronostiqueur trouve le nombre exact de buts /
-- clean sheets projeté d'un joueur, ses points sur ce joueur sont doublés (x2).
-- Le reste du barème (classement par proximité) est inchangé.
create or replace view v_season_prediction_points as
  WITH base AS (
    SELECT sp.id,
      sp.season_id,
      sp.predictor_profile_id,
      sp.season_player_id,
      sp.category,
      sp.predicted_value_30,
      CASE sp.category
        WHEN 'buts'::text THEN st.goals
        WHEN 'clean_sheets'::text THEN st.clean_sheets
        ELSE 0
      END AS metric,
      s.status AS season_status,
      mc.matches_played
    FROM season_predictions sp
      JOIN seasons s ON s.id = sp.season_id
      JOIN v_player_season_stats st ON st.season_player_id = sp.season_player_id
      LEFT JOIN v_season_match_count mc ON mc.season_id = sp.season_id
    WHERE sp.is_filled
      AND (sp.category = ANY (ARRAY['buts'::text, 'clean_sheets'::text]))
      AND (s.season_predictions_locked_at IS NOT NULL OR s.status = 'archived'::text)
  ), targeted AS (
    SELECT base.id,
      base.season_id,
      base.predictor_profile_id,
      base.season_player_id,
      base.category,
      base.predicted_value_30,
      base.metric,
      base.season_status,
      base.matches_played,
      CASE
        WHEN base.season_status = 'archived'::text THEN base.metric::numeric
        WHEN COALESCE(base.matches_played, 0) > 0
          THEN round(base.metric::numeric * 30.0 / base.matches_played::numeric)
        ELSE NULL::numeric
      END AS target
    FROM base
  )
  SELECT id,
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    (
      (count(*) OVER (PARTITION BY season_id, season_player_id, category)
        - (rank() OVER (PARTITION BY season_id, season_player_id, category
            ORDER BY (abs(predicted_value_30::numeric - target))) - 1))
      * CASE WHEN predicted_value_30::numeric = target THEN 2 ELSE 1 END
    )::integer AS points
  FROM targeted
  WHERE target IS NOT NULL;
