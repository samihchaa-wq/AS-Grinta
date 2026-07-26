begin;
set local search_path = public, extensions, pg_catalog;
select plan(2);

select has_function(
  'public',
  'admin_set_match_address',
  array['uuid', 'text', 'boolean'],
  'le RPC accepte le choix explicite de mémorisation'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_set_match_address(uuid,text,boolean)',
    'EXECUTE'
  ),
  'le RPC reste inaccessible aux anonymes'
);

select * from finish();
rollback;
