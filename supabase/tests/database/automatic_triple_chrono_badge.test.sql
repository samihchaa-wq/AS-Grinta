begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- « Triplé Chrono » : trois buts ou plus dans la même mi-temps.

insert into auth.users(id,email,raw_user_meta_data)
select ('c5000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('triple-chrono-%s@example.invalid',n),
       jsonb_build_object('first_name','Chrono','last_name','Badge')
from generate_series(1,16) n;

update public.profiles
set role=case when id='c5000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'c5000000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('c6000000-0000-0000-0000-000000000001','2211-2212','open');
insert into public.opponents(id,name)
values('c7000000-0000-0000-0000-000000000001','Chrono Rovers');

-- Joueur n (position n) = profil n+1. Le joueur 1 est gardien.
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('c8000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'c6000000-0000-0000-0000-000000000001',
       format('Joueur%s',n),'Chrono',
       n=1,true,n,('c5000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,15) n;

-- Le badge tel que l'administration l'a créé, avec sa règle.
insert into public.badges(
  code,name,description,emoji,family,auto,sort_order,kind,category,color,auto_rule
)
values
  ('custom_test_triple_chrono','Triplé Chrono','Marquer un triplé en une mi-temps.',
   '🏅','joueur',false,999921,'custom','faits_de_jeu','#F97316','hat_trick_in_half');

select throws_ok(
  $$update public.badges set auto_rule='hat_trick_in_halves'
    where code='custom_test_triple_chrono'$$,
  '23514',
  null,
  'seules les règles connues sont acceptées'
);

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='c5000000-0000-0000-0000-000000000001'
where key='sports_management';

-- ---------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------

create or replace function pg_temp.player(p_position integer)
returns uuid language sql immutable as $function$
  select ('c5000000-0000-0000-0000-'||lpad((p_position+1)::text,12,'0'))::uuid;
$function$;

create or replace function pg_temp.participant_of(p_match uuid, p_position integer)
returns uuid language sql stable as $function$
  select participant.id
  from public.match_sport_participants participant
  join public.season_players player on player.id=participant.season_player_id
  where participant.match_id=p_match
    and player.position=p_position;
$function$;
grant execute on function pg_temp.participant_of(uuid,integer) to authenticated;

-- Onze titulaires et trois remplaçants présents ; le joueur 15 est absent.
create or replace function pg_temp.report_lineup(p_match uuid)
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
      'sort_order',player.position
    ) order by player.position)
  )
  from public.match_sport_participants participant
  join public.season_players player on player.id=participant.season_player_id
  where participant.match_id=p_match
    and participant.is_eligible;
$function$;
grant execute on function pg_temp.report_lineup(uuid) to authenticated;

-- Un but d'AS Grinta : minute, buteur, passeur (0 = aucune passe).
create or replace function pg_temp.goal_us(
  p_match uuid, p_minute integer, p_scorer integer, p_assist integer
)
returns jsonb language sql stable as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'minute',p_minute,'team_side','as_grinta',
    'scorer_participant_id',pg_temp.participant_of(p_match,p_scorer),
    'assist_participant_id',case when p_assist>0
      then pg_temp.participant_of(p_match,p_assist) end,
    'assist_kind',case when p_assist>0 then 'player' else 'none' end,
    'is_own_goal',false
  )) || case when p_minute is null
    then jsonb_build_object('minute',null) else '{}'::jsonb end;
$function$;
grant execute on function pg_temp.goal_us(uuid,integer,integer,integer) to authenticated;

create or replace function pg_temp.goal_them(p_minute integer)
returns jsonb language sql immutable as $function$
  select jsonb_build_object(
    'minute',p_minute,'team_side','opponent',
    'assist_kind','none','is_own_goal',false
  );
$function$;
grant execute on function pg_temp.goal_them(integer) to authenticated;

-- Crée un match, le passe dans le passé et prépare son effectif.
create or replace function pg_temp.finished_match(p_hours_ago integer)
returns uuid language plpgsql as $function$
declare
  v_match uuid;
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"c5000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
    true
  );
  set local role authenticated;
  v_match := public.create_match_with_odds_and_sport_limit(
    'c6000000-0000-0000-0000-000000000001',
    'c7000000-0000-0000-0000-000000000001',
    ((now()+interval '3 days'+make_interval(hours=>p_hours_ago)) at time zone 'Europe/Paris')::date,
    ((now()+interval '3 days'+make_interval(hours=>p_hours_ago)) at time zone 'Europe/Paris')::time,
    'domicile',2.1,3.2,2.9,16
  );
  reset role;

  update public.matches
  set match_date=((now()-make_interval(hours=>p_hours_ago)) at time zone 'Europe/Paris')::date,
      match_time=((now()-make_interval(hours=>p_hours_ago)) at time zone 'Europe/Paris')::time,
      kickoff_at=now()-make_interval(hours=>p_hours_ago)
  where id=v_match;
  update public.match_sport_workflows
  set availability_state='closed'
  where match_id=v_match;
  update public.match_sport_participants
  set availability_status='available',convocation_status='convoked',selection_status='substitute'
  where match_id=v_match;
  return v_match;
