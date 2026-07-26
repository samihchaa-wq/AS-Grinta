begin;

-- Invariant global : aucune fonction SECURITY DEFINER du schéma public ne doit
-- conserver le droit EXECUTE accordé implicitement à PUBLIC, ni être accordée
-- directement au rôle anon. Les GRANT explicites déjà présents sur
-- authenticated et service_role ne sont pas modifiés par ce REVOKE ciblé.
do $block$
declare
  v_function record;
  v_anon_remaining bigint;
begin
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
