begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_or_create_opponent(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_or_create_opponent(text)',
    'EXECUTE'
  ),
  'la création d’un adversaire reste réservée aux utilisateurs authentifiés'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  '94000000-0000-0000-0000-000000000001',
  'duplicate-opponent-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Opponent"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '94000000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"94000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.opponent_duplicate_first',
  public.get_or_create_opponent('Duplicate FC')::text,
  true
);
select set_config(
  'test.opponent_duplicate_second',
  public.get_or_create_opponent('Duplicate FC')::text,
  true
);

reset role;

select isnt(
  current_setting('test.opponent_duplicate_first'),
  current_setting('test.opponent_duplicate_second'),
  'deux créations avec exactement le même nom produisent deux adversaires distincts'
);

select is(
  (
    select count(*)::integer
    from public.opponents
    where name = 'Duplicate FC'
  ),
  2,
  'les deux fiches adversaires homonymes sont conservées'
);

select * from finish();
rollback;
