begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_table_privilege('authenticated', 'public.season_predictions', 'SELECT'),
  'authenticated keeps read access to season_predictions'
);

select ok(
  not has_table_privilege('authenticated', 'public.season_predictions', 'INSERT'),
  'authenticated cannot INSERT season_predictions directly'
);

select ok(
  not has_table_privilege('authenticated', 'public.season_predictions', 'UPDATE'),
  'authenticated cannot UPDATE season_predictions directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.save_my_season_predictions(uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated can still execute the guarded batch RPC'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'season_predictions'
      and cmd in ('INSERT', 'UPDATE')
  ),
  'season_predictions exposes no authenticated write policy'
);

select * from finish();
rollback;
