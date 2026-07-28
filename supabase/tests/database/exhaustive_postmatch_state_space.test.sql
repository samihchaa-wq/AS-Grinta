begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data)
select ('f1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('postmatch-space-%s@example.invalid',n),
       jsonb_build_object('first_name',format('Profil%s',n),'last_name','Postmatch')
from generate_series(1,14) n;

update public.profiles
set role=case when id='f1000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'f1000000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('f2000000-0000-0000-0000-000000000001','2104-2105','open');
insert into public.opponents(id,name)
values('f3000000-0000-0000-0000-000000000001','Postmatch State FC');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('f4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'f2000000-0000-0000-0000-000000000001',format('Joueur%s',n),'Postmatch',
       n=1,true,n,('f1000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,13) n;

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='f1000000-0000-0000-0000-000000000001'
where key='sports_management';
select set_config('request.jwt.claims',
  '{"sub":"f1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select set_config('test.postmatch_match',public.create_match_with_odds_and_sport_limit(
  'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
  ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
  ((now()+interval '3 days') at time zone 'Europe/Paris')::time,
  'domicile',2.1,3.2,2.9,14)::text,true);
reset role;

update public.matches
set match_date=((now()-interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time=((now()-interval '2 hours') at time zone 'Europe/Paris')::time,
    kickoff_at=now()-interval '2 hours'
where id=current_setting('test.postmatch_match')::uuid;
update public.match_sport_workflows
set availability_state='closed'
where match_id=current_setting('test.postmatch_match')::uuid;
update public.match_sport_participants
set availability_status='available',convocation_status='convoked',selection_status='substitute'
where match_id=current_setting('test.postmatch_match')::uuid;

create or replace function pg_temp.postmatch_payload(
  p_present integer,p_starters integer,p_score integer,p_goal_mode text,p_clean_mode text
)
returns jsonb language sql stable as $function$
  with ranked as(
    select participant.id,player.position,player.is_goalkeeper
    from public.match_sport_participants participant
    join public.season_players player on player.id=participant.season_player_id
    where participant.match_id=current_setting('test.postmatch_match')::uuid
      and participant.is_eligible
  )
  select jsonb_agg(jsonb_build_object(
    'participant_id',id,
    'present',position<=p_present,
    'final_selection_status',case
      when position<=p_starters then 'starter'
      when position<=p_present then 'substitute'
      else 'not_selected' end,
    'goals',case when position=1 then case p_goal_mode
      when 'zero' then 0 when 'equal' then p_score else p_score+1 end else 0 end,
    'clean_sheet',case p_clean_mode
      when 'keeper' then position=1
      when 'field' then position=2
      when 'two' then position<=2
      else false end
  ) order by position)
  from ranked;
$function$;
grant execute on function pg_temp.postmatch_payload(integer,integer,integer,text,text) to authenticated;

create or replace function pg_temp.postmatch_composition_payload()
returns jsonb language sql stable as $function$
  with ranked as(
    select participant.id,player.position
    from public.match_sport_participants participant
    join public.season_players player on player.id=participant.season_player_id
    where participant.match_id=current_setting('test.postmatch_match')::uuid
      and participant.is_eligible
  )
  select jsonb_agg(jsonb_build_object(
    'participant_id',id,
    'zone',case when position<=11 then 'field' else 'bench' end,
    'x',case when position<=11 then 0.05+(position%10)*0.08 else null end,
    'y',case when position<=11 then 0.20+(position%4)*0.18 else null end,
    'slot_label',null,'sort_order',position
  ) order by position)
  from ranked;
$function$;
grant execute on function pg_temp.postmatch_composition_payload() to authenticated;

create temporary table pg_temp.postmatch_state_space(
  case_number integer primary key,score_grinta integer,score_adverse integer,
  present_count integer,starter_count integer,goal_mode text,clean_mode text,
  expected_success boolean,observed_success boolean,observed_sqlstate text,
  observed_message text,observed_version integer
) on commit drop;
grant select,insert,update,delete on pg_temp.postmatch_state_space to authenticated;

set local role authenticated;
do $state_space$
declare
  sg integer;sa integer;pc integer;sc integer;gm text;cm text;
  ok boolean;st text;msg text;version integer;case_no integer:=0;expected boolean;
begin
  foreach sg in array array[0,2] loop
    foreach sa in array array[0,1] loop
      foreach pc in array array[0,1,13] loop
        foreach sc in array array[0,11,12] loop
          foreach gm in array array['zero','equal','over'] loop
            foreach cm in array array['none','keeper','field','two'] loop
              case_no:=case_no+1;ok:=true;st:=null;msg:=null;version:=null;
              expected:=pc>0 and sc<=11 and sc<=pc
                and (case gm when 'zero' then 0 when 'equal' then sg else sg+1 end)<=sg
                and (cm='none' or (cm='keeper' and pc>=1 and sa=0));
              begin
                select (public.admin_finalize_match_sport_postgame(
                  current_setting('test.postmatch_match')::uuid,sg,sa,
                  pg_temp.postmatch_payload(pc,sc,sg,gm,cm),
                  format('case=%s',case_no))#>>'{version}')::integer into version;
              exception when others then ok:=false;st:=sqlstate;msg:=sqlerrm; end;
              insert into pg_temp.postmatch_state_space values(
                case_no,sg,sa,pc,sc,gm,cm,expected,ok,st,msg,version);
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$state_space$;
reset role;

select diag(format(
  'STATE_SPACE postmatch case=%s score=%s-%s present=%s starters=%s goals=%s clean=%s expected=%s observed=%s sqlstate=%s version=%s message=%s',
  case_number,score_grinta,score_adverse,present_count,starter_count,goal_mode,clean_mode,
  expected_success,observed_success,coalesce(observed_sqlstate,'-'),coalesce(observed_version::text,'-'),coalesce(observed_message,'-')))
from pg_temp.postmatch_state_space order by case_number;
select is((select count(*) from pg_temp.postmatch_state_space),432::bigint,'432 finalisations combinatoires exécutées');
select is((select count(*) from pg_temp.postmatch_state_space where expected_success),36::bigint,'36 combinaisons valides identifiées par oracle');
select is((select count(*) from pg_temp.postmatch_state_space where expected_success is distinct from observed_success),0::bigint,'toutes les finalisations suivent les invariants serveur');
select is((select count(*) from public.match_sport_finalization_versions where match_id=current_setting('test.postmatch_match')::uuid),36::bigint,'chaque succès crée exactement une version historique');
select is((select version from public.match_sport_finalizations where match_id=current_setting('test.postmatch_match')::uuid),36,'la version active suit les 36 succès');
select is((select count(*) from public.match_attendance where match_id=current_setting('test.postmatch_match')::uuid),13::bigint,'la dernière correction remplace les présences par treize présents');
select is((select goals from public.match_player_stats where match_id=current_setting('test.postmatch_match')::uuid and season_player_id='f4000000-0000-0000-0000-000000000001'),2,'la dernière correction remplace les buts sans cumul');
select is(public.admin_get_match_sport_statistics_integrity(current_setting('test.postmatch_match')::uuid)#>>'{all_ok}','true','intégrité statistique complète après 36 versions');

select set_config('request.jwt.claims','{"sub":"f1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,2,1,
  pg_temp.postmatch_payload(13,11,2,'equal','none'),'joueur')$$,
  '42501','Active administrator role required','un joueur ne peut pas corriger le match');
reset role;
select set_config('request.jwt.claims','{"sub":"f1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,-1,0,
  pg_temp.postmatch_payload(13,11,0,'zero','none'),'score négatif')$$,
  '22023','score négatif refusé');
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,100,0,
  pg_temp.postmatch_payload(13,11,0,'zero','none'),'score haut')$$,
  '22023','score supérieur à 99 refusé');
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,null::integer,0,
  pg_temp.postmatch_payload(13,11,0,'zero','none'),'score nul')$$,
  '22023','score nul refusé');
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,2,1,null,'payload nul')$$,
  '22023','payload nul refusé');
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,2,1,'{}'::jsonb,'payload objet')$$,
  '22023','payload objet refusé');
select throws_ok($$select public.admin_finalize_match_sport_postgame(
  current_setting('test.postmatch_match')::uuid,2,1,
  pg_temp.postmatch_payload(13,11,2,'equal','none')||jsonb_build_array(pg_temp.postmatch_payload(13,11,2,'equal','none')->0),'doublon')$$,
  '22023','participant dupliqué refusé');

select is(public.admin_create_postmatch_composition(
  current_setting('test.postmatch_match')::uuid,'4-3-3',
  pg_temp.postmatch_composition_payload(),false,'composition après match')#>>'{status}',
  'published','la composition post-match est publiée');
select ok(
  (
    select composition.status='published'
      and composition.closed_at is not null
      and not composition.has_unpublished_changes
    from public.match_compositions composition
    where composition.match_id=current_setting('test.postmatch_match')::uuid
  ),
  'la composition post-match est verrouillée après sa publication'
);
select throws_ok($$select public.admin_create_postmatch_composition(
  current_setting('test.postmatch_match')::uuid,'4-3-3',
  pg_temp.postmatch_composition_payload(),false,'deuxième tentative')$$,
  '55000','une deuxième composition post-match est refusée');

select * from finish();
rollback;