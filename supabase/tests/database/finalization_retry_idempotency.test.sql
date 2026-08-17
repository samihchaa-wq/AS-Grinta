begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data)
select ('f5000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('finalization-retry-%s@example.invalid',n),
       jsonb_build_object('first_name','Retry','last_name','Finalization')
from generate_series(1,14) n;

update public.profiles
set role=case when id='f5000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'f5000000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('f6000000-0000-0000-0000-000000000001','2105-2106','open');
insert into public.opponents(id,name)
values('f7000000-0000-0000-0000-000000000001','Retry Network FC');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('f8000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'f6000000-0000-0000-0000-000000000001','Joueur','Retry',
       n=1,true,n,('f5000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,13) n;

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='f5000000-0000-0000-0000-000000000001'
where key='sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"f5000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.finalization_retry_match',
  public.create_match_with_odds_and_sport_limit(
    'f6000000-0000-0000-0000-000000000001',
    'f7000000-0000-0000-0000-000000000001',
    ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile',2.1,3.2,2.9,14
  )::text,
  true
);
reset role;

update public.matches
set match_date=((now()-interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time=((now()-interval '2 hours') at time zone 'Europe/Paris')::time,
    kickoff_at=now()-interval '2 hours'
where id=current_setting('test.finalization_retry_match')::uuid;
update public.match_sport_workflows
set availability_state='closed'
where match_id=current_setting('test.finalization_retry_match')::uuid;
update public.match_sport_participants
set availability_status='available',convocation_status='convoked',selection_status='substitute'
where match_id=current_setting('test.finalization_retry_match')::uuid;

create or replace function pg_temp.retry_payload(p_score integer)
returns jsonb language sql stable as $function$
  with ranked as(
    select participant.id,player.position
    from public.match_sport_participants participant
    join public.season_players player on player.id=participant.season_player_id
    where participant.match_id=current_setting('test.finalization_retry_match')::uuid
      and participant.is_eligible
  )
  select jsonb_agg(jsonb_build_object(
    'participant_id',id,
    'present',true,
    'final_selection_status',case when position<=11 then 'starter' else 'substitute' end,
    'goals',case when position=1 then p_score else 0 end,
    'clean_sheet',false
  ) order by position)
  from ranked;
$function$;
grant execute on function pg_temp.retry_payload(integer) to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"f5000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.finalization_first_result',
  public.admin_finalize_match_sport_postgame(
    current_setting('test.finalization_retry_match')::uuid,
    2,1,pg_temp.retry_payload(2),'network-retry'
  )::text,
  true
);
reset role;

select is(
  (current_setting('test.finalization_first_result')::jsonb#>>'{version}')::integer,
  1,
  'la première finalisation crée la version 1'
);
select is(
  current_setting('test.finalization_first_result')::jsonb#>>'{validation_kind}',
  'initial',
  'la première finalisation reste une validation initiale'
);
select is(
  (select count(*) from public.match_sport_finalization_versions
   where match_id=current_setting('test.finalization_retry_match')::uuid),
  1::bigint,
  'une seule version historique existe après la première validation'
);
select is(
  (select count(*) from private.sport_admin_audit_log
   where match_id=current_setting('test.finalization_retry_match')::uuid
     and action in ('validate_final_attendance','correct_final_attendance')),
  1::bigint,
  'un seul audit existe après la première validation'
);

set local role authenticated;
select set_config(
  'test.finalization_retry_result',
  public.admin_finalize_match_sport_postgame(
    current_setting('test.finalization_retry_match')::uuid,
    2,1,pg_temp.retry_payload(2),'network-retry'
  )::text,
  true
);
reset role;

select is(
  (current_setting('test.finalization_retry_result')::jsonb#>>'{version}')::integer,
  1,
  'un retry strictement identique renvoie la version existante'
);
select is(
  current_setting('test.finalization_retry_result')::jsonb#>>'{validation_kind}',
  'unchanged',
  'le serveur identifie explicitement le retry comme inchangé'
);
select is(
  (select count(*) from public.match_sport_finalization_versions
   where match_id=current_setting('test.finalization_retry_match')::uuid),
  1::bigint,
  'le retry identique ne crée aucune version historique supplémentaire'
);
select is(
  (select count(*) from private.sport_admin_audit_log
   where match_id=current_setting('test.finalization_retry_match')::uuid
     and action in ('validate_final_attendance','correct_final_attendance')),
  1::bigint,
  'le retry identique ne crée aucun audit supplémentaire'
);

set local role authenticated;
select set_config(
  'test.finalization_correction_result',
  public.admin_finalize_match_sport_postgame(
    current_setting('test.finalization_retry_match')::uuid,
    2,0,pg_temp.retry_payload(2),'network-retry'
  )::text,
  true
);
reset role;

select is(
  (current_setting('test.finalization_correction_result')::jsonb#>>'{version}')::integer,
  2,
  'un changement réel avec le même motif crée bien une correction'
);
select is(
  current_setting('test.finalization_correction_result')::jsonb#>>'{validation_kind}',
  'correction',
  'un changement réel reste classé comme correction'
);
select is(
  (select count(*) from public.match_sport_finalization_versions
   where match_id=current_setting('test.finalization_retry_match')::uuid),
  2::bigint,
  'la correction réelle crée exactement une deuxième version'
);
select is(
  (select count(*) from private.sport_admin_audit_log
   where match_id=current_setting('test.finalization_retry_match')::uuid
     and action in ('validate_final_attendance','correct_final_attendance')),
  2::bigint,
  'la correction réelle crée exactement un deuxième audit'
);

set local role authenticated;
select set_config(
  'test.finalization_second_retry_result',
  public.admin_finalize_match_sport_postgame(
    current_setting('test.finalization_retry_match')::uuid,
    2,0,pg_temp.retry_payload(2),'network-retry'
  )::text,
  true
);
reset role;

select is(
  (current_setting('test.finalization_second_retry_result')::jsonb#>>'{version}')::integer,
  2,
  'le retry de la correction renvoie sa version existante'
);
select is(
  current_setting('test.finalization_second_retry_result')::jsonb#>>'{validation_kind}',
  'unchanged',
  'le retry de correction est lui aussi inchangé'
);
select is(
  (select count(*) from public.match_sport_finalization_versions
   where match_id=current_setting('test.finalization_retry_match')::uuid),
  2::bigint,
  'aucune troisième version artificielle n’est créée'
);
select is(
  (select count(*) from private.sport_admin_audit_log
   where match_id=current_setting('test.finalization_retry_match')::uuid
     and action in ('validate_final_attendance','correct_final_attendance')),
  2::bigint,
  'aucun troisième audit artificiel n’est créé'
);

select * from finish();
rollback;
