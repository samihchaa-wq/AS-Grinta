begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_set_match_address(uuid,text)',
    'EXECUTE'
  ),
  'un visiteur anonyme ne peut pas modifier une adresse de match'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_set_match_address(uuid,text)',
    'EXECUTE'
  ),
  'le client authentifié conserve la RPC, protégée par le contrôle admin interne'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.admin_set_match_address(uuid,text)',
    'EXECUTE'
  ),
  'le service interne conserve la mise à jour des adresses'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.cleanup_replaced_photo()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.cleanup_replaced_photo()',
    'EXECUTE'
  ),
  'la fonction de trigger photo n’est pas appelable directement par un client'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.cleanup_replaced_photo()',
    'EXECUTE'
  ),
  'le service interne conserve l’accès de maintenance au nettoyage photo'
);

select is(
  (
    select count(*)
    from pg_trigger
    where tgfoid = 'public.cleanup_replaced_photo()'::regprocedure
      and not tgisinternal
  ),
  3::bigint,
  'les trois triggers de nettoyage photo restent installés'
);

select * from finish();
rollback;
