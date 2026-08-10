-- 1) Retirer l'exécution des fonctions aux visiteurs non connectés
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

-- 2) Garantir l'accès aux utilisateurs connectés et au backend
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- 3) Les fonctions trigger ne doivent être appelables par personne via l'API
REVOKE EXECUTE ON FUNCTION public.apply_substitution_to_positions() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_match_odds_after_insert() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_live_session_update() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_sensitive_profile_fields() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_match_predictions() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_predictions_for_active_profile() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_season_predictions_for_player() FROM authenticated;

-- 4) Les futures fonctions ne seront pas exécutables par défaut par tout le monde
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;;