end;
$function$;

create or replace function pg_temp.validate(
  p_match uuid, p_us integer, p_them integer, p_goals jsonb
)
returns void language plpgsql as $function$
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"c5000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
    true
  );
  set local role authenticated;
  perform public.admin_submit_match_sport_report(
    p_match,p_us,p_them,pg_temp.report_lineup(p_match),p_goals,null
  );
  reset role;
end;
$function$;

create or replace function pg_temp.has_badge(p_position integer, p_code text)
returns boolean language sql stable as $function$
  select exists (
    select 1
    from public.profile_badges pb
    join public.badges b on b.id=pb.badge_id
    where pb.profile_id=pg_temp.player(p_position)
      and b.code=p_code
      and pb.source='auto'
  );
$function$;

create or replace function pg_temp.exploit(
  p_position integer, p_rule text, p_match uuid
)
returns boolean language sql stable as $function$
  select exists (
    select 1
    from private.profile_match_exploits(pg_temp.player(p_position)) exploit
    where exploit.rule=p_rule and exploit.match_id=p_match
  );
$function$;



-- Le compte rendu d'un match avec un journal Live : chaque but saisi pointe
-- vers l'événement Live qui l'a produit, avec la mi-temps notée par le Live.
create or replace function pg_temp.attach_live_half(
  p_match uuid, p_ordinal integer, p_live_minute integer, p_half integer
)
returns void language plpgsql as $function$
declare
  v_event uuid;
begin
  insert into public.match_live_events(
    match_id,event_type,minute,half,scorer_participant_id,
    score_as_grinta_after,created_by
  )
  select ga.match_id,'goal_us',p_live_minute,p_half,ga.scorer_participant_id,
    p_ordinal+1,'c5000000-0000-0000-0000-000000000001'
  from public.match_sport_goal_actions ga
  where ga.match_id=p_match and ga.ordinal=p_ordinal
  returning id into v_event;

  update public.match_sport_goal_actions
  set source_live_event_id=v_event
  where match_id=p_match and ordinal=p_ordinal;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 1. Match 1 (90 minutes) : 4-0
-- ---------------------------------------------------------------------------
--
-- Joueur2 marque à 10', 25' et 45' (arrêts de jeu de la première mi-temps
-- saisis à 45) : triplé en une mi-temps. Joueur3 n'a qu'un but.

select set_config('test.m1', pg_temp.finished_match(170)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m1')::uuid, 4, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m1')::uuid, 10, 2, 0),
        pg_temp.goal_us(current_setting('test.m1')::uuid, 25, 2, 0),
        pg_temp.goal_us(current_setting('test.m1')::uuid, 45, 2, 0),
        pg_temp.goal_us(current_setting('test.m1')::uuid, 70, 3, 2)
      )
    )$$,
  'le compte rendu du match 1 se valide'
);

select ok(
  pg_temp.has_badge(2,'custom_test_triple_chrono')
  and pg_temp.exploit(2,'hat_trick_in_half',current_setting('test.m1')::uuid),
  'trois buts en première mi-temps décernent « Triplé Chrono »'
);
select ok(
  not pg_temp.has_badge(3,'custom_test_triple_chrono'),
  'le passeur et les autres buteurs ne le reçoivent pas'
);

-- ---------------------------------------------------------------------------
-- 2. Match 2 (90 minutes) : 6-0
-- ---------------------------------------------------------------------------
--
-- Joueur4 : 46', 60', 89' — triplé en seconde mi-temps.
-- Joueur5 : 40', 45', 46' — un triplé, mais à cheval sur la pause.

select set_config('test.m2', pg_temp.finished_match(146)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m2')::uuid, 6, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m2')::uuid, 40, 5, 0),
        pg_temp.goal_us(current_setting('test.m2')::uuid, 45, 5, 0),
        pg_temp.goal_us(current_setting('test.m2')::uuid, 46, 4, 0),
        pg_temp.goal_us(current_setting('test.m2')::uuid, 46, 5, 0),
        pg_temp.goal_us(current_setting('test.m2')::uuid, 60, 4, 0),
        pg_temp.goal_us(current_setting('test.m2')::uuid, 89, 4, 0)
      )
    )$$,
  'le compte rendu du match 2 se valide'
);

select ok(
  pg_temp.has_badge(4,'custom_test_triple_chrono'),
  'trois buts en seconde mi-temps décernent « Triplé Chrono »'
);
select ok(
  not pg_temp.has_badge(5,'custom_test_triple_chrono'),
  'un triplé réparti sur les deux mi-temps ne suffit pas'
);

