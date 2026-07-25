begin;

set local search_path = public, extensions, pg_catalog;
select plan(5);

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

select ok(
  position(
    '''postmatch''::text' in (
      select pg_get_constraintdef(constraint_row.oid)
      from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.match_composition_publications'::regclass
        and constraint_row.conname = 'match_composition_publications_publication_kind_check'
    )
  ) > 0,
  'la publication post-match est autorisée par la contrainte'
);

select * from finish();
rollback;
