begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Un coach qui n'a jamais publié de composition doit quand même pouvoir
-- lancer le Live, et le coup d'envoi doit publier l'équipe réellement alignée.

insert into auth.users(id,email,raw_user_meta_data) values
('fb100000-0000-0000-0000-000000000001','nocompo-admin@example.invalid','{"first_name":"Admin"}'::jsonb),
('fb100000-0000-0000-0000-000000000002','nocompo-alpha@example.invalid','{"first_name":"Alpha"}'::jsonb),
('fb100000-0000-0000-0000-000000000003','nocompo-beta@example.invalid','{"first_name":"Beta"}'::jsonb);

update public.profiles
set role=case when id='fb100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id in (
 'fb100000-0000-0000-0000-000000000001',
 'fb100000-0000-0000-0000-000000000002',
 'fb100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id,name,status)
values('fb200000-0000-0000-0000-000000000001','2101-2102','open');
insert into public.opponents(id,name)
values('fb300000-0000-0000-0000-000000000001','Sans Compo FC');

insert into public.season_players(
 id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
) values
('fb400000-0000-0000-0000-000000000001','fb200000-0000-0000-0000-000000000001','Alpha','Nocompo',true,true,1,'fb100000-0000-0000-0000-000000000002'),
('fb400000-0000-0000-0000-000000000002','fb200000-0000-0000-0000-000000000001','Beta','Nocompo',false,true,2,'fb100000-0000-0000-0000-000000000003');

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='fb100000-0000-0000-0000-000000000001'
where key='sports_management';

select set_config(
 'request.jwt.claims',
 '{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
 true
);
set local role authenticated;
select set_config(
 'test.nocompo_match',
 public.admin_create_match_complete(
   'fb200000-0000-0000-0000-000000000001',
   'fb300000-0000-0000-0000-000000000001',
   ((now()+interval '4 days') at time zone 'Europe/Paris')::date,
   ((now()+interval '4 days') at time zone 'Europe/Paris')::time,
   'domicile',2.10,3.20,2.90,null,null,false,'championnat',null
 )::text,
 true
);
reset role;

select set_config('request.jwt.claims','{"sub":"fb100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_my_match_availability(current_setting('test.nocompo_match')::uuid,'available',null);
reset role;
select set_config('request.jwt.claims','{"sub":"fb100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.set_my_match_availability(current_setting('test.nocompo_match')::uuid,'available',null);
reset role;

select set_config('request.jwt.claims','{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select public.admin_publish_match_convocations(current_setting('test.nocompo_match')::uuid,'Sans compo');
reset role;

-- Aucune composition n'a jamais été enregistrée ni publiée : c'est exactement
-- la situation qui bloquait le Live.
select is(
 (select count(*) from public.match_compositions
  where match_id=current_setting('test.nocompo_match')::uuid),
 0::bigint,
 'le match part sans aucune composition enregistrée'
);
select is(
 (select count(*) from public.match_composition_publications
  where match_id=current_setting('test.nocompo_match')::uuid),
 0::bigint,
 'le match part sans aucune composition publiée'
);

set local session_replication_role=replica;
update public.matches
set kickoff_at=now()+interval '10 minutes',
    match_date=((now()+interval '10 minutes') at time zone 'Europe/Paris')::date,
    match_time=((now()+interval '10 minutes') at time zone 'Europe/Paris')::time
where id=current_setting('test.nocompo_match')::uuid;
set local session_replication_role=origin;

select set_config('request.jwt.claims','{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select lives_ok(
 format('select public.open_match_live_workspace(%L::uuid,90)',current_setting('test.nocompo_match')),
 'le Live s’ouvre sans composition publiée'
);
reset role;

select is(
 (select count(*)::integer
  from public.match_composition_entries entry
  where entry.match_id=current_setting('test.nocompo_match')::uuid
    and entry.zone='bench'),
 2,
 'les convoqués arrivent sur le banc du Live'
);

select is(
 (select formation_code from public.match_compositions
  where match_id=current_setting('test.nocompo_match')::uuid),
 '4-2-1-3',
 'un dispositif par défaut est posé pour que l’écran soit utilisable'
);

select isnt(
 (select private.composition_snapshot(current_setting('test.nocompo_match')::uuid)),
 null,
 'le Live renvoie une composition au lieu de « Composition indisponible »'
);

-- Le coach place un titulaire, exactement ce que fait le glisser-déposer.
set local session_replication_role=replica;
update public.match_composition_entries entry
set zone='field',x=0.5,y=0.85,slot_label='GB'
where entry.match_id=current_setting('test.nocompo_match')::uuid
  and entry.participant_id=(
    select participant.id from public.match_sport_participants participant
    where participant.match_id=current_setting('test.nocompo_match')::uuid
      and participant.season_player_id='fb400000-0000-0000-0000-000000000001'
  );
set local session_replication_role=origin;

select set_config('request.jwt.claims','{"sub":"fb100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select lives_ok(
 format('select public.confirm_start_match_live(%L::uuid,%L)',current_setting('test.nocompo_match'),'Sans compo'),
 'le coup d’envoi part sans composition publiée au préalable'
);
reset role;

select is(
 (select count(*)::integer from public.match_composition_publications
  where match_id=current_setting('test.nocompo_match')::uuid),
 1,
 'le coup d’envoi publie la composition alignée'
);

select is(
 (select version from public.match_compositions
  where match_id=current_setting('test.nocompo_match')::uuid),
 1,
 'la composition passe en version publiée'
);

select is(
 (select workflow.composition_state::text from public.match_sport_workflows workflow
  where workflow.match_id=current_setting('test.nocompo_match')::uuid),
 'published',
 'le workflow du match suit la publication du coup d’envoi'
);

select is(
 (select (publication.snapshot->'entries')::jsonb #>> '{0,zone}'
  from public.match_composition_publications publication
  where publication.match_id=current_setting('test.nocompo_match')::uuid),
 'field',
 'le titulaire placé juste avant le coup d’envoi figure dans la publication'
);

select is(
 (select state::text from public.match_live_sessions
  where match_id=current_setting('test.nocompo_match')::uuid),
 'running',
 'le chronomètre est bien lancé'
);

select * from finish();
rollback;
