begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
('fd100000-0000-0000-0000-000000000001','season-write@example.invalid','{"first_name":"SeasonWrite"}'::jsonb);

update public.profiles
set status='active', role='pronostiqueur'
where id='fd100000-0000-0000-0000-000000000001';

insert into public.seasons(id,name,status)
values('fd200000-0000-0000-0000-000000000001','2073-2074','open');

insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position
) values
(
  'fd400000-0000-0000-0000-000000000001',
  'fd200000-0000-0000-0000-000000000001',
  'Attaquant','Atomic',false,true,1
),
(
  'fd400000-0000-0000-0000-000000000002',
  'fd200000-0000-0000-0000-000000000001',
  'Gardien','Atomic',true,true,2
);

select ok(
  has_table_privilege('authenticated','public.season_predictions','SELECT'),
  'authenticated keeps read access to season_predictions'
);
select ok(
  not has_table_privilege('authenticated','public.season_predictions','INSERT'),
  'authenticated cannot INSERT season_predictions directly'
);
select ok(
  not has_table_privilege('authenticated','public.season_predictions','UPDATE'),
  'authenticated cannot UPDATE season_predictions directly'
);
select ok(
  not has_table_privilege('authenticated','public.season_predictions','DELETE'),
  'authenticated cannot DELETE season_predictions directly'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.save_my_season_predictions(uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated can execute the public atomic save RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'private.save_my_season_predictions(uuid,jsonb)',
    'EXECUTE'
  ),
  'authenticated cannot execute the private implementation directly'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fd100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.save_my_season_predictions(
    'fd200000-0000-0000-0000-000000000001'::uuid,
    jsonb_build_array(
      jsonb_build_object(
        'season_player_id','fd400000-0000-0000-0000-000000000001',
        'category','buts',
        'predicted_value_30',12
      ),
      jsonb_build_object(
        'season_player_id','fd400000-0000-0000-0000-000000000002',
        'category','clean_sheets',
        'predicted_value_30',7
      )
    )
  )$$,
  'complete season form is saved through the public RPC'
);

reset role;

select is(
  (
    select count(*)
    from public.season_predictions
    where season_id='fd200000-0000-0000-0000-000000000001'
      and predictor_profile_id='fd100000-0000-0000-0000-000000000001'
      and is_filled
  ),
  2::bigint,
  'the atomic RPC fills the complete two-player roster'
);
select is(
  (
    select predicted_value_30
    from public.season_predictions
    where season_id='fd200000-0000-0000-0000-000000000001'
      and predictor_profile_id='fd100000-0000-0000-0000-000000000001'
      and season_player_id='fd400000-0000-0000-0000-000000000001'
      and category='buts'
  ),
  12,
  'outfield prediction value is persisted'
);
select is(
  (
    select predicted_value_30
    from public.season_predictions
    where season_id='fd200000-0000-0000-0000-000000000001'
      and predictor_profile_id='fd100000-0000-0000-0000-000000000001'
      and season_player_id='fd400000-0000-0000-0000-000000000002'
      and category='clean_sheets'
  ),
  7,
  'goalkeeper prediction value is persisted'
);

set local role authenticated;
select throws_ok(
  $$select public.save_my_season_predictions(
    'fd200000-0000-0000-0000-000000000001'::uuid,
    jsonb_build_array(
      jsonb_build_object(
        'season_player_id','fd400000-0000-0000-0000-000000000001',
        'category','buts',
        'predicted_value_30',99
      )
    )
  )$$,
  '22023',
  'The complete active roster must be submitted',
  'an incomplete form is rejected atomically'
);
reset role;

select is(
  (
    select predicted_value_30
    from public.season_predictions
    where season_id='fd200000-0000-0000-0000-000000000001'
      and predictor_profile_id='fd100000-0000-0000-0000-000000000001'
      and season_player_id='fd400000-0000-0000-0000-000000000001'
      and category='buts'
  ),
  12,
  'rejected incomplete save leaves prior values unchanged'
);

select * from finish();
rollback;
