begin;

-- Retour à l'état antérieur : RLS reste activée et l'absence de politique
-- continue de refuser implicitement les rôles clients.
do $$
declare
  target record;
begin
  for target in
    select *
    from (values
      ('private', 'app_feature_flag_audit'),
      ('private', 'app_feature_flags'),
      ('private', 'sport_admin_audit_log'),
      ('public', 'historical_match_scores'),
      ('public', 'match_composition_entries'),
      ('public', 'match_compositions'),
      ('public', 'match_sport_finalization_versions'),
      ('public', 'match_sport_finalizations'),
      ('public', 'match_sport_motm_elections'),
      ('public', 'match_sport_motm_results'),
      ('public', 'match_sport_motm_votes'),
      ('public', 'sport_availability_notification_events')
    ) as targets(schema_name, table_name)
  loop
    execute format(
      'drop policy if exists deny_client_access on %I.%I',
      target.schema_name,
      target.table_name
    );
  end loop;
end
$$;

commit;
