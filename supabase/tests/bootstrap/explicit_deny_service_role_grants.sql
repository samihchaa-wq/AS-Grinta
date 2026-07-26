-- La base isolée est créée par le rôle postgres, contrairement à Supabase
-- hébergé où service_role reçoit les privilèges nécessaires. Ce bootstrap aligne
-- uniquement les privilèges de l’environnement de test sur la production.

grant all on table
  private.app_feature_flag_audit,
  private.app_feature_flags,
  private.sport_admin_audit_log,
  public.historical_match_scores,
  public.match_composition_entries,
  public.match_compositions,
  public.match_sport_finalization_versions,
  public.match_sport_finalizations,
  public.match_sport_motm_elections,
  public.match_sport_motm_results,
  public.match_sport_motm_votes,
  public.sport_availability_notification_events
to service_role;
