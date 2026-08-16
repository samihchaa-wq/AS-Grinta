begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)::integer
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_save_match_live_lineup'
      and proc.pronargs = 3
  ),
  0,
  'la signature historique sans lineup_revision n existe plus'
);

select is(
  (
    select count(*)::integer
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_save_match_live_lineup'
      and proc.pronargs = 4
      and pg_get_function_arguments(proc.oid)
        like '%p_expected_lineup_revision integer%'
  ),
  1,
  'la signature versionnee avec lineup_revision reste disponible'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.coach_save_match_live_lineup(uuid,jsonb,jsonb,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.coach_save_match_live_lineup(uuid,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'la signature versionnee conserve ses droits attendus'
);

select * from finish();
rollback;
