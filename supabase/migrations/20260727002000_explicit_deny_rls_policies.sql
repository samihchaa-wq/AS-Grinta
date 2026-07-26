begin;

-- Ces tables étaient déjà fermées aux rôles clients : RLS était activée,
-- aucun privilège n'était accordé et l'absence de politique produisait un refus
-- implicite. Une politique restrictive explicite rend cette intention durable,
-- vérifiable et visible dans les conseillers Supabase.
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
      'alter table %I.%I enable row level security',
      target.schema_name,
      target.table_name
    );
    execute format(
      'drop policy if exists deny_client_access on %I.%I',
      target.schema_name,
      target.table_name
    );
    execute format(
      'create policy deny_client_access on %I.%I as restrictive for all to anon, authenticated using (false) with check (false)',
      target.schema_name,
      target.table_name
    );
  end loop;
end
$$;

commit;
