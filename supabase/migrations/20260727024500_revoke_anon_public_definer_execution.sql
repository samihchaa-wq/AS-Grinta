begin;

-- Invariant global : aucune fonction SECURITY DEFINER du schéma public ne doit
-- être directement exécutable par un visiteur anonyme. Les fonctions publiques
-- sans élévation de privilèges ne sont pas concernées.
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
    execute format('revoke execute on function %s from anon', v_function.signature);
  end loop;
end;
$block$;

commit;
