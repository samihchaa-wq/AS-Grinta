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
where id in ('fc100000-0000-0000-0000-000000000001','fc100000-0000-0000-0000-000000000002','fc100000-0000-0000-0000-000000000003');

select ok(not has_table_privilege('authenticated','public.match_predictions','INSERT'),
  'authenticated cannot INSERT match_predictions directly');
select ok(has_table_privilege('authenticated','public.match_predictions','UPDATE'),
  'UPDATE grant remains only so RLS can silently deny direct mutations');

insert into public.seasons(id,name,status)
values('fc200000-0000-0000-0000-000000000001','2087-2088','open');
insert into public.opponents(id,name)
values('fc300000-0000-0000-0000-000000000001','Integrity FC');
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select set_config('test.match',public.admin_create_match_complete(
  'fc200000-0000-0000-0000-000000000001','fc300000-0000-0000-0000-000000000001',
  ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
  ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
  'domicile',2,3,4,null,null,false,'championnat',null)::text,true);
select set_config('test.internal',public.create_internal_match(
  'fc200000-0000-0000-0000-000000000001',
  ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
  ((now()+interval '3 days') at time zone 'Europe/Paris')::time,null)::text,true);
reset role;

select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select lives_ok(format('select public.save_match_prediction(%L::uuid,1,0)',current_setting('test.match')),
  'official RPC remains writable');
update public.match_predictions set predicted_score_as_grinta=9
where match_id=current_setting('test.match')::uuid
  and profile_id='fc100000-0000-0000-0000-000000000002';
select throws_ok(format('select public.save_match_prediction(%L::uuid,1,0)',current_setting('test.internal')),
  '22023','Les matchs entre nous ne sont pas ouverts aux pronostics.',
  'official RPC rejects internal match');
reset role;
select is((select predicted_score_as_grinta from public.match_predictions
  where match_id=current_setting('test.match')::uuid
    and profile_id='fc100000-0000-0000-0000-000000000002'),1,
  'direct authenticated UPDATE is RLS-filtered to zero rows');
select throws_ok(format(
  'insert into public.match_predictions(match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled) values(%L::uuid,%L::uuid,2,1,true)',
  current_setting('test.internal'),'fc100000-0000-0000-0000-000000000002'),
  '22023','Les matchs entre nous ne sont pas ouverts aux pronostics.',
  'trigger rejects privileged internal-match write');

select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.close_match_predictions(current_setting('test.match')::uuid);
reset role;
select set_config('test.updated',(select updated_at::text from public.matches where id=current_setting('test.match')::uuid),true);
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.admin_update_match_complete(
  current_setting('test.match')::uuid,'fc200000-0000-0000-0000-000000000001','fc300000-0000-0000-0000-000000000001',
  ((now()+interval '4 days') at time zone 'Europe/Paris')::date,
  ((now()+interval '4 days') at time zone 'Europe/Paris')::time,
  'domicile','a_venir',2,3,4,current_setting('test.updated')::timestamptz,null,null,false,'championnat',null);
reset role;
select is((select predictions_closed_at from public.matches where id=current_setting('test.match')::uuid),
  null::timestamptz,'reschedule clears stale manual close');

insert into public.seasons(id,name,status)
values('fc200000-0000-0000-0000-000000000002','2086-2087','open');
insert into public.season_players(id,season_id,first_name,last_name,is_goalkeeper,is_active,position)
values('fc400000-0000-0000-0000-000000000001','fc200000-0000-0000-0000-000000000002','Target','Season',false,true,1);
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.save_my_season_predictions('fc200000-0000-0000-0000-000000000002',
  jsonb_build_array(jsonb_build_object('season_player_id','fc400000-0000-0000-0000-000000000001','category','buts','predicted_value_30',10)));
reset role;
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_season_predictions_lock('fc200000-0000-0000-0000-000000000002',true);
select throws_ok($$select public.set_season_predictions_lock('fc200000-0000-0000-0000-000000000002'::uuid,false)$$,
  '22023','Les pronostics de saison révélés sont définitivement figés.',
  'filled revealed season predictions cannot unlock');
select public.set_season_status('fc200000-0000-0000-0000-000000000002','archived');
select throws_ok($$select public.set_season_status('fc200000-0000-0000-0000-000000000002'::uuid,'open')$$,
  '22023','Une saison avec des données de compétition ne peut pas être rouverte.',
  'archived competition season cannot reopen');
reset role;
select ok(exists(select 1 from public.season_prediction_roster_captures
  where season_id='fc200000-0000-0000-0000-000000000002'),
  'committed roster snapshot survives archive');

set local session_replication_role=replica;
update public.matches set kickoff_at='2015-03-17 20:00:00+00',match_date='2015-03-17',match_time='21:00:00'
where id=current_setting('test.match')::uuid;
set local session_replication_role=origin;
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
select public.finalize_match_postgame(current_setting('test.match')::uuid,1,'[]'::jsonb,null,2);
set local role authenticated;
select public.archive_match(current_setting('test.match')::uuid);
select public.set_season_status('fc200000-0000-0000-0000-000000000001','archived');
reset role;
update public.profiles set status='archived' where id='fc100000-0000-0000-0000-000000000002';
select ok(exists(select 1 from public.v_classement_general
  where profile_id='fc100000-0000-0000-0000-000000000002'),
  'archived real predictor remains in leaderboard');

update public.profiles set status='active' where id='fc100000-0000-0000-0000-000000000002';
insert into public.seasons(id,name,status)
values('fc200000-0000-0000-0000-000000000003','2085-2086','open');
insert into public.opponents(id,name)
values('fc300000-0000-0000-0000-000000000002','Title Integrity FC');
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select set_config('test.title_match',public.admin_create_match_complete(
  'fc200000-0000-0000-0000-000000000003','fc300000-0000-0000-0000-000000000002',
  ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
  ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
  'domicile',2,3,4,null,null,false,'championnat',null)::text,true);
reset role;
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated; select public.save_match_prediction(current_setting('test.title_match')::uuid,2,0); reset role;
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated; select public.save_match_prediction(current_setting('test.title_match')::uuid,1,0); reset role;
set local session_replication_role=replica;
update public.matches set kickoff_at='2014-03-17 20:00:00+00',match_date='2014-03-17',match_time='21:00:00'
where id=current_setting('test.title_match')::uuid;
set local session_replication_role=origin;
select set_config('request.jwt.claims','{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
select public.finalize_match_postgame(current_setting('test.title_match')::uuid,0,'[]'::jsonb,null,1);
set local role authenticated;
select public.archive_match(current_setting('test.title_match')::uuid);
select public.set_season_status('fc200000-0000-0000-0000-000000000003','archived');
reset role;
select ok(not exists(select 1 from public.season_awards
  where season_id='fc200000-0000-0000-0000-000000000003'
    and profile_id='fc100000-0000-0000-0000-000000000003'),
  'test account receives no season award');
select ok(exists(select 1 from public.season_awards
  where season_id='fc200000-0000-0000-0000-000000000003'
    and profile_id='fc100000-0000-0000-0000-000000000002'
    and award_type='best_pred_overall'),
  'best real predictor is promoted to overall title');

select * from finish();
rollback;
