begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data)
select ('b1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('composition-state-%s@example.invalid',n),
       jsonb_build_object('first_name',format('Profil%s',n),'last_name','State')
from generate_series(1,17) n;
update public.profiles
set role=case when id='b1000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'b1000000-0000-0000-0000-%';
insert into public.seasons(id,name,status)
values('b2000000-0000-0000-0000-000000000001','2102-2103','open');
insert into public.opponents(id,name)
values('b3000000-0000-0000-0000-000000000001','Composition State FC');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('b4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'b2000000-0000-0000-0000-000000000001',format('Joueur%s',n),'State',
       n=1,true,n,('b1000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,16) n;
insert into public.matches(
  id,season_id,opponent_id,match_date,match_time,kickoff_at,location,
  planned_duration_minutes,status,created_by
) values(
  'b5000000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  ((now()+interval '5 days') at time zone 'Europe/Paris')::date,
  ((now()+interval '5 days') at time zone 'Europe/Paris')::time,
  now()+interval '5 days','domicile',90,'a_venir',
  'b1000000-0000-0000-0000-000000000001'
);
update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='b1000000-0000-0000-0000-000000000001'
where key='sports_management';
select set_config('request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
select private.sync_match_sport_workflow('b5000000-0000-0000-0000-000000000001');
update public.match_sport_participants
set availability_status='available',availability_updated_at=now(),
    availability_updated_by='b1000000-0000-0000-0000-000000000001',
    waitlist_turn_should_consume=false,waitlist_turn_state='waived',updated_at=now()
where match_id='b5000000-0000-0000-0000-000000000001';

create or replace function pg_temp.prepare_convocations(p_selected integer)
returns void language plpgsql as $function$
begin
  with ranked as(
    select participant.id,row_number() over(order by player.position,participant.id)::integer n
    from public.match_sport_participants participant
    join public.season_players player on player.id=participant.season_player_id
    where participant.match_id='b5000000-0000-0000-0000-000000000001'
      and participant.is_eligible
  )
  update public.match_sport_participants participant
  set convocation_status=case when ranked.n<=p_selected
        then 'convoked'::public.sport_convocation_status
        else 'not_convoked'::public.sport_convocation_status end,
      convocation_manual_override=true,availability_status='available',updated_at=now()
  from ranked where participant.id=ranked.id;
end;
$function$;

create or replace function pg_temp.composition_payload(p_selected integer,p_field integer)
returns jsonb language sql stable as $function$
  with ranked as(
    select participant.id,row_number() over(order by player.position,participant.id)::integer n
    from public.match_sport_participants participant
    join public.season_players player on player.id=participant.season_player_id
    where participant.match_id='b5000000-0000-0000-0000-000000000001'
      and participant.is_eligible
  )
  select jsonb_agg(jsonb_build_object(
    'participant_id',id,
    'zone',case when n<=p_field then 'field' when n<=p_selected then 'bench' else 'not_selected' end,
    'x',case when n<=p_field then 0.05+(n%10)*0.08 else null end,
    'y',case when n<=p_field then 0.20+(n%4)*0.18 else null end,
    'slot_label',null,'sort_order',n
  ) order by n) from ranked;
$function$;

create or replace function pg_temp.effectif_payload(p_selected integer)
returns jsonb language sql stable as $function$
  select jsonb_agg(jsonb_build_object(
    'season_player_id',id,
    'status',case when position<=p_selected then 'convoked' else 'not_convoked' end
  ) order by position)
  from public.season_players
  where season_id='b2000000-0000-0000-0000-000000000001';
$function$;

create temporary table pg_temp.composition_state_space(
  selected_count integer,field_count integer,squad_limit integer,allow_exception boolean,
  expected_success boolean,observed_success boolean,observed_sqlstate text,observed_message text
) on commit drop;

do $state_space$
declare
  s integer; f integer; l integer; a boolean; ok boolean; st text; msg text;
begin
  foreach s in array array[0,1,10,11,12,14,15,16] loop
    foreach f in array array[0,1,10,11,12] loop
      if f>s then continue; end if;
      foreach l in array array[1,11,14,16] loop
        foreach a in array array[false,true] loop
          perform pg_temp.prepare_convocations(s);
          update public.match_sport_workflows set squad_size_limit=l
          where match_id='b5000000-0000-0000-0000-000000000001';
          ok:=true;st:=null;msg:=null;
          begin
            perform private.save_match_composition(
              'b5000000-0000-0000-0000-000000000001','state-space',
              pg_temp.composition_payload(s,f),a,
              format('selected=%s field=%s limit=%s allow=%s',s,f,l,a));
          exception when others then ok:=false;st:=sqlstate;msg:=sqlerrm; end;
          insert into pg_temp.composition_state_space
          values(s,f,l,a,f<=11 and(s<=l or a),ok,st,msg);
        end loop;
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE composition selected=%s field=%s limit=%s allow=%s expected=%s observed=%s sqlstate=%s message=%s',
  selected_count,field_count,squad_limit,allow_exception,expected_success,observed_success,
  coalesce(observed_sqlstate,'-'),coalesce(observed_message,'-')))
from pg_temp.composition_state_space
order by selected_count,field_count,squad_limit,allow_exception;
select is((select count(*) from pg_temp.composition_state_space),240::bigint,'240 combinaisons de composition exécutées');
select is((select count(*) from pg_temp.composition_state_space where expected_success is distinct from observed_success),0::bigint,'toutes les limites de composition suivent le contrat');
select is((select count(*) from pg_temp.composition_state_space where not observed_success and observed_sqlstate<>'22023'),0::bigint,'les refus de composition utilisent une erreur de validation stable');

update public.match_sport_workflows set squad_size_limit=16
where match_id='b5000000-0000-0000-0000-000000000001';
select pg_temp.prepare_convocations(11);
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','duplicate',
  pg_temp.composition_payload(11,11)||jsonb_build_array(pg_temp.composition_payload(11,11)->0),
  false,'participant dupliqué')$$,'22023','participant dupliqué refusé');
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','missing',
  (select jsonb_agg(value) from jsonb_array_elements(pg_temp.composition_payload(11,11))
   with ordinality item(value,pos) where pos<16),false,'participant manquant')$$,
  '22023','participant manquant refusé');
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','identity',
  jsonb_set(pg_temp.composition_payload(11,11),'{0,participant_id}',
    '"00000000-0000-0000-0000-000000000000"'::jsonb),false,'identité étrangère')$$,
  '22023','identité hors match refusée');
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','coordinate',
  jsonb_set(pg_temp.composition_payload(11,11),'{0,x}','null'::jsonb),false,'x manquant')$$,
  '22023','titulaire sans coordonnées refusé');
