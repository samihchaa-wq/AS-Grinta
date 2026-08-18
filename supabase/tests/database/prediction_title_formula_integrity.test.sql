begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
('fe100000-0000-0000-0000-000000000001','titleformula-admin@example.invalid','{"first_name":"Titleadmin"}'::jsonb),
('fe100000-0000-0000-0000-000000000002','titleformula-a@example.invalid','{"first_name":"Titleone"}'::jsonb),
('fe100000-0000-0000-0000-000000000003','titleformula-b@example.invalid','{"first_name":"Titletwo"}'::jsonb);
update public.profiles
set status='active',
    role=case when id='fe100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    is_test_account=false
where id in (
  'fe100000-0000-0000-0000-000000000001',
  'fe100000-0000-0000-0000-000000000002',
  'fe100000-0000-0000-0000-000000000003'
);

-- Overall title: A wins the visible weighted Global leaderboard even though B
-- has the larger unweighted raw sum. best_pred_overall must follow Global.
insert into public.seasons(id,name,status)
values('fe200000-0000-0000-0000-000000000001','2076-2077','open');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position
) values(
  'fe400000-0000-0000-0000-000000000001',
  'fe200000-0000-0000-0000-000000000001',
  'Target','Overall',false,true,1
);
insert into public.opponents(id,name)
values('fe300000-0000-0000-0000-000000000001','Overall Formula FC');

select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_my_season_predictions(
  'fe200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fe400000-0000-0000-0000-000000000001',
    'category','buts','predicted_value_30',0
  ))
);
reset role;
select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_my_season_predictions(
  'fe200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fe400000-0000-0000-0000-000000000001',
    'category','buts','predicted_value_30',1
  ))
);
reset role;

select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_season_predictions_lock('fe200000-0000-0000-0000-000000000001',true);
select set_config(
  'test.overall_match',
  public.admin_create_match_complete(
    'fe200000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000001',
    ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile',2,3,4,null,null,false,'championnat',null
  )::text,
  true
);
reset role;

select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_match_prediction(current_setting('test.overall_match')::uuid,1,0);
reset role;
select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_match_prediction(current_setting('test.overall_match')::uuid,2,0);
reset role;

set local session_replication_role=replica;
update public.matches
set kickoff_at='2009-03-17 20:00:00+00',
    match_date='2009-03-17',
    match_time='21:00:00'
where id=current_setting('test.overall_match')::uuid;
set local session_replication_role=origin;
select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.finalize_match_postgame(
  current_setting('test.overall_match')::uuid,
  0,
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fe400000-0000-0000-0000-000000000001','goals',1
  )),
  null,
  1
);
select public.set_season_status('fe200000-0000-0000-0000-000000000001','archived');
reset role;

select ok(
  (select total_points from public.v_classement_general
   where profile_id='fe100000-0000-0000-0000-000000000002')
  >
  (select total_points from public.v_classement_general
   where profile_id='fe100000-0000-0000-0000-000000000003'),
  'fixture A leads the weighted Global leaderboard'
);
select ok(
  exists(select 1 from public.season_awards
    where season_id='fe200000-0000-0000-0000-000000000001'
      and profile_id='fe100000-0000-0000-0000-000000000002'
      and award_type='best_pred_overall'),
  'weighted Global leader receives best_pred_overall'
);
select ok(
  not exists(select 1 from public.season_awards
    where season_id='fe200000-0000-0000-0000-000000000001'
      and profile_id='fe100000-0000-0000-0000-000000000003'
      and award_type='best_pred_overall'),
  'lower weighted Global scorer does not receive best_pred_overall'
);

-- Player title: A has better base proximity points, but B is the only one with
-- the correct relative order and therefore wins after the ordering bonus.
insert into public.seasons(id,name,status)
values('fe200000-0000-0000-0000-000000000002','2075-2076','open');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position
) values
('fe400000-0000-0000-0000-000000000002','fe200000-0000-0000-0000-000000000002','First','Target',false,true,1),
('fe400000-0000-0000-0000-000000000003','fe200000-0000-0000-0000-000000000002','Second','Target',false,true,2);
insert into public.opponents(id,name)
values('fe300000-0000-0000-0000-000000000002','Bonus Formula FC');

select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_my_season_predictions(
  'fe200000-0000-0000-0000-000000000002',
  jsonb_build_array(
    jsonb_build_object('season_player_id','fe400000-0000-0000-0000-000000000002','category','buts','predicted_value_30',1),
    jsonb_build_object('season_player_id','fe400000-0000-0000-0000-000000000003','category','buts','predicted_value_30',1)
  )
);
reset role;
select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_my_season_predictions(
  'fe200000-0000-0000-0000-000000000002',
  jsonb_build_array(
    jsonb_build_object('season_player_id','fe400000-0000-0000-0000-000000000002','category','buts','predicted_value_30',10),
    jsonb_build_object('season_player_id','fe400000-0000-0000-0000-000000000003','category','buts','predicted_value_30',9)
  )
);
reset role;

select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_season_predictions_lock('fe200000-0000-0000-0000-000000000002',true);
select set_config(
  'test.bonus_match',
  public.admin_create_match_complete(
    'fe200000-0000-0000-0000-000000000002',
    'fe300000-0000-0000-0000-000000000002',
    ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile',2,3,4,null,null,false,'championnat',null
  )::text,
  true
);
reset role;
set local session_replication_role=replica;
update public.matches
set kickoff_at='2008-03-17 20:00:00+00',
    match_date='2008-03-17',
    match_time='21:00:00'
where id=current_setting('test.bonus_match')::uuid;
set local session_replication_role=origin;
select set_config('request.jwt.claims','{"sub":"fe100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.finalize_match_postgame(
  current_setting('test.bonus_match')::uuid,
  0,
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fe400000-0000-0000-0000-000000000002','goals',2
  )),
  null,
  2
);
select public.set_season_status('fe200000-0000-0000-0000-000000000002','archived');
reset role;

select ok(
  (
    (select coalesce(sum(points),0) from public.v_season_prediction_points
      where season_id='fe200000-0000-0000-0000-000000000002'
        and predictor_profile_id='fe100000-0000-0000-0000-000000000003')
    +
    (select coalesce(sum(bonus_points),0) from public.v_season_prediction_bonus
      where season_id='fe200000-0000-0000-0000-000000000002'
        and predictor_profile_id='fe100000-0000-0000-0000-000000000003')
  )
  >
  (
    (select coalesce(sum(points),0) from public.v_season_prediction_points
      where season_id='fe200000-0000-0000-0000-000000000002'
        and predictor_profile_id='fe100000-0000-0000-0000-000000000002')
    +
    (select coalesce(sum(bonus_points),0) from public.v_season_prediction_bonus
      where season_id='fe200000-0000-0000-0000-000000000002'
        and predictor_profile_id='fe100000-0000-0000-0000-000000000002')
  ),
  'fixture B leads Buteurs after ordering bonus'
);
select ok(
  exists(select 1 from public.season_awards
    where season_id='fe200000-0000-0000-0000-000000000002'
      and profile_id='fe100000-0000-0000-0000-000000000003'
      and award_type='best_pred_player'),
  'bonus-adjusted Buteurs leader receives best_pred_player'
);
select ok(
  not exists(select 1 from public.season_awards
    where season_id='fe200000-0000-0000-0000-000000000002'
      and profile_id='fe100000-0000-0000-0000-000000000002'
      and award_type='best_pred_player'),
  'base-only leader does not receive best_pred_player'
);

select * from finish();
rollback;
