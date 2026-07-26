begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table audited_rls_targets (
  schema_name text not null,
  table_name text not null
) on commit drop;

insert into audited_rls_targets(schema_name, table_name)
values
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
  ('public', 'sport_availability_notification_events');

select is(
  (
    select count(*)
    from audited_rls_targets target
    join pg_namespace namespace
      on namespace.nspname = target.schema_name
    join pg_class relation
      on relation.relnamespace = namespace.oid
     and relation.relname = target.table_name
     and relation.relkind = 'r'
    where relation.relrowsecurity
  ),
  12::bigint,
  'RLS reste activée sur les douze tables internes'
);

select is(
  (
    select count(*)
    from audited_rls_targets target
    join pg_policies policy
      on policy.schemaname = target.schema_name
     and policy.tablename = target.table_name
    where policy.policyname = 'deny_client_access'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'ALL'
      and policy.roles @> array['anon', 'authenticated']::name[]
      and regexp_replace(coalesce(policy.qual, ''), '[()[:space:]]', '', 'g') = 'false'
      and regexp_replace(coalesce(policy.with_check, ''), '[()[:space:]]', '', 'g') = 'false'
  ),
  12::bigint,
  'chaque table possède une politique restrictive de refus client'
);

select is(
  (
    select count(*)
    from audited_rls_targets target
    where has_table_privilege(
      'anon',
      format('%I.%I', target.schema_name, target.table_name),
      'SELECT,INSERT,UPDATE,DELETE'
    )
    or has_table_privilege(
      'authenticated',
      format('%I.%I', target.schema_name, target.table_name),
      'SELECT,INSERT,UPDATE,DELETE'
    )
  ),
  0::bigint,
  'aucun rôle client ne possède de privilège direct sur ces tables'
);

select is(
  (
    select count(*)
    from audited_rls_targets target
    where has_table_privilege(
      'service_role',
      format('%I.%I', target.schema_name, target.table_name),
      'SELECT,INSERT,UPDATE,DELETE'
    )
  ),
  12::bigint,
  'le service interne conserve tous les privilèges nécessaires'
);

select * from finish();
rollback;
