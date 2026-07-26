begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'aucune fonction SECURITY DEFINER publique n’est exécutable anonymement'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname <> 'profile_badge_metrics'
      and pg_get_functiondef(p.oid) !~* 'auth\.uid\s*\('
      and pg_get_functiondef(p.oid) !~* '(public|private)\.is_active_profile\s*\('
      and pg_get_functiondef(p.oid) !~* '(public|private)\.is_match_staff\s*\('
      and pg_get_functiondef(p.oid) !~* '(public|private)\.is_admin\s*\('
  ),
  0::bigint,
  'toute fonction privilégiée accessible aux connectés possède un garde approuvé'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.profile_badge_metrics(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.profile_badge_metrics(uuid)',
    'EXECUTE'
  ),
  'l’exception de lecture des métriques de badge est authentifiée uniquement'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral unnest(p.proargnames)
      with ordinality as argument(argument_name, position)
    where n.nspname = 'public'
      and p.proname = 'profile_badge_metrics'
      and argument.position > p.pronargs
      and coalesce(argument.argument_name, '') ~*
        '(email|username|password|token|endpoint|first_name|last_name|photo_url)'
  ),
  0::bigint,
  'profile_badge_metrics ne renvoie aucune donnée d’identité ou d’authentification'
);

select * from finish();
rollback;
