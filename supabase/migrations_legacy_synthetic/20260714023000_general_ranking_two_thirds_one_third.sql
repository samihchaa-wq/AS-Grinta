-- Classement général : 2/3 pronostics de matchs, 1/3 pronostics de saison.
-- Les barèmes bruts restent strictement inchangés ; seule la pondération finale
-- des deux scores normalisés est modifiée.

create or replace view public.v_classement_general as
  WITH mt AS (
    SELECT profile_id, COALESCE(sum(points), 0::numeric) AS match_points
    FROM public.v_match_prediction_points
    GROUP BY profile_id
  ), mf AS (
    SELECT profile_id,
      COALESCE(sum(bon_pari), 0) AS match_bons,
      COALESCE(sum(exact), 0) AS match_exacts
    FROM public.v_match_prediction_flags
    GROUP BY profile_id
  ), sp AS (
    SELECT predictor_profile_id AS profile_id,
      COALESCE(sum(points), 0::bigint)::numeric AS season_points
    FROM public.v_season_prediction_points
    GROUP BY predictor_profile_id
  ), bn AS (
    SELECT predictor_profile_id AS profile_id,
      COALESCE(sum(bonus_points), 0::bigint)::numeric AS bonus_points
    FROM public.v_season_prediction_bonus
    GROUP BY predictor_profile_id
  ), sf AS (
    SELECT predictor_profile_id AS profile_id,
      COALESCE(sum(bon_pari), 0) AS season_bons,
      COALESCE(sum(exact), 0) AS season_exacts
    FROM public.v_season_prediction_flags
    GROUP BY predictor_profile_id
  ), tot AS (
    SELECT p.id AS profile_id,
      p.first_name,
      p.surnom,
      COALESCE(mt.match_points, 0::numeric) AS match_points,
      COALESCE(sp.season_points, 0::numeric)
        + COALESCE(bn.bonus_points, 0::numeric) AS season_points,
      COALESCE(mf.match_bons, 0) AS match_bons,
      COALESCE(mf.match_exacts, 0) AS match_exacts,
      COALESCE(sf.season_bons, 0) AS season_bons,
      COALESCE(sf.season_exacts, 0) AS season_exacts
    FROM public.profiles p
      LEFT JOIN mt ON mt.profile_id = p.id
      LEFT JOIN mf ON mf.profile_id = p.id
      LEFT JOIN sp ON sp.profile_id = p.id
      LEFT JOIN bn ON bn.profile_id = p.id
      LEFT JOIN sf ON sf.profile_id = p.id
    WHERE p.status = 'active'::text
  ), mx AS (
    SELECT max(match_points) AS mm, max(season_points) AS ms FROM tot
  )
  SELECT t.profile_id,
    t.first_name,
    t.surnom,
    t.match_points,
    t.season_points,
    ceil(
      100::numeric * (2::numeric / 3::numeric)
        * CASE
            WHEN mx.mm > 0::numeric THEN t.match_points / mx.mm
            ELSE 0::numeric
          END
      + 100::numeric * (1::numeric / 3::numeric)
        * CASE
            WHEN mx.ms > 0::numeric THEN t.season_points / mx.ms
            ELSE 0::numeric
          END
    ) AS total_points,
    t.match_bons,
    t.match_exacts,
    t.season_bons,
    t.season_exacts
  FROM tot t CROSS JOIN mx;

alter view public.v_classement_general set (security_invoker = true);

revoke all privileges on table public.v_classement_general from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_classement_general
  from authenticated;
grant select on table public.v_classement_general to authenticated;
