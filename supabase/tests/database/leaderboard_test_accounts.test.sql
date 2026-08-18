begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_attribute
    where attrelid = 'public.profiles'::regclass
      and attname = 'is_test_account'
      and attnum > 0
      and not attisdropped
      and attnotnull
  ),
  'profiles expose an explicit non-null test-account marker'
);

select ok(
  coalesce(
    (
      select pg_get_expr(adbin, adrelid) = 'false'
      from pg_attrdef
      where adrelid = 'public.profiles'::regclass
        and adnum = (
          select attnum
          from pg_attribute
          where attrelid = 'public.profiles'::regclass
            and attname = 'is_test_account'
            and not attisdropped
        )
    ),
    false
  ),
  'new profiles are real accounts by default'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'is_test_account',
    'UPDATE'
  ),
  'authenticated clients cannot mark themselves as test accounts'
);

select ok(
  exists (
    select 1
    from pg_class
    where oid = 'public.v_classement_general'::regclass
      and coalesce(reloptions, '{}'::text[]) @> array['security_invoker=true']
  ),
  'the leaderboard keeps security_invoker enabled'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'fb100000-0000-0000-0000-000000000001',
    'leaderboard-real@example.invalid',
    '{"first_name":"Real","last_name":"Leaderboard"}'::jsonb
  ),
  (
    'fb100000-0000-0000-0000-000000000002',
    'leaderboard-qa@example.invalid',
    '{"first_name":"Qa","last_name":"Leaderboard"}'::jsonb
  );

update public.profiles
set status = 'active',
    is_test_account = id = 'fb100000-0000-0000-0000-000000000002'
where id in (
  'fb100000-0000-0000-0000-000000000001',
  'fb100000-0000-0000-0000-000000000002'
);

select ok(
  exists (
    select 1
    from public.v_classement_general
    where profile_id = 'fb100000-0000-0000-0000-000000000001'
  ),
  'an active real pronosticator remains visible in the leaderboard'
);

select ok(
  not exists (
    select 1
    from public.v_classement_general
    where profile_id = 'fb100000-0000-0000-0000-000000000002'
  ),
  'an active QA account is excluded from the leaderboard'
);

select * from finish();
rollback;
