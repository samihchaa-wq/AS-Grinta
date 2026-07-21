-- Le create-or-replace de 20260721130000 a réinitialisé l'option
-- security_invoker de v_season_prediction_points (retombée en SECURITY DEFINER
-- par défaut, signalée ERROR par l'advisor `security_definer_view`). On restaure
-- security_invoker=true pour aligner la vue sur ses sœurs
-- (v_season_prediction_flags/_bonus, v_match_prediction_points,
-- v_classement_general) : la vue applique ainsi les droits + RLS de
-- l'utilisateur qui l'interroge, et non ceux de son créateur.
alter view public.v_season_prediction_points set (security_invoker = true);
