begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
('fa100000-0000-0000-0000-000000000001','cross-admin@example.invalid','{"first_name":"Admin"}'::jsonb),
('fa100000-0000-0000-0000-000000000002','cross-alpha@example.invalid','{"first_name":"Alpha"}'::jsonb),
('fa100000-0000-0000-0000-000000000003','cross-beta@example.invalid','{"first_name":"Beta"}'::jsonb);

update public.profiles
set role=case when id='fa100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id in (
 'fa100000-0000-0000-0000-000000000001',
 'fa100000-0000-0000-0000-000000000002',
 'fa100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id,name,status)
values('fa200000-0000-0000-0000-000000000001','2099-2100','open');
insert into public.opponents(id,name)
values('fa300000-0000-0000-0000-000000000001','Cross Stage FC');

insert into public.season_players(
 id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
) values
('fa400000-0000-0000-0000-000000000001','fa200000-0000-0000-0000-000000000001','Alpha','Cross',false,true,1,'fa100000-0000-0000-0000-000000000002'),
('fa400000-0000-0000-0000-000000000002','fa200000-0000-0000-0000-000000000001','Beta','Cross',false,true,2,'fa100000-0000-0000-0000-000000000003'),
('fa400000-0000-0000-0000-000000000003','fa200000-0000-0000-0000-000000000001','Ghost','Inactive',false,true,3,null);

update public.season_players
set is_active=false
where id='fa400000-0000-0000-0000-000000000003';

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='fa100000-0000-0000-0000-000000000001'
where key='sports_management';

select set_config(
 'request.jwt.claims',
 '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
 true
);
set local role authenticated;
select set_config(
 'test.cross_match',
 public.admin_create_match_complete(
   'fa200000-0000-0000-0000-000000000001',
   'fa300000-0000-0000-0000-000000000001',
   ((now()+interval '4 days') at time zone 'Europe/Paris')::date,
   ((now()+interval '4 days') at time zone 'Europe/Paris')::time,
   'domicile',2.10,3.20,2.90,null,null,false,'championnat',null
 )::text,
 true
);
reset role;

select is(
 (select count(*) from public.match_sport_workflows
  where match_id=current_setting('test.cross_match')::uuid),
 1::bigint,
 'null squad limit still creates sports workflow'
);
select is(
 (select squad_size_limit from public.match_sport_workflows
  where match_id=current_setting('test.cross_match')::uuid),
 14::smallint,
 'server resolves default squad limit'
);

select set_config(
 'test.cross_updated_at',
 (select updated_at::text from public.matches
  where id=current_setting('test.cross_match')::uuid),
 true
);
select set_config(
 'request.jwt.claims',
 '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
 true
);
set local role authenticated;
select ok(
 public.admin_update_match_complete(
   current_setting('test.cross_match')::uuid,
   'fa200000-0000-0000-0000-000000000001',
   'fa300000-0000-0000-0000-000000000001',
   ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
   ((now()+interval '3 days') at time zone 'Europe/Paris')::time,
   'domicile','a_venir',2.10,3.20,2.90,
   current_setting('test.cross_updated_at')::timestamptz,
   null,null,false,'championnat',null
 ),
 'null squad limit update stays on sports workflow'
);
reset role;

select is(
 (select workflow.availability_opens_at
  from public.match_sport_workflows workflow
  join public.matches match on match.id=workflow.match_id
  where workflow.match_id=current_setting('test.cross_match')::uuid),
 (select private.match_features_open_at(match.kickoff_at)
  from public.matches match
  where match.id=current_setting('test.cross_match')::uuid),
 'reschedule recalculates availability opening'
);
select is(
 (select workflow.late_withdrawal_cutoff_at
  from public.match_sport_workflows workflow
  where workflow.match_id=current_setting('test.cross_match')::uuid),
 (select ((((match.kickoff_at at time zone 'Europe/Paris')::date-1)+time '12:00') at time zone 'Europe/Paris')
  from public.matches match
  where match.id=current_setting('test.cross_match')::uuid),
 'reschedule recalculates waitlist cutoff'
);

select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_my_match_availability(current_setting('test.cross_match')::uuid,'available',null);
reset role;
select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_my_match_availability(current_setting('test.cross_match')::uuid,'available',null);
reset role;

select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.admin_set_match_convocation(
 current_setting('test.cross_match')::uuid,
 'fa400000-0000-0000-0000-000000000002',
 'not_convoked',true,'Cross stage'
);
select public.admin_publish_match_convocations(current_setting('test.cross_match')::uuid,'Cross stage');
select public.admin_save_match_composition(
 current_setting('test.cross_match')::uuid,
 '4-4-2',
 jsonb_build_array(
   jsonb_build_object(
     'participant_id',(select id from public.match_sport_participants
       where match_id=current_setting('test.cross_match')::uuid
         and season_player_id='fa400000-0000-0000-0000-000000000001'),
     'zone','field','x',0.5,'y',0.5,'slot_label','9','sort_order',0
   ),
   jsonb_build_object(
     'participant_id',(select id from public.match_sport_participants
       where match_id=current_setting('test.cross_match')::uuid
         and season_player_id='fa400000-0000-0000-0000-000000000002'),
     'zone','not_selected','x',null,'y',null,'slot_label',null,'sort_order',1
   )
 ),
 false,
 'Cross stage'
);
select public.admin_publish_match_composition(current_setting('test.cross_match')::uuid,false,'Cross stage');
reset role;

select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_my_match_availability(current_setting('test.cross_match')::uuid,'absent','After publication');
reset role;

