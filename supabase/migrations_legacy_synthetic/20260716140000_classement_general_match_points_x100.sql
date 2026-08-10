-- Le cumulé (total_points) doit additionner les points matchs À LA MÊME
-- ÉCHELLE que ceux affichés (×100) + les points saison. Avant, il ajoutait
-- les points matchs bruts (ex. 14,90) au lieu de 1490, ce qui rendait le
-- classement Général quasi identique au classement Saison.
create or replace view public.v_classement_general as
 WITH match_totals AS (
         SELECT v_match_prediction_points.profile_id,
            COALESCE(sum(v_match_prediction_points.points), 0::numeric) AS match_points
           FROM v_match_prediction_points
          GROUP BY v_match_prediction_points.profile_id
        ), match_flags AS (
         SELECT v_match_prediction_flags.profile_id,
            COALESCE(sum(v_match_prediction_flags.bon_pari), 0::bigint) AS match_bons,
            COALESCE(sum(v_match_prediction_flags.exact), 0::bigint) AS match_exacts
           FROM v_match_prediction_flags
          GROUP BY v_match_prediction_flags.profile_id
        ), season_totals AS (
         SELECT v_season_prediction_points.predictor_profile_id AS profile_id,
            COALESCE(sum(v_season_prediction_points.points), 0::bigint)::numeric AS season_points
           FROM v_season_prediction_points
          GROUP BY v_season_prediction_points.predictor_profile_id
        ), season_bonus AS (
         SELECT v_season_prediction_bonus.predictor_profile_id AS profile_id,
            COALESCE(sum(v_season_prediction_bonus.bonus_points), 0::bigint)::numeric AS bonus_points
           FROM v_season_prediction_bonus
          GROUP BY v_season_prediction_bonus.predictor_profile_id
        ), season_flags AS (
         SELECT v_season_prediction_flags.predictor_profile_id AS profile_id,
            COALESCE(sum(v_season_prediction_flags.bon_pari), 0::bigint) AS season_bons,
            COALESCE(sum(v_season_prediction_flags.exact), 0::bigint) AS season_exacts
           FROM v_season_prediction_flags
          GROUP BY v_season_prediction_flags.predictor_profile_id
        ), totals AS (
         SELECT p.id AS profile_id,
            p.first_name,
            p.surnom,
            COALESCE(mt.match_points, 0::numeric) AS match_points,
            COALESCE(st.season_points, 0::numeric) + COALESCE(sb.bonus_points, 0::numeric) AS season_points,
            COALESCE(mf.match_bons, 0::bigint) AS match_bons,
            COALESCE(mf.match_exacts, 0::bigint) AS match_exacts,
            COALESCE(sf.season_bons, 0::bigint) AS season_bons,
            COALESCE(sf.season_exacts, 0::bigint) AS season_exacts
           FROM profiles p
             LEFT JOIN match_totals mt ON mt.profile_id = p.id
             LEFT JOIN match_flags mf ON mf.profile_id = p.id
             LEFT JOIN season_totals st ON st.profile_id = p.id
             LEFT JOIN season_bonus sb ON sb.profile_id = p.id
             LEFT JOIN season_flags sf ON sf.profile_id = p.id
          WHERE p.status = 'active'::text
        )
 SELECT profile_id,
    first_name,
    surnom,
    match_points,
    season_points,
    match_points * 100 + season_points AS total_points,
    match_bons,
    match_exacts,
    season_bons,
    season_exacts
   FROM totals;
