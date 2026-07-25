begin;

set local search_path = public, extensions, pg_catalog;
select plan(4);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_create_postmatch_composition(uuid,text,jsonb,boolean,text)',
    'EXECUTE'
  ),
  'le wrapper post-match est accessible aux utilisateurs authentifiés'
);

select ok(
  has_function_privilege(
    'authenticated',
    'private.create_postmatch_composition(uuid,text,jsonb,boolean,text)',
    'EXECUTE'
  ),
  'le wrapper peut appeler son implémentation privée'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_create_postmatch_composition(uuid,text,jsonb,boolean,text)',
    'EXECUTE'
  ),
  'le wrapper post-match reste inaccessible aux anonymes'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.create_postmatch_composition(uuid,text,jsonb,boolean,text)',
    'EXECUTE'
  ),
  'l’implémentation privée reste inaccessible aux anonymes'
);

select * from finish();
rollback;
