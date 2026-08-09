begin;

select plan(8);

select ok(
  to_regprocedure('public.save_my_season_predictions(uuid,jsonb)') is not null,
  'atomic season prediction save RPC exists'
);

select ok(
  to_regprocedure('public.admin_get_player_position_history(timestamp with time zone)') is not null,
  'player position history RPC exists'
);

select ok(
  to_regprocedure('public.admin_add_or_reuse_match_guest(uuid,uuid,text,text,boolean,text)') is not null,
  'guest add/reuse RPC exists'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'guest_players'
      and indexdef ilike '%unique%'
      and indexdef ilike '%is_reusable%'
  ),
  'reusable guest identity has a uniqueness guard'
);

select ok(
  position('availability_j3' in pg_get_constraintdef(
    (select oid from pg_constraint
     where conrelid = 'public.push_delivery_log'::regclass
       and conname = 'push_delivery_log_kind_check')
  )) > 0,
  'push delivery log accepts availability_j3'
);

select ok(
  position('availability_j1' in pg_get_constraintdef(
    (select oid from pg_constraint
     where conrelid = 'public.push_delivery_log'::regclass
       and conname = 'push_delivery_log_kind_check')
  )) > 0,
  'push delivery log accepts availability_j1'
);

select ok(
  position('v_global_hour' in pg_get_functiondef(
    'public.consume_registration_rate_limit(text)'::regprocedure
  )) = 0,
  'registration limiter has no shared global hourly counter'
);

select ok(
  position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.admin_add_or_reuse_match_guest(uuid,uuid,text,text,boolean,text)'::regprocedure
  )) > 0,
  'guest add/reuse serializes identical concurrent creation'
);

select * from finish();
rollback;
