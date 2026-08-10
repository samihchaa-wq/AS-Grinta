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
  ('public', 'historical_match_details'),
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
  13::bigint,
  'RLS reste activée sur les treize tables internes'
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
  13::bigint,
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
  1::bigint,
  'une seule table conserve le privilège client historique présent en production'
);

select ok(
  has_table_privilege('authenticated', 'public.historical_match_details', 'SELECT')
  and has_table_privilege('authenticated', 'public.historical_match_details', 'INSERT')
  and has_table_privilege('authenticated', 'public.historical_match_details', 'UPDATE')
  and has_table_privilege('authenticated', 'public.historical_match_details', 'DELETE')
  and not has_table_privilege('anon', 'public.historical_match_details', 'SELECT')
  and not has_table_privilege('anon', 'public.historical_match_details', 'INSERT')
  and not has_table_privilege('anon', 'public.historical_match_details', 'UPDATE')
  and not has_table_privilege('anon', 'public.historical_match_details', 'DELETE'),
  'historical_match_details reproduit exactement son ACL de production, sous deny_client_access'
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
  13::bigint,
  'le service interne conserve tous les privilèges nécessaires'
);

select * from finish();
rollback;
