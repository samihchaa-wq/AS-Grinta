-- Points arrondis à l'entier supérieur (ceil) + statistiques de classement
-- « Bons paris » et « Exacts » pour les matchs et la saison.
--
-- Rappel barème match : le score exact vaut cote × 20, le bon vainqueur seul
-- cote × 10 — l'exact vaut donc déjà le double (x2) du bon vainqueur.
-- On se contente d'arrondir les points au supérieur.

-- 1) Points de match arrondis à l'entier supérieur.
create or replace view v_match_prediction_points as
  SELECT mp.id,
    mp.match_id,
    mp.profile_id,
    CASE
      WHEN NOT mp.is_filled THEN 0::numeric
      WHEN sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
           <> sign((m.score_as_grinta - m.score_adverse)::numeric) THEN 0::numeric
      ELSE ceil(
        CASE
          WHEN m.score_as_grinta > m.score_adverse THEN mo.odds_victoire_as_grinta
          WHEN m.score_as_grinta = m.score_adverse THEN mo.odds_nul
          ELSE mo.odds_victoire_adverse
        END *
        CASE
          WHEN mp.predicted_score_as_grinta = m.score_as_grinta
               AND mp.predicted_score_adverse = m.score_adverse THEN 20
          WHEN (mp.predicted_score_as_grinta - mp.predicted_score_adverse)
               = (m.score_as_grinta - m.score_adverse) THEN 15
          WHEN mp.predicted_score_as_grinta = m.score_as_grinta
               OR mp.predicted_score_adverse = m.score_adverse THEN 15
          ELSE 10
        END::numeric
      )
    END AS points
  FROM match_predictions mp
    JOIN matches m ON m.id = mp.match_id
      AND (m.status = ANY (ARRAY['termine'::text, 'archive'::text]))
    JOIN match_odds mo ON mo.match_id = m.id;

-- 2) Drapeaux match : bon pari (bon vainqueur) et score exact, par pronostic.
create or replace view v_match_prediction_flags as
  SELECT mp.profile_id,
    (mp.is_filled
      AND sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int AS bon_pari,
    (mp.is_filled
      AND mp.predicted_score_as_grinta = m.score_as_grinta
      AND mp.predicted_score_adverse = m.score_adverse)::int AS exact
  FROM match_predictions mp
    JOIN matches m ON m.id = mp.match_id
      AND (m.status = ANY (ARRAY['termine'::text, 'archive'::text]));

-- 3) Drapeaux saison : bon pari (le plus proche, égalités comprises) et exact
--    (bon nombre de buts / clean sheets projeté), par pronostic.
create or replace view v_season_prediction_flags as
  WITH base AS (
    SELECT sp.season_id,
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
    SELECT base.*,
      CASE
        WHEN base.season_status = 'archived'::text THEN base.metric::numeric
        WHEN COALESCE(base.matches_played, 0) > 0
          THEN round(base.metric::numeric * 30.0 / base.matches_played::numeric)
        ELSE NULL::numeric
      END AS target
    FROM base
  ), ranked AS (
    SELECT targeted.*,
      rank() OVER (
        PARTITION BY season_id, season_player_id, category
        ORDER BY abs(predicted_value_30::numeric - target)
      ) AS closeness_rank
    FROM targeted
    WHERE target IS NOT NULL
  )
  SELECT season_id,
    predictor_profile_id,
    (closeness_rank = 1)::int AS bon_pari,
    (predicted_value_30::numeric = target)::int AS exact
  FROM ranked;

-- 4) Classement général enrichi : colonnes Bons paris / Exacts + total arrondi
--    à l'entier supérieur.
create or replace view v_classement_general as
  WITH mt AS (
    SELECT profile_id, COALESCE(sum(points), 0::numeric) AS match_points
    FROM v_match_prediction_points
    GROUP BY profile_id
  ), mf AS (
    SELECT profile_id,
      COALESCE(sum(bon_pari), 0) AS match_bons,
      COALESCE(sum(exact), 0) AS match_exacts
    FROM v_match_prediction_flags
    GROUP BY profile_id
  ), sp AS (
    SELECT predictor_profile_id AS profile_id,
      COALESCE(sum(points), 0::bigint)::numeric AS season_points
    FROM v_season_prediction_points
    GROUP BY predictor_profile_id
  ), bn AS (
    SELECT predictor_profile_id AS profile_id,
      COALESCE(sum(bonus_points), 0::bigint)::numeric AS bonus_points
    FROM v_season_prediction_bonus
    GROUP BY predictor_profile_id
  ), sf AS (
    SELECT predictor_profile_id AS profile_id,
      COALESCE(sum(bon_pari), 0) AS season_bons,
      COALESCE(sum(exact), 0) AS season_exacts
    FROM v_season_prediction_flags
    GROUP BY predictor_profile_id
  ), tot AS (
    SELECT p.id AS profile_id,
      p.first_name,
      p.surnom,
      COALESCE(mt.match_points, 0::numeric) AS match_points,
      COALESCE(sp.season_points, 0::numeric) + COALESCE(bn.bonus_points, 0::numeric) AS season_points,
      COALESCE(mf.match_bons, 0) AS match_bons,
      COALESCE(mf.match_exacts, 0) AS match_exacts,
      COALESCE(sf.season_bons, 0) AS season_bons,
      COALESCE(sf.season_exacts, 0) AS season_exacts
    FROM profiles p
      LEFT JOIN mt ON mt.profile_id = p.id
      LEFT JOIN mf ON mf.profile_id = p.id
      LEFT JOIN sp ON sp.profile_id = p.id
      LEFT JOIN bn ON bn.profile_id = p.id
      LEFT JOIN sf ON sf.profile_id = p.id
    WHERE p.status = 'active'::text
  ), mx AS (
    SELECT max(match_points) AS mm, max(season_points) AS ms FROM tot
  )
  -- NB : les 6 premières colonnes gardent leur ordre historique (create or
  -- replace l'exige) ; les nouvelles colonnes sont ajoutées à la fin.
  SELECT t.profile_id,
    t.first_name,
    t.surnom,
    t.match_points,
    t.season_points,
    ceil(
      70::numeric * CASE WHEN mx.mm > 0::numeric THEN t.match_points / mx.mm ELSE 0::numeric END
      + 30::numeric * CASE WHEN mx.ms > 0::numeric THEN t.season_points / mx.ms ELSE 0::numeric END
    ) AS total_points,
    t.match_bons,
    t.match_exacts,
    t.season_bons,
    t.season_exacts
  FROM tot t CROSS JOIN mx;

grant select on v_match_prediction_flags to anon, authenticated;
grant select on v_season_prediction_flags to anon, authenticated;
