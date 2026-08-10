
-- Le create-or-replace de la migration précédente a réinitialisé l'option
-- security_invoker de la vue (retombée en SECURITY DEFINER par défaut, signalée
-- ERROR par le linter). On restaure security_invoker=true pour aligner la vue
-- sur ses sœurs (v_season_prediction_flags/_bonus, v_match_prediction_points,
-- v_classement_general) : la vue applique alors les droits + RLS de
-- l'utilisateur qui l'interroge.
alter view public.v_season_prediction_points set (security_invoker = true);
;