select pg_temp.prepare_convocations(12);
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','coordinate',
  jsonb_set(jsonb_set(pg_temp.composition_payload(12,11),'{11,x}','0.5'::jsonb),
    '{11,y}','0.5'::jsonb),false,'coordonnées banc')$$,
  '22023','remplaçant avec coordonnées refusé');
select pg_temp.prepare_convocations(1);
update public.match_sport_participants set availability_status='absent'
where id=(select (value->>'participant_id')::uuid
          from jsonb_array_elements(pg_temp.composition_payload(1,1)) item(value) limit 1);
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','absent',
  pg_temp.composition_payload(1,1),false,'absent')$$,'22023','joueur absent sélectionné refusé');
select pg_temp.prepare_convocations(1);
update public.match_sport_participants set convocation_status='not_convoked'
where id=(select (value->>'participant_id')::uuid
          from jsonb_array_elements(pg_temp.composition_payload(1,1)) item(value) limit 1);
select throws_ok($$select private.save_match_composition(
  'b5000000-0000-0000-0000-000000000001','not-convoked',
  pg_temp.composition_payload(1,1),false,'non convoqué')$$,'22023','joueur non convoqué sélectionné refusé');

set local role authenticated;
select is(public.admin_publish_match_effectif(
  'b5000000-0000-0000-0000-000000000001',16,pg_temp.effectif_payload(16),'publication complète')#>>'{convocation_version}',
  '1','publication initiale des convocations version 1');
select is(public.admin_save_match_composition(
  'b5000000-0000-0000-0000-000000000001','4-3-3',pg_temp.composition_payload(16,11),false,'enregistrement initial')#>>'{field_count}',
  '11','enregistrement initial valide');
select is(public.admin_publish_match_composition(
  'b5000000-0000-0000-0000-000000000001',false,'synchronisation initiale')#>>'{version}',
  '1','synchronisation initiale version 1');
select is(public.admin_publish_match_effectif(
  'b5000000-0000-0000-0000-000000000001',14,pg_temp.effectif_payload(14),'réduction à quatorze')#>>'{convocation_version}',
  '2','republication des convocations version 2');
select is(public.admin_save_match_composition(
  'b5000000-0000-0000-0000-000000000001','4-4-2',pg_temp.composition_payload(14,10),false,'modification')#>>'{has_unpublished_changes}',
  'false','modification immédiatement persistée');
select is(public.admin_publish_match_composition(
  'b5000000-0000-0000-0000-000000000001',false,'synchronisation')#>>'{version}',
  '2','synchronisation version 2');
reset role;

update public.match_sport_participants
set final_presence_status=case when convocation_status='convoked'
  then 'present'::public.sport_final_presence_status
  else 'actual_absent'::public.sport_final_presence_status end
where match_id='b5000000-0000-0000-0000-000000000001';
create temporary table pg_temp.publication_status_state_space(
  match_status text,expected_success boolean,observed_success boolean,
  observed_sqlstate text,observed_message text
) on commit drop;
do $state_space$
declare s text; ok boolean; st text; msg text;
begin
  foreach s in array array['a_venir','en_cours','termine','archive'] loop
    ok:=true;st:=null;msg:=null;
    begin
      update public.matches set status=s
      where id='b5000000-0000-0000-0000-000000000001';
      update public.match_compositions set has_unpublished_changes=true
      where match_id='b5000000-0000-0000-0000-000000000001';
      perform private.publish_match_composition(
        'b5000000-0000-0000-0000-000000000001',false,format('status %s',s));
    exception when others then ok:=false;st:=sqlstate;msg:=sqlerrm; end;
    insert into pg_temp.publication_status_state_space
    values(s,s='a_venir',ok,st,msg);
  end loop;
end;
$state_space$;
select diag(format(
  'STATE_SPACE composition_publication status=%s expected=%s observed=%s sqlstate=%s message=%s',
  match_status,expected_success,observed_success,coalesce(observed_sqlstate,'-'),coalesce(observed_message,'-')))
from pg_temp.publication_status_state_space order by match_status;
select is((select count(*) from pg_temp.publication_status_state_space where expected_success is distinct from observed_success),0::bigint,'publication ordinaire limitée aux matchs à venir');

select * from finish();
rollback;