begin;

-- Invariant global : aucune fonction SECURITY DEFINER du schéma public ne doit
-- conserver le droit EXECUTE accordé implicitement à PUBLIC, ni être accordée
-- directement au rôle anon. Les droits explicites authenticated/service_role
-- déjà définis fonction par fonction doivent rester inchangés.
do $block$
declare
  v_function record;
  v_authenticated_before oid[];
  v_service_before oid[];
  v_lost_authenticated text;
  v_lost_service text;
  v_anon_remaining bigint;
begin
  select coalesce(array_agg(p.oid), '{}'::oid[])
  into v_authenticated_before
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and has_function_privilege('authenticated', p.oid, 'EXECUTE');

  select coalesce(array_agg(p.oid), '{}'::oid[])
  into v_service_before
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and has_function_privilege('service_role', p.oid, 'EXECUTE');

  for v_function in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format(
      'revoke execute on function %s from public, anon',
      v_function.signature
    );
  end loop;

  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
  into v_lost_authenticated
  from pg_proc p
  where p.oid = any(v_authenticated_before)
    and not has_function_privilege('authenticated', p.oid, 'EXECUTE');

  if v_lost_authenticated is not null then
    raise exception
      'Authenticated relied on an implicit PUBLIC grant for: %',
      v_lost_authenticated
      using errcode = '42501';
  end if;

  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
  into v_lost_service
  from pg_proc p
  where p.oid = any(v_service_before)
    and not has_function_privilege('service_role', p.oid, 'EXECUTE');

  if v_lost_service is not null then
    raise exception
      'Service role relied on an implicit PUBLIC grant for: %',
      v_lost_service
      using errcode = '42501';
  end if;

  select count(*)
  into v_anon_remaining
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_remaining <> 0 then
    raise exception
      'Anonymous execution remains on % SECURITY DEFINER function(s)',
      v_anon_remaining
      using errcode = '42501';
  end if;
end;
$block$;

commit;
