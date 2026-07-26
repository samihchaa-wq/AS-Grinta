begin;

-- Invariant global : aucune fonction SECURITY DEFINER du schéma public ne doit
-- conserver le droit EXECUTE accordé implicitement à PUBLIC, ni être accordée
-- directement au rôle anon. Les droits explicites authenticated/service_role
-- déjà définis fonction par fonction restent inchangés.
do $block$
declare
  v_function record;
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
end;
$block$;

commit;
