create or replace view v_match_prediction_points as
  SELECT mp.id, mp.match_id, mp.profile_id,
    CASE
      WHEN NOT mp.is_filled THEN 0::numeric
      WHEN sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
           <> sign((m.score_as_grinta - m.score_adverse)::numeric) THEN 0::numeric
      ELSE
        CASE
          WHEN m.score_as_grinta > m.score_adverse THEN mo.odds_victoire_as_grinta
          WHEN m.score_as_grinta = m.score_adverse THEN mo.odds_nul
          ELSE mo.odds_victoire_adverse
        END *
        CASE
          WHEN mp.predicted_score_as_grinta = m.score_as_grinta
               AND mp.predicted_score_adverse = m.score_adverse THEN 2
          WHEN (mp.predicted_score_as_grinta - mp.predicted_score_adverse)
               = (m.score_as_grinta - m.score_adverse) THEN 1.5
          WHEN mp.predicted_score_as_grinta = m.score_as_grinta
               OR mp.predicted_score_adverse = m.score_adverse THEN 1.5
          ELSE 1
        END::numeric
    END AS points
  FROM match_predictions mp
    JOIN matches m ON m.id = mp.match_id
      AND (m.status = ANY (ARRAY['termine'::text, 'archive'::text]))
    JOIN match_odds mo ON mo.match_id = m.id;;
