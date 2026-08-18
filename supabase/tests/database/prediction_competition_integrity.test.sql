begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
('fc100000-0000-0000-0000-000000000001','integrity-admin@example.invalid','{"first_name":"IntegrityAdmin"}'::jsonb),
('fc100000-0000-0000-0000-000000000002','integrity-real@example.invalid','{"first_name":"IntegrityReal"}'::jsonb),
('fc100000-0000-0000-0000-000000000003','integrity-test@example.invalid','{"first_name":"IntegrityTest"}'::jsonb);

update public.profiles
set status='active',
    role=case when id='fc100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    is_test_account=(id='fc100000-0000-0000-0000-000000000003')
where id in (
  'fc100000-0000-0000-0000-000000000001',
  'fc100000-0000-0000-0000-000000000002',
  'fc100000-0000-0000-0000-000000000003'
);

select ok(
  not has_table_privilege('authenticated','public.match_predictions','INSERT'),
  'authenticated cannot INSERT match_predictions directly'
);
select ok(
  not has_table_privilege('authenticated','public.match_predictions','UPDATE'),
  'authenticated cannot UPDATE match_predictions directly'
);

-- Match prediction contract: official RPC remains usable, internal matches are
-- rejected even when a privileged caller writes directly.
insert into public.seasons(id,name,status)
values('fc200000-0000-0000-0000-000000000001','2087-2088','open');
insert into public.opponents(id,name)
values('fc300000-0000-0000-0000-000000000001','Integrity FC');

select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.integrity_match',
  public.admin_create_match_complete(
    'fc200000-0000-0000-0000-000000000001',
    'fc300000-0000-0000-0000-000000000001',
    ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile',2.00,3.00,4.00,null,null,false,'championnat',null
  )::text,
  true
);
select set_config(
  'test.internal_match',
  public.create_internal_match(
    'fc200000-0000-0000-0000-000000000001',
    ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '3 days') at time zone 'Europe/Paris')::time,
    null
  )::text,
  true
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.save_match_prediction(%L::uuid,1,0)',
    current_setting('test.integrity_match')
  ),
  'official match prediction RPC still writes after table grants are revoked'
);
select throws_ok(
  format(
    'select public.save_match_prediction(%L::uuid,1,0)',
    current_setting('test.internal_match')
  ),
  '22023',
  'Les matchs entre nous ne sont pas ouverts aux pronostics.',
  'official RPC rejects internal matches'
);
reset role;

select throws_ok(
  format(
    $sql$insert into public.match_predictions(
      match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
    ) values(%L::uuid,%L::uuid,2,1,true)$sql$,
    current_setting('test.internal_match'),
    'fc100000-0000-0000-0000-000000000002'
  ),
  '22023',
  'Les matchs entre nous ne sont pas ouverts aux pronostics.',
  'database trigger also rejects privileged filled writes on internal matches'
);

