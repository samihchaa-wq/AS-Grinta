begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- ---------------------------------------------------------------------------
-- 1. Deux téléphones, même compte : un seul pilote réel.
-- ---------------------------------------------------------------------------
insert into auth.users(id,email,raw_user_meta_data) values
('4a100000-0000-0000-0000-000000000001','live-pilot-admin@example.invalid','{"first_name":"Live","last_name":"Pilot"}'::jsonb),
('4a100000-0000-0000-0000-000000000002','live-pilot-viewer@example.invalid','{"first_name":"Live","last_name":"Viewer"}'::jsonb);

update public.profiles
set role=case when id='4a100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id in (
  '4a100000-0000-0000-0000-000000000001',
  '4a100000-0000-0000-0000-000000000002'
);

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='4a100000-0000-0000-0000-000000000001'
where key='sports_management';

insert into public.seasons(id,name,status)
values('4a200000-0000-0000-0000-000000000001','2104-2105','open');

insert into public.matches(
  id,season_id,match_date,match_time,location,planned_duration_minutes,status,
  match_type,created_by
) values (
  '4a300000-0000-0000-0000-000000000001',
  '4a200000-0000-0000-0000-000000000001',
  current_date + 1,'20:00'::time,'domicile',90,'a_venir','amical',
  '4a100000-0000-0000-0000-000000000001'
);

insert into public.match_live_sessions(
  match_id,state,planned_duration_minutes,half,elapsed_seconds,running_since,
  updated_by
) values (
  '4a300000-0000-0000-0000-000000000001','running',90,1,0,now(),
  '4a100000-0000-0000-0000-000000000001'
);

-- Téléphone A prend la place.
select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.claim_match_live_pilot('4a300000-0000-0000-0000-000000000001',90)$$,
  'le téléphone A prend la place de pilote'
);
select ok(
  (public.get_match_live_state('4a300000-0000-0000-0000-000000000001')->>'pilot_is_me')::boolean,
  'le téléphone A se voit pilote'
);
select ok(
  not (public.get_match_live_state('4a300000-0000-0000-0000-000000000001') ? 'pilot_session_id'),
  'l’identifiant technique de la connexion pilote n’est jamais exposé'
);
reset role;

-- Téléphone B utilise le même compte, mais une autre session Auth.
select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000002"}',
  true
);
set local role authenticated;
select ok(
  (public.claim_match_live_pilot('4a300000-0000-0000-0000-000000000001',90)->>'pilot_active')::boolean
  and not (public.get_match_live_state('4a300000-0000-0000-0000-000000000001')->>'pilot_is_me')::boolean,
  'le téléphone B voit que la place est occupée sans la voler'
);

select ok(
  (public.take_over_match_live_pilot('4a300000-0000-0000-0000-000000000001')->>'pilot_is_me')::boolean,
  'Prendre la main transfère la place au téléphone B'
);
reset role;

-- L’ancien téléphone ne peut plus agir.
select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.coach_set_match_live_clock_state('4a300000-0000-0000-0000-000000000001','pause',null)$$,
  '42501',
  'Tu ne pilotes pas ce Live.',
  'l’ancien téléphone ne peut plus modifier le Live'
);
reset role;

-- Si B disparaît plus d’une minute, A peut reprendre sans rester bloqué.
update public.match_live_sessions
set pilot_heartbeat_at=now()-interval '61 seconds'
where match_id='4a300000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;
select ok(
  (public.claim_match_live_pilot('4a300000-0000-0000-0000-000000000001',90)->>'pilot_is_me')::boolean,
  'après environ une minute sans signal, un autre téléphone peut reprendre'
);
select ok(
  not (public.release_match_live_pilot('4a300000-0000-0000-0000-000000000001')->>'pilot_active')::boolean,
  'quitter volontairement libère immédiatement la place'
);
reset role;

-- ---------------------------------------------------------------------------
-- 2. Composition publiée visible avant qu’un coach ouvre le mode Piloter.
-- ---------------------------------------------------------------------------
insert into public.opponents(id,name)
values('4a500000-0000-0000-0000-000000000001','Published XI FC');

