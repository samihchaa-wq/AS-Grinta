begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'matches'
      and column_name = 'match_time'
  ),
  'NO',
  'matches.match_time est obligatoire'
);

select ok(
  to_regprocedure('public.get_internal_composition(uuid)') is not null,
  'le RPC canonique de lecture de composition interne existe'
);

select ok(
  (
    select p.prosecdef
      and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
    from pg_proc p
    where p.oid = 'public.get_internal_composition(uuid)'::regprocedure
  ),
  'le RPC canonique conserve SECURITY DEFINER avec search_path vide'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_internal_composition(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_internal_composition(uuid)',
    'EXECUTE'
  ),
  'la composition interne est lisible uniquement par une session authentifiée'
);

select ok(
  to_regprocedure('public.admin_get_internal_composition(uuid)') is not null
  and not (
    select p.prosecdef
    from pg_proc p
    where p.oid = 'public.admin_get_internal_composition(uuid)'::regprocedure
  )
  and pg_get_functiondef(
    'public.admin_get_internal_composition(uuid)'::regprocedure
  ) ~ 'public\.get_internal_composition\(p_match_id\)',
  'l’ancien nom reste un alias SECURITY INVOKER de compatibilité'
);

-- The CI bootstrap intentionally grants authenticated a *global* default
-- EXECUTE so pg_temp pgTAP fixtures can run after SET ROLE. Production never
-- receives that test-only grant. Assert the application-owned public-schema
-- default ACL here; the global production default is verified by the canonical
-- migration/replay and by production inspection.
select is(
  (
    select count(*)
    from pg_default_acl defaults
    cross join lateral aclexplode(defaults.defaclacl) acl
    where defaults.defaclrole = 'postgres'::regrole
      and defaults.defaclobjtype = 'f'
      and defaults.defaclnamespace = 'public'::regnamespace
      and acl.privilege_type = 'EXECUTE'
      and acl.grantee in (
        0,
        'anon'::regrole,
        'authenticated'::regrole
      )
  ),
  0::bigint,
  'les futurs RPC public postgres ne reçoivent aucun EXECUTE implicite client'
);

select * from finish();
rollback;
