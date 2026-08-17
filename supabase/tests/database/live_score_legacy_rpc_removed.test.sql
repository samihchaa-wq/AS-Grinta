begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)::integer
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_adjust_match_live_score'
  ),
  1,
  'une seule RPC publique de score Live reste exposee'
);

select ok(
  not exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_adjust_match_live_score'
      and proc.pronargs = 4
  ),
  'la signature historique sans operation_id est absente'
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
  'la seule signature restante exige un operation_id'
);

select * from finish();
rollback;
