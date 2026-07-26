-- Pré-requis minimal pour les politiques RLS explicites et leur matrice de test.
-- La base locale est créée par postgres ; on aligne également les privilèges du
-- service interne sur ceux du projet Supabase hébergé.

create table if not exists public.historical_match_scores (
  id uuid primary key,
  opponent_id uuid not null references public.opponents(id) on delete restrict,
  match_date date not null,
  score_as_grinta smallint not null check (score_as_grinta between 0 and 99),
  score_adverse smallint not null check (score_adverse between 0 and 99)
);

revoke all on public.historical_match_scores from anon, authenticated;

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