-- A manual close belongs to the old kickoff. Moving the kickoff creates a new
-- prediction window and clears only that stale close marker.
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.close_match_predictions(current_setting('test.integrity_match')::uuid);
reset role;
select set_config(
  'test.integrity_updated_at',
  (select updated_at::text from public.matches where id=current_setting('test.integrity_match')::uuid),
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.admin_update_match_complete(
    current_setting('test.integrity_match')::uuid,
    'fc200000-0000-0000-0000-000000000001',
    'fc300000-0000-0000-0000-000000000001',
    ((now()+interval '4 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile','a_venir',2.00,3.00,4.00,
    current_setting('test.integrity_updated_at')::timestamptz,
    null,null,false,'championnat',null
  ),
  'reschedule succeeds after a manual prediction close'
);
reset role;
select is(
  (select predictions_closed_at from public.matches where id=current_setting('test.integrity_match')::uuid),
  null::timestamptz,
  'reschedule clears the stale manual prediction close'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  format(
    'select public.save_match_prediction(%L::uuid,2,1)',
    current_setting('test.integrity_match')
  ),
  'prediction can be modified in the new rescheduled window'
);
reset role;

-- Season prediction reveal becomes irreversible once a real prediction exists.
insert into public.seasons(id,name,status)
values('fc200000-0000-0000-0000-000000000002','2086-2087','open');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
) values(
  'fc400000-0000-0000-0000-000000000001',
  'fc200000-0000-0000-0000-000000000002',
  'Target','Season',false,true,1,null
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'fc200000-0000-0000-0000-000000000002',
  jsonb_build_array(jsonb_build_object(
    'season_player_id','fc400000-0000-0000-0000-000000000001',
    'category','buts','predicted_value_30',10
  ))
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.set_season_predictions_lock('fc200000-0000-0000-0000-000000000002',true),
  'admin can reveal season predictions once'
);
select throws_ok(
  $$select public.set_season_predictions_lock('fc200000-0000-0000-0000-000000000002'::uuid,false)$$,
  '22023',
  'Les pronostics de saison révélés sont définitivement figés.',
  'revealed season predictions cannot be unlocked through the RPC'
);
select throws_ok(
  $$update public.seasons set season_predictions_locked_at=null where id='fc200000-0000-0000-0000-000000000002'::uuid$$,
  '22023',
  'Les pronostics de saison révélés sont définitivement figés.',
  'direct staff update cannot clear a committed reveal either'
);
select ok(
  public.set_season_status('fc200000-0000-0000-0000-000000000002','archived'),
  'season can be archived after prediction reveal'
);
select throws_ok(
  $$select public.set_season_status('fc200000-0000-0000-0000-000000000002'::uuid,'open')$$,
  '22023',
  'Une saison avec des données de compétition ne peut pas être rouverte.',
  'archived season with competition data cannot reopen by status RPC'
);
select throws_ok(
  $$select public.open_or_create_season('2086-2087')$$,
  '22023',
  'Une saison avec des données de compétition ne peut pas être rouverte.',
  'archived season with competition data cannot reopen by name RPC'
);
reset role;

select ok(
  exists(
    select 1 from public.season_prediction_roster_captures
    where season_id='fc200000-0000-0000-0000-000000000002'
  ),
  'committed prediction roster snapshot remains present after archive'
);

-- Archived real predictors remain in historical rankings after participating.
set local session_replication_role=replica;
update public.matches
set kickoff_at='2015-03-17 20:00:00+00',
    match_date='2015-03-17',
    match_time='21:00:00'
where id=current_setting('test.integrity_match')::uuid;
set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.finalize_match_postgame(
  current_setting('test.integrity_match')::uuid,1,'[]'::jsonb,null,2
);
reset role;
update public.profiles
set status='archived'
where id='fc100000-0000-0000-0000-000000000002';
select ok(
  exists(
    select 1 from public.v_classement_general
    where profile_id='fc100000-0000-0000-0000-000000000002'
  ),
  'archived real predictor remains in the leaderboard after participation'
);

-- Test accounts do not enter the title ranking; the best real predictor is
-- promoted instead of being left behind a filtered test winner.
insert into public.seasons(id,name,status)
values('fc200000-0000-0000-0000-000000000003','2085-2086','open');
insert into public.opponents(id,name)
values('fc300000-0000-0000-0000-000000000002','Title Integrity FC');
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.title_match',
  public.admin_create_match_complete(
    'fc200000-0000-0000-0000-000000000003',
    'fc300000-0000-0000-0000-000000000002',
    ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile',2.00,3.00,4.00,null,null,false,'championnat',null
  )::text,
  true
);
reset role;

-- Reactivate the real predictor only for this isolated title scenario.
update public.profiles set status='active'
where id='fc100000-0000-0000-0000-000000000002';
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_match_prediction(current_setting('test.title_match')::uuid,2,0);
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_match_prediction(current_setting('test.title_match')::uuid,1,0);
reset role;

set local session_replication_role=replica;
update public.matches
set kickoff_at='2014-03-17 20:00:00+00',
    match_date='2014-03-17',
    match_time='21:00:00'
where id=current_setting('test.title_match')::uuid;
set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.finalize_match_postgame(current_setting('test.title_match')::uuid,0,'[]'::jsonb,null,1);
select public.set_season_status('fc200000-0000-0000-0000-000000000003','archived');
reset role;

select ok(
  not exists(
    select 1 from public.season_awards
    where season_id='fc200000-0000-0000-0000-000000000003'
      and profile_id='fc100000-0000-0000-0000-000000000003'
  ),
  'test account receives no season title'
);
select ok(
  exists(
    select 1 from public.season_awards
    where season_id='fc200000-0000-0000-0000-000000000003'
      and profile_id='fc100000-0000-0000-0000-000000000002'
      and award_type='best_pred_overall'
  ),
  'best real predictor wins overall title when test account is excluded before rank'
);

select * from finish();
rollback;
