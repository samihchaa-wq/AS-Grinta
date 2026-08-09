begin;

select plan(2);

select ok(
  position('v_global_hour' in pg_get_functiondef(
    'public.consume_registration_rate_limit(text)'::regprocedure
  )) = 0,
  'registration rate limit no longer has a shared global hourly quota'
);

select ok(
  position('v_origin_hour >= 5 or v_origin_day >= 15' in pg_get_functiondef(
    'public.consume_registration_rate_limit(text)'::regprocedure
  )) > 0,
  'registration rate limit keeps per-origin hourly and daily limits'
);

select * from finish();
rollback;
