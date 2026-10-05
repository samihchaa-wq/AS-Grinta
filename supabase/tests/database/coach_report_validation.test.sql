begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Un coach qui n'est pas administrateur valide le compte rendu du match qu'il
-- vient de piloter. Il ne peut pas pour autant appeler directement les
-- fonctions d'administration de fin de match.

insert into auth.users(id,email,raw_user_meta_data)
select ('c7100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('coach-report-%s@example.invalid',n),
       jsonb_build_object('first_name','Coach','last_name','Report')
from generate_series(1,17) n;

-- 1 : administrateur ; 2..16 : joueurs ; 17 : coach (pas administrateur).
update public.profiles
set role=case when id='c7100000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'c7100000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('c7200000-0000-0000-0000-000000000001','2207-2208','open');
insert into public.opponents(id,name)
values('c7300000-0000-0000-0000-000000000001','Coach Report FC');

insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('c7400000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'c7200000-0000-0000-0000-000000000001',
       format('Joueur%s',n),'Report',
       n=1,true,n,('c7100000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,15) n;

insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,is_coach,profile_id
) values (
  'c7400000-0000-0000-0000-000000000099',
  'c7200000-0000-0000-0000-000000000001',
  'Coach','Report',false,true,true,
  'c7100000-0000-0000-0000-000000000017'
);

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='c7100000-0000-0000-0000-000000000001'
where key='sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"c7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.coach_match',
  public.create_match_with_odds_and_sport_limit(
    'c7200000-0000-0000-0000-000000000001',
    'c7300000-0000-0000-0000-000000000001',
    ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile',2.1,3.2,2.9,16
  )::text,
  true
);
reset role;

update public.matches
set match_date=((now()-interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time=((now()-interval '2 hours') at time zone 'Europe/Paris')::time,
    kickoff_at=now()-interval '2 hours'
where id=current_setting('test.coach_match')::uuid;
update public.match_sport_workflows
set availability_state='closed'
where match_id=current_setting('test.coach_match')::uuid;
update public.match_sport_participants
set availability_status='available',convocation_status='convoked',selection_status='substitute'
where match_id=current_setting('test.coach_match')::uuid;

-- Le Live vient d'être terminé par le coach.
insert into public.match_live_sessions(
  match_id,state,planned_duration_minutes,half,elapsed_seconds,running_since,
  started_at,finished_at,updated_by
) values (
  current_setting('test.coach_match')::uuid,'finished',90,2,5400,null,
  now()-interval '2 hours',now(),'c7100000-0000-0000-0000-000000000017'
);

create or replace function pg_temp.participant_of(p_position integer)
returns uuid language sql stable as $function$
  select participant.id
  from public.match_sport_participants participant
  join public.season_players player on player.id=participant.season_player_id
  where participant.match_id=current_setting('test.coach_match')::uuid
    and player.position=p_position;
$function$;

create or replace function pg_temp.report_lineup()
returns jsonb language sql stable as $function$
  select jsonb_build_object(
    'formation_code','4-4-2',
    'entries', jsonb_agg(jsonb_build_object(
      'participant_id',participant.id,
      'zone',case
        when player.position<=11 then 'field'
        when player.position<=14 then 'bench'
        else 'not_selected'
      end,
      'x',case when player.position<=11
        then round((0.05*player.position)::numeric,6) else null end,
      'y',case when player.position<=11
        then round((0.05*player.position)::numeric,6) else null end,
      'sort_order',coalesce(player.position,99)
    ) order by player.position)
  )
  from public.match_sport_participants participant
  join public.season_players player on player.id=participant.season_player_id
  where participant.match_id=current_setting('test.coach_match')::uuid
    and participant.is_eligible
    and player.position is not null;
$function$;

-- Paquets préparés avant de changer de rôle : un coach ou un joueur ne lit
-- pas directement ces tables.
select set_config('test.coach_lineup', pg_temp.report_lineup()::text, true);
select set_config(
  'test.coach_goals',
  jsonb_build_array(jsonb_build_object(
    'minute',10,'team_side','as_grinta',
    'scorer_participant_id',pg_temp.participant_of(2),'assist_kind','none','is_own_goal',false
  ))::text,
  true
);

-- ---------------------------------------------------------------------------
-- 1. Un joueur ne valide pas le compte rendu.
-- ---------------------------------------------------------------------------
select set_config(
  'request.jwt.claims',
  '{"sub":"c7100000-0000-0000-0000-000000000005","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.admin_submit_match_sport_report(
    current_setting('test.coach_match')::uuid,1,0,
    current_setting('test.coach_lineup')::jsonb,
    current_setting('test.coach_goals')::jsonb,
    'tentative joueur'
  )$$,
  '42501',
  null,
  'un joueur ne peut pas valider le compte rendu'
);
reset role;

-- ---------------------------------------------------------------------------
-- 2. Le coach valide le compte rendu après le Live.
-- ---------------------------------------------------------------------------
select set_config(
  'request.jwt.claims',
  '{"sub":"c7100000-0000-0000-0000-000000000017","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.admin_submit_match_sport_report(
    current_setting('test.coach_match')::uuid,1,0,
    current_setting('test.coach_lineup')::jsonb,
    current_setting('test.coach_goals')::jsonb,
    'validation par le coach'
  )$$,
  'le coach valide le compte rendu du match qu’il a piloté'
);

-- Hors validation, les fonctions d'administration restent fermées au coach.
select throws_ok(
  $$select public.staff_set_match_mvp(current_setting('test.coach_match')::uuid,'{}'::uuid[])$$,
  '42501',
  null,
  'le coach ne peut pas appeler directement le réglage HDM'
);
select throws_ok(
  $$select public.staff_set_match_attendance(current_setting('test.coach_match')::uuid,'{}'::uuid[])$$,
  '42501',
  null,
  'le coach ne peut pas appeler directement le réglage des présences'
);
select throws_ok(
  $$select public.finalize_match_postgame(current_setting('test.coach_match')::uuid,0,'[]'::jsonb,null,0)$$,
  '42501',
  null,
  'le coach ne peut pas appeler directement la saisie du score'
);
reset role;

select is(
  (select status from public.matches where id=current_setting('test.coach_match')::uuid),
  'termine',
  'le match validé par le coach est terminé'
);
select is(
  (select score_as_grinta from public.matches where id=current_setting('test.coach_match')::uuid),
  1,
  'le score validé par le coach est enregistré'
);
select is(
  (select count(*) from public.match_attendance where match_id=current_setting('test.coach_match')::uuid),
  14::bigint,
  'les présences validées par le coach sont enregistrées'
);
select ok(
  (select exported from public.match_live_sessions where match_id=current_setting('test.coach_match')::uuid),
  'le Live est marqué comme exporté après la validation du coach'
);

select * from finish();
rollback;
