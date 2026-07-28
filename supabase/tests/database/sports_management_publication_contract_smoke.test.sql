begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regprocedure(
    'public.admin_publish_match_effectif(uuid,integer,jsonb,text)'
  ) is not null,
  'la RPC explicite de publication d’effectif existe'
);

select is(
  (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid = to_regprocedure(
      'public.admin_publish_match_effectif(uuid,integer,jsonb,text)'
    )
  ),
  false,
  'la RPC publique reste SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_publish_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.admin_publish_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'la publication est réservée aux profils authentifiés puis contrôlée côté serveur'
);

select * from finish();
rollback;
