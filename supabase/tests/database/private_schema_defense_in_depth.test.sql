begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relkind = 'r'
      and relation.relrowsecurity
  ),
  (
    select count(*)
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relkind = 'r'
  ),
  'toutes les tables privées ont la RLS activée'
);

select is(
  (
    select count(*)
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relkind = 'r'
      and (
        has_table_privilege(
          'anon', relation.oid, 'SELECT,INSERT,UPDATE,DELETE'
        )
        or has_table_privilege(
          'authenticated', relation.oid, 'SELECT,INSERT,UPDATE,DELETE'
        )
      )
  ),
  0::bigint,
  'aucune table privée ne donne de CRUD direct aux rôles clients'
);

select ok(
  (
    select constraint_row.convalidated
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.push_notification_log'::regclass
      and constraint_row.conname = 'push_notification_log_kind_check'
  ),
  'la contrainte des types de notifications est validée sur tout l’historique'
);

select * from finish();
rollback;
