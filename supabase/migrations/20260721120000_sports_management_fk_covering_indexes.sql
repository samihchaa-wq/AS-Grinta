-- Index de couverture des clés étrangères des tables « sports_management ».
--
-- Les nouvelles tables ajoutées lors du chantier de gestion sportive (feuille
-- de match, compositions, MOTM, disponibilités, liste d'attente, journaux
-- d'audit) déclarent de nombreuses clés étrangères sans index de couverture.
-- Sans index, chaque UPDATE/DELETE sur la table référencée impose un scan
-- séquentiel de la table référençante pour vérifier la contrainte, et les
-- jointures sur ces colonnes sont lentes. Le linter Supabase (advisor
-- `unindexed_foreign_keys`) les signalait toutes.
--
-- On crée un index B-tree par clé étrangère non couverte. `if not exists` rend
-- la migration ré-exécutable ; les noms trop longs sont tronqués à 63 octets
-- par Postgres de façon déterministe, ce qui reste idempotent.

-- private.app_feature_flag_audit
create index if not exists idx_app_feature_flag_audit_actor_profile_id on private.app_feature_flag_audit (actor_profile_id);
create index if not exists idx_app_feature_flag_audit_feature_key on private.app_feature_flag_audit (feature_key);

-- private.app_feature_flags
create index if not exists idx_app_feature_flags_updated_by on private.app_feature_flags (updated_by);

-- private.sport_admin_audit_log
create index if not exists idx_sport_admin_audit_log_actor_profile_id on private.sport_admin_audit_log (actor_profile_id);

-- public.guest_players
create index if not exists idx_guest_players_created_by on public.guest_players (created_by);
create index if not exists idx_guest_players_updated_by on public.guest_players (updated_by);

-- public.match_composition_entries
create index if not exists idx_match_composition_entries_participant_id_match_id on public.match_composition_entries (participant_id, match_id);

-- public.match_composition_publications
create index if not exists idx_match_composition_publications_published_by on public.match_composition_publications (published_by);

-- public.match_compositions
create index if not exists idx_match_compositions_last_modified_by on public.match_compositions (last_modified_by);
create index if not exists idx_match_compositions_published_by on public.match_compositions (published_by);

-- public.match_sport_finalization_versions
create index if not exists idx_match_sport_finalization_versions_created_by on public.match_sport_finalization_versions (created_by);

-- public.match_sport_finalizations
create index if not exists idx_match_sport_finalizations_corrected_by on public.match_sport_finalizations (corrected_by);
create index if not exists idx_match_sport_finalizations_validated_by on public.match_sport_finalizations (validated_by);

-- public.match_sport_motm_results
create index if not exists idx_match_sport_motm_results_participant_id_match_id on public.match_sport_motm_results (participant_id, match_id);

-- public.match_sport_motm_votes
create index if not exists idx_match_sport_motm_votes_candidate_participant_id_match_id on public.match_sport_motm_votes (candidate_participant_id, match_id);
create index if not exists idx_match_sport_motm_votes_voter_profile_id on public.match_sport_motm_votes (voter_profile_id);

-- public.match_sport_participant_events
create index if not exists idx_match_sport_participant_events_actor_profile_id on public.match_sport_participant_events (actor_profile_id);
create index if not exists idx_match_sport_participant_events_participant_id_match_id on public.match_sport_participant_events (participant_id, match_id);

-- public.match_sport_participants
create index if not exists idx_match_sport_participants_availability_updated_by on public.match_sport_participants (availability_updated_by);
create index if not exists idx_match_sport_participants_final_presence_confirmed_by on public.match_sport_participants (final_presence_confirmed_by);
create index if not exists idx_match_sport_participants_promoted_from_participant_id on public.match_sport_participants (promoted_from_participant_id);
create index if not exists idx_match_sport_participants_selection_updated_by on public.match_sport_participants (selection_updated_by);

-- public.match_sport_workflows
create index if not exists idx_match_sport_workflows_created_by on public.match_sport_workflows (created_by);
create index if not exists idx_match_sport_workflows_updated_by on public.match_sport_workflows (updated_by);

-- public.sport_availability_notification_events
create index if not exists idx_sport_availability_notification_events_participant_id_match_id on public.sport_availability_notification_events (participant_id, match_id);
create index if not exists idx_sport_availability_notification_events_requested_by on public.sport_availability_notification_events (requested_by);

-- public.sport_waitlist_entries
create index if not exists idx_sport_waitlist_entries_created_by on public.sport_waitlist_entries (created_by);
create index if not exists idx_sport_waitlist_entries_season_player_id_season_id on public.sport_waitlist_entries (season_player_id, season_id);
create index if not exists idx_sport_waitlist_entries_updated_by on public.sport_waitlist_entries (updated_by);