select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000003"}',
  true
);
set local role authenticated;
select set_config(
  'test.live_published_match',
  public.admin_create_match_complete(
    '4a200000-0000-0000-0000-000000000001',
    '4a500000-0000-0000-0000-000000000001',
    ((now()+interval '4 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '4 days') at time zone 'Europe/Paris')::time,
    'domicile',2.10,3.20,2.90,null,null,false,'amical',null
  )::text,
  true
);
reset role;

insert into public.match_compositions(
  match_id,formation_code,status,version,has_unpublished_changes,published_at,
  published_by,last_modified_by
) values (
  current_setting('test.live_published_match')::uuid,
  '4-2-1-3','published',1,false,now(),
  '4a100000-0000-0000-0000-000000000001',
  '4a100000-0000-0000-0000-000000000001'
);

insert into public.match_composition_publications(
  match_id,version,formation_code,snapshot,publication_kind,published_by
) values (
  current_setting('test.live_published_match')::uuid,
  1,
  '4-2-1-3',
  jsonb_build_object(
    'match_id',current_setting('test.live_published_match'),
    'formation_code','4-2-1-3',
    'status','published',
    'version',1,
    'has_unpublished_changes',false,
    'squad_size_exception_approved',false,
    'entries',jsonb_build_array(
      jsonb_build_object(
        'participant_id','4a600000-0000-0000-0000-000000000001',
        'display_name','Joueur publié',
        'is_goalkeeper',false,
        'zone','bench',
        'sort_order',0,
        'availability_status','available',
        'convocation_status','convoked',
        'selection_status','substitute'
      )
    )
  ),
  'prematch',
  '4a100000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000004"}',
  true
);
set local role authenticated;
select ok(
  not (public.get_match_live_state(current_setting('test.live_published_match')::uuid)->>'session_exists')::boolean
  and public.get_match_live_state(current_setting('test.live_published_match')::uuid)->'lineup'->>'formation_code'='4-2-1-3',
  'un spectateur reçoit la dernière composition publiée même sans session Live'
);
reset role;

-- Un brouillon ne doit jamais être exposé par ce raccourci.
update public.match_compositions
set status='draft',has_unpublished_changes=true
where match_id=current_setting('test.live_published_match')::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000004"}',
  true
);
set local role authenticated;
select ok(
  public.get_match_live_state(current_setting('test.live_published_match')::uuid)->'lineup' is null,
  'un brouillon n’est jamais exposé avant la création de la session Live'
);
reset role;

-- ---------------------------------------------------------------------------
-- 3. created_at dans l’après-match et notification de coup d’envoi.
-- ---------------------------------------------------------------------------
insert into public.matches(
  id,season_id,match_date,match_time,location,planned_duration_minutes,status,
  match_type,created_by
) values (
  '4a300000-0000-0000-0000-000000000002',
  '4a200000-0000-0000-0000-000000000001',
  current_date + 2,'20:00'::time,'domicile',90,'a_venir','amical',
  '4a100000-0000-0000-0000-000000000001'
),(
  '4a300000-0000-0000-0000-000000000003',
  '4a200000-0000-0000-0000-000000000001',
  current_date + 3,'20:00'::time,'domicile',90,'a_venir','amical',
  '4a100000-0000-0000-0000-000000000001'
);

insert into public.match_live_sessions(
  match_id,state,planned_duration_minutes,half,elapsed_seconds,running_since,
  exported,exported_at,updated_by
) values (
  '4a300000-0000-0000-0000-000000000002','finished',90,2,5400,null,
  true,now(),'4a100000-0000-0000-0000-000000000001'
),(
  '4a300000-0000-0000-0000-000000000003','not_started',90,1,0,null,
  false,null,'4a100000-0000-0000-0000-000000000001'
);

insert into public.match_live_events(
  match_id,event_type,minute,half,score_adverse_after,created_by,created_at
) values
('4a300000-0000-0000-0000-000000000002','goal_them',12,1,1,'4a100000-0000-0000-0000-000000000001',now()-interval '2 seconds'),
('4a300000-0000-0000-0000-000000000002','goal_them',12,1,2,'4a100000-0000-0000-0000-000000000001',now()-interval '1 second');

select set_config(
  'request.jwt.claims',
  '{"sub":"4a100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated","session_id":"4a400000-0000-0000-0000-000000000004"}',
  true
);
set local role authenticated;
select ok(
  (public.get_match_live_timeline('4a300000-0000-0000-0000-000000000002')->'events'->0) ? 'created_at'
  and (public.get_match_live_timeline('4a300000-0000-0000-0000-000000000002')->'events'->1) ? 'created_at',
  'l’après-match reçoit created_at pour distinguer deux validations dans la même minute'
);
reset role;

insert into public.match_live_notification_subscriptions(match_id,profile_id)
values(
  '4a300000-0000-0000-0000-000000000003',
  '4a100000-0000-0000-0000-000000000002'
);

update public.match_live_sessions
set state='running',running_since=now(),started_at=now(),updated_at=now()
where match_id='4a300000-0000-0000-0000-000000000003';

select is(
  (select count(*)::integer
   from private.match_live_notification_events
   where match_id='4a300000-0000-0000-0000-000000000003'
     and kind='kickoff'),
  1,
  'le coup d’envoi crée exactement une notification Live'
);

select ok(
  has_function_privilege('authenticated','public.claim_match_live_pilot(uuid,integer)','EXECUTE')
  and has_function_privilege('authenticated','public.take_over_match_live_pilot(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.claim_match_live_pilot(uuid,integer)','EXECUTE'),
  'les commandes de pilotage sont réservées aux utilisateurs authentifiés'
);

select * from finish();
rollback;
