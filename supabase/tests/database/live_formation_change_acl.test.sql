begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.coach_change_match_live_formation(uuid,text,jsonb,integer)',
    'EXECUTE'
  ),
  'authenticated peut appeler le changement de dispositif Live'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.coach_change_match_live_formation(uuid,text,jsonb,integer)',
    'EXECUTE'
  ),
  'anon ne peut pas appeler le changement de dispositif Live'
);

select * from finish();
rollback;