-- ---------------------------------------------------------------------------
-- 3. Match 3 (90 minutes) : 3-0, une minute inconnue
-- ---------------------------------------------------------------------------

select set_config('test.m3', pg_temp.finished_match(122)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m3')::uuid, 3, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m3')::uuid, 10, 6, 0),
        pg_temp.goal_us(current_setting('test.m3')::uuid, 20, 6, 0),
        pg_temp.goal_us(current_setting('test.m3')::uuid, null, 6, 0)
      )
    )$$,
  'le compte rendu du match 3 se valide'
);

select ok(
  not pg_temp.has_badge(6,'custom_test_triple_chrono'),
  'un but sans minute ne peut pas être placé dans une mi-temps'
);

-- ---------------------------------------------------------------------------
-- 4. Match 4 (60 minutes) : 3-0
-- ---------------------------------------------------------------------------
--
-- Joueur7 : 20', 31', 35'. Sur 60 minutes, la pause tombe à 30' : 31' est en
-- seconde mi-temps.

select set_config('test.m4', pg_temp.finished_match(98)::text, true);
set local session_replication_role = replica;
update public.matches set planned_duration_minutes=60
where id=current_setting('test.m4')::uuid;
set local session_replication_role = origin;

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m4')::uuid, 3, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m4')::uuid, 20, 7, 0),
        pg_temp.goal_us(current_setting('test.m4')::uuid, 31, 7, 0),
        pg_temp.goal_us(current_setting('test.m4')::uuid, 35, 7, 0)
      )
    )$$,
  'le compte rendu du match 4 se valide'
);

select ok(
  not pg_temp.exploit(7,'hat_trick_in_half',current_setting('test.m4')::uuid),
  'la pause suit la durée prévue du match'
);

-- ---------------------------------------------------------------------------
-- 5. Match 5 (90 minutes) : 3-0, buts venus du Live
-- ---------------------------------------------------------------------------
--
-- Joueur8 marque à 30', puis à 46' et 47' pendant les arrêts de jeu de la
-- première mi-temps : le Live les a notés en première mi-temps.
-- Joueur9 marque à 20', 30' et 40' selon le Live, mais l'administrateur a
-- corrigé la dernière minute en 75' dans le compte rendu : la correction
-- l'emporte.

select set_config('test.m5', pg_temp.finished_match(74)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m5')::uuid, 6, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m5')::uuid, 20, 9, 0),
        pg_temp.goal_us(current_setting('test.m5')::uuid, 30, 8, 0),
        pg_temp.goal_us(current_setting('test.m5')::uuid, 30, 9, 0),
        pg_temp.goal_us(current_setting('test.m5')::uuid, 46, 8, 0),
        pg_temp.goal_us(current_setting('test.m5')::uuid, 47, 8, 0),
        pg_temp.goal_us(current_setting('test.m5')::uuid, 75, 9, 0)
      )
    )$$,
  'le compte rendu du match 5 se valide'
);

select ok(
  not pg_temp.exploit(8,'hat_trick_in_half',current_setting('test.m5')::uuid),
  'sans Live, 46'' et 47'' comptent en seconde mi-temps'
);

select lives_ok(
  $$select pg_temp.attach_live_half(current_setting('test.m5')::uuid, ordinal, live_minute, half)
    from (values (0, 20, 1), (1, 30, 1), (2, 30, 1), (3, 46, 1), (4, 47, 1), (5, 40, 1))
      as live(ordinal, live_minute, half)$$,
  'les buts du match 5 sont rattachés à leur événement Live'
);
select lives_ok(
  $$select public.recalculate_all_badges()$$,
  'le recalcul complet s’exécute'
);

select ok(
  pg_temp.has_badge(8,'custom_test_triple_chrono')
  and pg_temp.exploit(8,'hat_trick_in_half',current_setting('test.m5')::uuid),
  'les arrêts de jeu notés par le Live restent en première mi-temps'
);
select ok(
  not pg_temp.has_badge(9,'custom_test_triple_chrono'),
  'une minute corrigée après le Live l’emporte sur la mi-temps du Live'
);

-- ---------------------------------------------------------------------------
-- 6. Journal et idempotence
-- ---------------------------------------------------------------------------

select is(
  (
    select count(*)
    from private.profile_badge_audit_log audit
    where audit.profile_id=pg_temp.player(2)
      and audit.badge_code='custom_test_triple_chrono'
      and audit.event_type='award'
      and audit.source='auto'
      and audit.metadata->>'reason'='match_exploit'
      and audit.metadata->>'rule'='hat_trick_in_half'
      and audit.metadata->>'match_id'=current_setting('test.m1')
  ),
  1::bigint,
  'l’attribution est journalisée une seule fois avec le match concerné'
);

select * from finish();
rollback;