select is(
 (select convocation_status::text from public.match_sport_participants
  where match_id=current_setting('test.cross_match')::uuid
    and season_player_id='fa400000-0000-0000-0000-000000000001'),
 'not_applicable'::text,
 'withdrawn player leaves current convocation'
);
select is(
 (select convocation_status::text from public.match_sport_participants
  where match_id=current_setting('test.cross_match')::uuid
    and season_player_id='fa400000-0000-0000-0000-000000000002'),
 'convoked'::text,
 'waitlisted player is promoted'
);

set local session_replication_role=replica;
update public.matches
set kickoff_at=now()+interval '10 minutes',
    match_date=((now()+interval '10 minutes') at time zone 'Europe/Paris')::date,
    match_time=((now()+interval '10 minutes') at time zone 'Europe/Paris')::time
where id=current_setting('test.cross_match')::uuid;
set local session_replication_role=origin;

select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.open_match_live_workspace(current_setting('test.cross_match')::uuid,90);
reset role;

select is(
 (select entry.zone::text
  from public.match_composition_entries entry
  join public.match_sport_participants participant on participant.id=entry.participant_id
  where entry.match_id=current_setting('test.cross_match')::uuid
    and participant.season_player_id='fa400000-0000-0000-0000-000000000001'),
 'not_selected'::text,
 'withdrawn player does not reappear in Live'
);
select is(
 (select entry.zone::text
  from public.match_composition_entries entry
  join public.match_sport_participants participant on participant.id=entry.participant_id
  where entry.match_id=current_setting('test.cross_match')::uuid
    and participant.season_player_id='fa400000-0000-0000-0000-000000000002'),
 'bench'::text,
 'promoted player is injected into Live bench'
);

select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select lives_ok(
 format('select public.confirm_start_match_live(%L::uuid,%L)',current_setting('test.cross_match'),'Cross stage'),
 'Live starts with reconciled current convocations'
);

select set_config(
 'test.internal_match',
 public.create_internal_match(
   'fa200000-0000-0000-0000-000000000001',
   ((now()+interval '1 day') at time zone 'Europe/Paris')::date,
   ((now()+interval '1 day') at time zone 'Europe/Paris')::time,
   null
 )::text,
 true
);
reset role;

select is(
 (select count(*) from public.match_predictions
  where match_id=current_setting('test.internal_match')::uuid),
 0::bigint,
 'internal match has no prediction rows'
);
select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select throws_ok(
 format('select public.save_match_prediction(%L::uuid,1,0)',current_setting('test.internal_match')),
 '22023',
 'Les matchs entre nous ne sont pas ouverts aux pronostics.',
 'direct RPC cannot save an internal-match prediction'
);
reset role;

select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select set_config(
 'test.final_match',
 public.admin_create_match_complete(
   'fa200000-0000-0000-0000-000000000001',
   'fa300000-0000-0000-0000-000000000001',
   ((now()+interval '2 days') at time zone 'Europe/Paris')::date,
   ((now()+interval '2 days') at time zone 'Europe/Paris')::time,
   'exterieur',2.20,3.10,3.00,null,null,false,'amical',null
 )::text,
 true
);
reset role;

select ok(
 exists(select 1 from public.match_sport_participants
  where match_id=current_setting('test.final_match')::uuid
    and season_player_id='fa400000-0000-0000-0000-000000000001'),
 'Alpha belongs to final-match snapshot before deactivation'
);
select ok(
 not exists(select 1 from public.match_sport_participants
  where match_id=current_setting('test.final_match')::uuid
    and season_player_id='fa400000-0000-0000-0000-000000000003'),
 'inactive Ghost does not belong to final-match snapshot'
);

update public.season_players
set is_active=false
where id='fa400000-0000-0000-0000-000000000001';

set local session_replication_role=replica;
update public.matches
set kickoff_at=timestamp with time zone '2015-03-17 20:00:00+00',
    match_date=date '2015-03-17',
    match_time=time '21:00:00'
where id=current_setting('test.final_match')::uuid;
set local session_replication_role=origin;

-- The internal helper is intentionally not executable by authenticated. Test
-- its business guard as owner while keeping the admin JWT in request claims.
select set_config('request.jwt.claims','{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
reset role;
select throws_ok(
 format(
   'select public.staff_set_match_attendance(%L::uuid,array[%L::uuid])',
   current_setting('test.final_match'),
   'fa400000-0000-0000-0000-000000000003'
 ),
 '22023',
 'Player is not active in the match season',
 'unrelated inactive player remains rejected'
);

set local role authenticated;
select lives_ok(
 format(
   $sql$select public.admin_finalize_match_sport_postgame(
     %L::uuid,1,0,
     (
       select jsonb_agg(jsonb_build_object(
         'participant_id',participant.id,
         'present',participant.season_player_id='fa400000-0000-0000-0000-000000000001',
         'final_selection_status',case
           when participant.season_player_id='fa400000-0000-0000-0000-000000000001' then 'starter'
           else 'not_selected'
         end,
         'goals',case
           when participant.season_player_id='fa400000-0000-0000-0000-000000000001' then 1
           else 0
         end,
         'clean_sheet',false
       ) order by participant.id)
       from public.match_sport_participants participant
       where participant.match_id=%L::uuid
         and participant.is_eligible
     ),
     'Historical inactive participant'
   )$sql$,
   current_setting('test.final_match'),
   current_setting('test.final_match')
 ),
 'modern finalization accepts deactivated participant already in match snapshot'
);
reset role;

select is(
 (select count(*) from public.match_attendance
  where match_id=current_setting('test.final_match')::uuid
    and season_player_id='fa400000-0000-0000-0000-000000000001'),
 1::bigint,
 'historical attendance is recorded'
);
select is(
 (select goals from public.match_player_stats
  where match_id=current_setting('test.final_match')::uuid
    and season_player_id='fa400000-0000-0000-0000-000000000001'),
 1,
 'historical goal survives roster deactivation'
);

select * from finish();
rollback;
