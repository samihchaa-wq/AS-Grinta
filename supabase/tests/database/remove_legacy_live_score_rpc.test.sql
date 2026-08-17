begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  not exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_adjust_match_live_score'
      and proc.pronargs = 4
  ),
  'la RPC de score legacy a 4 parametres est supprimee'
);

select ok(
  exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_adjust_match_live_score'
      and proc.pronargs = 5
      and pg_get_function_arguments(proc.oid) like '%p_operation_id uuid%'
  ),
  'la RPC de score idempotente a 5 parametres reste disponible'
);

select * from finish();
rollback;
