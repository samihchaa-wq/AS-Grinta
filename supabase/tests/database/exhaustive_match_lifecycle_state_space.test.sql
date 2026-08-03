begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data) values
('e1000000-0000-0000-0000-000000000001','match-space-admin@example.invalid','{"first_name":"Admin"}'::jsonb),
('e1000000-0000-0000-0000-000000000002','match-space-player@example.invalid','{"first_name":"Player"}'::jsonb);

update public.profiles
set role = case when id='e1000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active', updated_at=now()
where id in ('e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002');

insert into public.seasons(id,name,status) values
('e2000000-0000-0000-0000-000000000001','2098-2099','open'),
('e2000000-0000-0000-0000-000000000002','2097-2098','terminee');
insert into public.opponents(id,name) values
('e3000000-0000-0000-0000-000000000001','Lifecycle FC'),
('e3000000-0000-0000-0000-000000000002','Collision FC');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
) values (
  'e4000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001',
  'Player','Lifecycle',false,true,1,'e1000000-0000-0000-0000-000000000002'
);
update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='e1000000-0000-0000-0000-000000000001'
where key='sports_management';

create temporary table pg_temp.match_creation_state_space(
  season_kind text, location text, match_date date, odds numeric,
  expected_success boolean, observed_success boolean,
  observed_sqlstate text, observed_message text
) on commit drop;
grant select, insert, update, delete
on pg_temp.match_creation_state_space to authenticated;

select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;

do $state_space$
declare
  v_kind text; v_season uuid; v_location text; v_date date; v_odds numeric;
  v_match uuid; v_ok boolean; v_state text; v_message text;
begin
  foreach v_kind in array array['open','terminee','missing'] loop
    v_season := case v_kind
      when 'open' then 'e2000000-0000-0000-0000-000000000001'::uuid
      when 'terminee' then 'e2000000-0000-0000-0000-000000000002'::uuid
      else '00000000-0000-0000-0000-000000000000'::uuid end;
    foreach v_location in array array['domicile','exterieur','invalid'] loop
      foreach v_date in array array[date '1999-12-31',date '2000-01-01',date '2100-12-31',date '2101-01-01'] loop
        foreach v_odds in array array[1.00::numeric,1.01::numeric,100.00::numeric,100.01::numeric] loop
          v_match:=null; v_ok:=true; v_state:=null; v_message:=null;
          begin
            v_match:=public.create_match_with_odds(
              v_season,'e3000000-0000-0000-0000-000000000001',v_date,time '18:00',
              v_location,v_odds,v_odds,v_odds);
          exception when others then
            v_ok:=false; v_state:=sqlstate; v_message:=sqlerrm;
          end;
          insert into pg_temp.match_creation_state_space values(
            v_kind,v_location,v_date,v_odds,
            v_kind='open' and v_location in ('domicile','exterieur')
              and v_date between date '2000-01-01' and date '2100-12-31'
              and v_odds between 1.01 and 100,
            v_ok,v_state,v_message);
          if v_match is not null then perform public.delete_match(v_match); end if;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE match_create season=%s location=%s date=%s odds=%s expected=%s observed=%s sqlstate=%s message=%s',
  season_kind,location,match_date,odds,expected_success,observed_success,
  coalesce(observed_sqlstate,'-'),coalesce(observed_message,'-')))
from pg_temp.match_creation_state_space order by season_kind,location,match_date,odds;
select is((select count(*) from pg_temp.match_creation_state_space),144::bigint,'144 créations aux bornes exécutées');
select is((select count(*) from pg_temp.match_creation_state_space where expected_success is distinct from observed_success),0::bigint,'contrat de création respecté');

select throws_ok($$select public.create_match_with_odds(null,'e3000000-0000-0000-0000-000000000001',date '2099-01-01',time '18:00','domicile',2,3,4)$$,'22023','saison nulle refusée');
select throws_ok($$select public.create_match_with_odds('e2000000-0000-0000-0000-000000000001',null,date '2099-01-01',time '18:00','domicile',2,3,4)$$,'22023','adversaire nul refusé');
select throws_ok($$select public.create_match_with_odds('e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',null,time '18:00','domicile',2,3,4)$$,'22023','date nulle refusée');
select throws_ok($$select public.create_match_with_odds('e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',date '2099-01-01',null,'domicile',2,3,4)$$,'22023','heure nulle refusée');
reset role;
select set_config('request.jwt.claims','{"sub":"e1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.create_match_with_odds('e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',date '2099-02-01',time '18:00','domicile',2,3,4)$$,'42501','joueur: création refusée');
select throws_ok($$select public.archive_match('00000000-0000-0000-0000-000000000000')$$,'42501','joueur: archivage refusé');
select throws_ok($$select public.delete_match('00000000-0000-0000-0000-000000000000')$$,'42501','joueur: suppression refusée');

reset role;
select set_config('request.jwt.claims','{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select set_config('test.lifecycle_collision_match',public.create_match_with_odds_and_sport_limit(
  'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',
  date '2099-03-01',time '18:00','domicile',2,3,4,14)::text,true);
select throws_ok($$select public.create_match_with_odds('e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002',date '2099-03-01',time '18:00','exterieur',2,3,4)$$,'23505','collision exacte refusée');
select throws_ok($$select public.create_match_with_odds('e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002',date '2099-03-01',time '21:00','exterieur',2,3,4)$$,'23505','second match du même jour refusé');

