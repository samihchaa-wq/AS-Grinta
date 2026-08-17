begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regprocedure(
    'public.admin_update_match_complete(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,integer,text,boolean,text,text)'
  ) is null,
  'ancienne signature admin_update_match_complete absente'
);

select ok(
  to_regprocedure(
    'public.update_internal_match(uuid,uuid,date,time without time zone,text)'
  ) is null,
  'ancienne signature update_internal_match absente'
);

select ok(
  to_regprocedure(
    'public.admin_update_match_complete(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric,timestamp with time zone,integer,text,boolean,text,text)'
  ) is not null,
  'signature verrouillée admin_update_match_complete conservée'
);

select ok(
  to_regprocedure(
    'public.update_internal_match(uuid,uuid,date,time without time zone,text,timestamp with time zone)'
  ) is not null,
  'signature verrouillée update_internal_match conservée'
);

select * from finish();
rollback;
