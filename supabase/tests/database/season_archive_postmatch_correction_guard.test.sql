begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
('fb100000-0000-0000-0000-000000000001','archiveguard-admin@example.invalid','{"first_name":"ArchiveAdmin"}'::jsonb),
('fb100000-0000-0000-0000-000000000002','archiveguard-a@example.invalid','{"first_name":"ArchiveA"}'::jsonb),
('fb100000-0000-0000-0000-000000000003','archiveguard-b@example.invalid','{"first_name":"ArchiveB"}'::jsonb);

update public.profiles
set status='active',
    role=case when id='fb100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    is_test_account=false
where id in (
  'fb100000-0000-0000-0000-000000000001',
  'fb100000-0000-0000-0000-000000000002',
  'fb100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id,name,status)
values('fb200000-0000-0000-0000-000000000001','2074-2075','open');

insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position
) values(
  'fb400000-0000-0000-0000-000000000001',
  'fb200000-0000-0000-0000-000000000001',
  'Archive','Scorer',false,true,1
);

insert into public.opponents(id,name)
values('fb300000-0000-0000-0000-000000000001','Archive Guard FC');

select set_config(
  'request.jwt.claims',
  '{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.archive_guard_match',
  public.admin_create_match_complete(
    'fb200000-0000-0000-0000-000000000001',
    'fb300000-0000-0000-0000-000000000001',
    ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile',2,3,4,null,null,false,'championnat',null
  )::text,
  true
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"fb100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_match_prediction(
  current_setting('test.archive_guard_match')::uuid,
  1,
  0
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"fb100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_match_prediction(
  current_setting('test.archive_guard_match')::uuid,
  2,
  0
);
reset role;

-- Move the fixture to the past without invoking scheduling guards.
set local session_replication_role=replica;
update public.matches
set kickoff_at='2007-03-17 20:00:00+00',
    match_date='2007-03-17',
    match_time='21:00:00'
where id=current_setting('test.archive_guard_match')::uuid;
set local session_replication_role=origin;

-- Initial validation makes B the prediction leader and opens the immutable
-- post-match correction window.
select set_config(
  'request.jwt.claims',
  '{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
select public.finalize_match_postgame(
  current_setting('test.archive_guard_match')::uuid,
  0,
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fb400000-0000-0000-0000-000000000001',
    'goals',2
  )),
  null,
  2
);

select ok(
  (select points from public.v_match_prediction_points
   where match_id=current_setting('test.archive_guard_match')::uuid
     and profile_id='fb100000-0000-0000-0000-000000000003')
  >
  (select points from public.v_match_prediction_points
   where match_id=current_setting('test.archive_guard_match')::uuid
     and profile_id='fb100000-0000-0000-0000-000000000002'),
  'B leads before the in-window correction'
);

set local role authenticated;
select throws_ok(
  $$select public.set_season_status('fb200000-0000-0000-0000-000000000001'::uuid,'archived')$$,
  '22023',
  'Impossible d’archiver la saison : un match possède encore une fenêtre de correction ouverte.',
  'season archive is refused while a finished match remains correctable'
);
reset role;

select is(
  (select status::text from public.seasons
   where id='fb200000-0000-0000-0000-000000000001'),
  'open',
  'failed archive leaves the season mutable'
);
select is(
  (select count(*) from public.season_awards
   where season_id='fb200000-0000-0000-0000-000000000001'),
  0::bigint,
  'no season title is persisted before correction finality'
);

-- Correct the match through the real post-match workflow. A is now the leader.
select public.finalize_match_postgame(
  current_setting('test.archive_guard_match')::uuid,
  0,
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fb400000-0000-0000-0000-000000000001',
    'goals',1
  )),
  null,
  1
);

select ok(
  (select points from public.v_match_prediction_points
   where match_id=current_setting('test.archive_guard_match')::uuid
     and profile_id='fb100000-0000-0000-0000-000000000002')
  >
  (select points from public.v_match_prediction_points
   where match_id=current_setting('test.archive_guard_match')::uuid
     and profile_id='fb100000-0000-0000-0000-000000000003'),
  'A leads after the authorized correction'
);

-- Age every supported correction-deadline source beyond 24 h. This simulates
-- the normal passage of time without making the test sleep or depend on wall time.
set local session_replication_role=replica;
update public.match_sport_motm_elections
set closes_at=now()-interval '1 minute'
where match_id=current_setting('test.archive_guard_match')::uuid;
update public.match_sport_finalizations
set validated_at=now()-interval '25 hours'
where match_id=current_setting('test.archive_guard_match')::uuid;
update public.matches
set result_validated_at=now()-interval '25 hours'
where id=current_setting('test.archive_guard_match')::uuid;
set local session_replication_role=origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.set_season_status('fb200000-0000-0000-0000-000000000001'::uuid,'archived')$$,
  'season archive succeeds once every correction deadline is closed'
);
reset role;

select is(
  (select status::text from public.seasons
   where id='fb200000-0000-0000-0000-000000000001'),
  'archived',
  'season becomes immutable only after post-match finality'
);
select ok(
  exists(select 1 from public.season_awards
    where season_id='fb200000-0000-0000-0000-000000000001'
      and profile_id='fb100000-0000-0000-0000-000000000002'
      and award_type='best_pred_overall'),
  'the corrected final leader receives best_pred_overall'
);
select ok(
  not exists(select 1 from public.season_awards
    where season_id='fb200000-0000-0000-0000-000000000001'
      and profile_id='fb100000-0000-0000-0000-000000000003'
      and award_type='best_pred_overall'),
  'the pre-correction leader receives no stale overall title'
);

select * from finish();
rollback;