reset role;
select set_config('request.jwt.claims','{}',true);
-- This lifecycle fixture deliberately uses a far-future match. Bypass only the
-- prediction-window trigger while seeding the row; timing behavior is covered
-- independently by prediction-window tests.
set local session_replication_role = replica;
insert into public.match_predictions(
  match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
) values(
  current_setting('test.lifecycle_collision_match')::uuid,
  'e1000000-0000-0000-0000-000000000002',2,1,true
)
on conflict(match_id,profile_id) do update
set predicted_score_as_grinta=excluded.predicted_score_as_grinta,
    predicted_score_adverse=excluded.predicted_score_adverse,
    is_filled=excluded.is_filled;
set local session_replication_role = origin;
select is(
  (
    select profile_id::text
    from public.match_predictions
    where match_id=current_setting('test.lifecycle_collision_match')::uuid
      and is_filled
  ),
  'e1000000-0000-0000-0000-000000000002',
  'la fixture attribue le pronostic au joueur attendu'
);
select set_config('request.jwt.claims','{"sub":"e1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
select set_config('test.lifecycle_participant_count',(select count(*)::text from public.match_sport_participants where match_id=current_setting('test.lifecycle_collision_match')::uuid),true);
set local role authenticated;
select ok(public.update_match_with_odds(
  current_setting('test.lifecycle_collision_match')::uuid,
  'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000001',
  date '2099-03-02',time '20:30','domicile','a_venir',2.2,3.3,4.4),'report par changement de date');
reset role;
select is((select match_date::text||' '||match_time::text from public.matches where id=current_setting('test.lifecycle_collision_match')::uuid),'2099-03-02 20:30:00','date et heure reportées');
select is((select (kickoff_at at time zone 'Europe/Paris')::date from public.matches where id=current_setting('test.lifecycle_collision_match')::uuid),date '2099-03-02','kickoff recalculé');
select is((select count(*) from public.match_predictions where match_id=current_setting('test.lifecycle_collision_match')::uuid and profile_id='e1000000-0000-0000-0000-000000000002' and is_filled),1::bigint,'pronostic conservé');
select is((select count(*)::text from public.match_sport_participants where match_id=current_setting('test.lifecycle_collision_match')::uuid),current_setting('test.lifecycle_participant_count'),'participants conservés');
select is((select count(*) from public.match_sport_workflows where match_id=current_setting('test.lifecycle_collision_match')::uuid),1::bigint,'workflow conservé');

set local role authenticated;
select set_config('test.lifecycle_replacement_match',public.create_match_with_odds(
  'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002',
  date '2099-03-01',time '21:00','exterieur',2,3,4)::text,true);

create temporary table pg_temp.match_status_state_space(
  proposed_status text primary key, expected_success boolean,
  observed_success boolean, observed_sqlstate text, observed_message text
) on commit drop;
do $state_space$
declare v_status text; v_ok boolean; v_state text; v_message text;
begin
  foreach v_status in array array['a_venir','en_cours','termine','archive','annule','reporte','invalid'] loop
    v_ok:=true;v_state:=null;v_message:=null;
    begin
      perform public.update_match_with_odds(
        current_setting('test.lifecycle_replacement_match')::uuid,
        'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002',
        date '2099-03-01',time '21:00','exterieur',v_status,
        case when v_status='a_venir' then 2 else null end,
        case when v_status='a_venir' then 3 else null end,
        case when v_status='a_venir' then 4 else null end);
    exception when others then v_ok:=false;v_state:=sqlstate;v_message:=sqlerrm; end;
    insert into pg_temp.match_status_state_space values(v_status,v_status in ('a_venir','termine','archive'),v_ok,v_state,v_message);
  end loop;
end;
$state_space$;
select diag(format('STATE_SPACE match_status proposed=%s expected=%s observed=%s sqlstate=%s message=%s',proposed_status,expected_success,observed_success,coalesce(observed_sqlstate,'-'),coalesce(observed_message,'-')))
from pg_temp.match_status_state_space order by proposed_status;
select is((select count(*) from pg_temp.match_status_state_space where expected_success is distinct from observed_success),0::bigint,'contrat des sept statuts stable');

select public.update_match_with_odds(
  current_setting('test.lifecycle_replacement_match')::uuid,
  'e2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000002',
  date '2099-03-01',time '21:00','exterieur','termine',null,null,null);
select ok(public.archive_match(current_setting('test.lifecycle_replacement_match')::uuid),'archivage initial réussi');
select throws_ok(format('select public.archive_match(%L::uuid)',current_setting('test.lifecycle_replacement_match')),'P0002','double archivage refusé');

select ok(public.delete_match(current_setting('test.lifecycle_collision_match')::uuid),'suppression du match reporté');
reset role;
select is((select count(*) from public.matches where id=current_setting('test.lifecycle_collision_match')::uuid),0::bigint,'match supprimé');
select is((select count(*) from public.match_odds where match_id=current_setting('test.lifecycle_collision_match')::uuid),0::bigint,'cotes supprimées');
select is((select count(*) from public.match_predictions where match_id=current_setting('test.lifecycle_collision_match')::uuid),0::bigint,'pronostics supprimés');
select is((select count(*) from public.match_sport_workflows where match_id=current_setting('test.lifecycle_collision_match')::uuid),0::bigint,'workflow supprimé');
select is((select count(*) from public.match_sport_participants where match_id=current_setting('test.lifecycle_collision_match')::uuid),0::bigint,'participants supprimés');

select * from finish();
rollback;