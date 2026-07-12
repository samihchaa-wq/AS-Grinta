-- Les vues de statistiques et de classement doivent respecter la RLS de
-- l'utilisateur qui les interroge (et non celle du créateur). Toutes les
-- tables sous-jacentes autorisent déjà la lecture aux comptes authentifiés.
alter view public.v_player_season_stats set (security_invoker = true);
alter view public.v_scorer_standings set (security_invoker = true);
alter view public.v_season_match_count set (security_invoker = true);
alter view public.v_season_prediction_points set (security_invoker = true);
alter view public.v_season_prediction_bonus set (security_invoker = true);
alter view public.v_classement_general set (security_invoker = true);
