begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Badges mystère automatiques : « Au four et au moulin », « Remontada » et
-- « Clutch » sont décernés par la validation réelle d'un compte rendu, sans
-- aucune action de l'administrateur.

insert into auth.users(id,email,raw_user_meta_data)
select ('b1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('mystery-badges-%s@example.invalid',n),
       jsonb_build_object('first_name','Mystere','last_name','Badge')
from generate_series(1,16) n;

update public.profiles
set role=case when id='b1000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'b1000000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('b2000000-0000-0000-0000-000000000001','2207-2208','open');
insert into public.opponents(id,name)
values('b3000000-0000-0000-0000-000000000001','Mystery United');

-- Joueur n (position n) = profil n+1. Le joueur 1 est gardien.
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('b4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'b2000000-0000-0000-0000-000000000001',
       format('Joueur%s',n),'Mystere',
       n=1,true,n,('b1000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,15) n;

-- Les trois badges tels que l'administration les a créés, avec leur règle.
insert into public.badges(
  code,name,description,emoji,family,auto,sort_order,kind,category,color,auto_rule
)
values
  ('custom_test_four_moulin','Au four et au moulin','But et passe décisive.',
   '🏅','joueur',false,999901,'custom','faits_de_jeu','#F97316','goal_and_assist'),
  ('custom_test_remontada','Remontada','Gagner après avoir été mené de 2 buts.',
   '🏅','joueur',false,999902,'custom','faits_de_jeu','#F97316','remontada'),
  ('custom_test_clutch','Clutch','But de la victoire dans les dernières minutes.',
   '🏅','joueur',false,999903,'custom','faits_de_jeu','#F97316','clutch'),
  ('custom_test_manual','Manuel','Badge sans règle.',
   '🏅','joueur',false,999904,'custom','faits_de_jeu','#F97316',null);

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='b1000000-0000-0000-0000-000000000001'
where key='sports_management';

-- ---------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------

create or replace function pg_temp.player(p_position integer)
returns uuid language sql immutable as $function$
  select ('b1000000-0000-0000-0000-'||lpad((p_position+1)::text,12,'0'))::uuid;
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
    '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
    true
  );
  set local role authenticated;
  v_match := public.create_match_with_odds_and_sport_limit(
    'b2000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
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
    '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
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

-- ---------------------------------------------------------------------------
-- 1. Match A : mené 0-2, gagné 3-2 grâce à un but à la 86e
-- ---------------------------------------------------------------------------
--
-- 10' et 20' adverses, puis Joueur2 (servi par Joueur3), Joueur3 (servi par
-- Joueur2) et Joueur5 à la 86e : le troisième but est celui de la victoire.

select set_config('test.match_a', pg_temp.finished_match(2)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.match_a')::uuid, 3, 2,
      jsonb_build_array(
        pg_temp.goal_them(10),
        pg_temp.goal_them(20),
        pg_temp.goal_us(current_setting('test.match_a')::uuid, 30, 2, 3),
        pg_temp.goal_us(current_setting('test.match_a')::uuid, 50, 3, 2),
        pg_temp.goal_us(current_setting('test.match_a')::uuid, 86, 5, 0)
      )
    )$$,
  'le compte rendu du match A se valide'
);

select ok(
  pg_temp.has_badge(2,'custom_test_four_moulin')
  and pg_temp.has_badge(3,'custom_test_four_moulin'),
  'marquer et faire une passe dans le même match décerne « Au four et au moulin »'
);
select ok(
  not pg_temp.has_badge(5,'custom_test_four_moulin'),
  'un but sans passe décisive ne suffit pas pour « Au four et au moulin »'
);

select is(
  (
    select count(*)
    from generate_series(1,14) position
    where pg_temp.has_badge(position,'custom_test_remontada')
  ),
  14::bigint,
  'les quatorze joueurs présents reçoivent « Remontada »'
);
select ok(
  not pg_temp.has_badge(15,'custom_test_remontada'),
  'un joueur absent du match ne reçoit pas « Remontada »'
);

select ok(
  pg_temp.has_badge(5,'custom_test_clutch'),
  'le but de la victoire à la 86e décerne « Clutch »'
);
select is(
  (
    select count(*)
    from generate_series(1,15) position
    where pg_temp.has_badge(position,'custom_test_clutch')
  ),
  1::bigint,
  'seul le buteur de la victoire reçoit « Clutch »'
);

select ok(
  not exists (
    select 1 from public.profile_badges pb
    join public.badges b on b.id=pb.badge_id
    where b.code='custom_test_manual'
  ),
  'un badge sans règle n’est jamais décerné automatiquement'
);

select is(
  (
    select count(*)
    from private.profile_badge_audit_log audit
    where audit.profile_id=pg_temp.player(5)
      and audit.badge_code='custom_test_clutch'
      and audit.event_type='award'
      and audit.source='auto'
      and audit.metadata->>'reason'='match_exploit'
      and audit.metadata->>'rule'='clutch'
      and audit.metadata->>'match_id'=current_setting('test.match_a')
  ),
  1::bigint,
  'l’attribution automatique est journalisée avec sa règle et son match'
);

select lives_ok(
  $$select public.recalculate_all_badges()$$,
  'un nouveau recalcul complet s’exécute'
);
select is(
  (
    select count(*)
    from private.profile_badge_audit_log audit
    where audit.badge_code in (
      'custom_test_four_moulin','custom_test_remontada','custom_test_clutch'
    )
  ),
  17::bigint,
  'un recalcul ne décerne rien deux fois'
);

-- ---------------------------------------------------------------------------
-- 2. Match B : même scénario, mais un but sans minute
-- ---------------------------------------------------------------------------

select set_config('test.match_b', pg_temp.finished_match(26)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.match_b')::uuid, 3, 2,
      jsonb_build_array(
        pg_temp.goal_them(10),
        pg_temp.goal_them(20),
        pg_temp.goal_us(current_setting('test.match_b')::uuid, null, 6, 7),
        pg_temp.goal_us(current_setting('test.match_b')::uuid, 50, 7, 0),
        pg_temp.goal_us(current_setting('test.match_b')::uuid, 88, 8, 0)
      )
    )$$,
  'le compte rendu du match B se valide'
);

select ok(
  not pg_temp.exploit(1,'remontada',current_setting('test.match_b')::uuid),
  'sans la minute de chaque but, la chronologie n’est pas sûre : pas de Remontada'
);
select ok(
  not pg_temp.exploit(8,'clutch',current_setting('test.match_b')::uuid),
  'sans la minute de chaque but d’AS Grinta, pas de Clutch'
);
-- Joueur7 sert Joueur6 (minute inconnue) puis marque à la 50e.
select ok(
  pg_temp.exploit(7,'goal_and_assist',current_setting('test.match_b')::uuid)
  and pg_temp.has_badge(7,'custom_test_four_moulin'),
  '« Au four et au moulin » ne dépend pas des minutes'
);

-- ---------------------------------------------------------------------------
-- 3. Match C : 3-1, le but de la victoire tombe à la 84e
-- ---------------------------------------------------------------------------
--
-- Le 2e but d'AS Grinta (84e, Joueur9) donne la victoire : trop tôt. Le 3e
-- (88e, Joueur10) est tardif mais ne décide rien. Jamais mené de deux buts.

select set_config('test.match_c', pg_temp.finished_match(50)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.match_c')::uuid, 3, 1,
      jsonb_build_array(
        pg_temp.goal_them(5),
        pg_temp.goal_us(current_setting('test.match_c')::uuid, 10, 11, 0),
        pg_temp.goal_us(current_setting('test.match_c')::uuid, 84, 9, 0),
        pg_temp.goal_us(current_setting('test.match_c')::uuid, 88, 10, 0)
      )
    )$$,
  'le compte rendu du match C se valide'
);

select ok(
  not pg_temp.exploit(9,'clutch',current_setting('test.match_c')::uuid),
  'un but de la victoire avant les cinq dernières minutes n’est pas un Clutch'
);
select ok(
  not pg_temp.exploit(10,'clutch',current_setting('test.match_c')::uuid),
  'un but tardif qui ne décide pas de la victoire n’est pas un Clutch'
);
select ok(
  not pg_temp.exploit(1,'remontada',current_setting('test.match_c')::uuid),
  'mené d’un seul but, ce n’est pas une Remontada'
);

-- ---------------------------------------------------------------------------
-- 4. Match D : mené 0-2, défaite 2-3
-- ---------------------------------------------------------------------------

select set_config('test.match_d', pg_temp.finished_match(74)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.match_d')::uuid, 2, 3,
      jsonb_build_array(
        pg_temp.goal_them(10),
        pg_temp.goal_them(20),
        pg_temp.goal_us(current_setting('test.match_d')::uuid, 30, 12, 0),
        pg_temp.goal_us(current_setting('test.match_d')::uuid, 40, 13, 0),
        pg_temp.goal_them(89)
      )
    )$$,
  'le compte rendu du match D se valide'
);

select ok(
  not pg_temp.exploit(1,'remontada',current_setting('test.match_d')::uuid),
  'un retour sans victoire n’est pas une Remontada'
);

-- ---------------------------------------------------------------------------
-- 5. Correction : la minute ajoutée après coup suffit à décerner le badge
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.match_b')::uuid, 3, 2,
      jsonb_build_array(
        pg_temp.goal_them(10),
        pg_temp.goal_them(20),
        pg_temp.goal_us(current_setting('test.match_b')::uuid, 40, 6, 7),
        pg_temp.goal_us(current_setting('test.match_b')::uuid, 50, 7, 0),
        pg_temp.goal_us(current_setting('test.match_b')::uuid, 88, 8, 0)
      )
    )$$,
  'la correction du match B se valide'
);

select ok(
  pg_temp.has_badge(8,'custom_test_clutch'),
  'une fois la minute corrigée, le but de la 88e décerne « Clutch »'
);
select ok(
  pg_temp.exploit(1,'remontada',current_setting('test.match_b')::uuid),
  'une fois la minute corrigée, la Remontada est reconnue'
);

-- ---------------------------------------------------------------------------
-- 6. Cloisonnement
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege(
    'authenticated', 'private.profile_match_exploits(uuid)', 'execute'
  ),
  'un compte connecté ne peut pas interroger les faits de match d’autrui'
);
select ok(
  not has_function_privilege(
    'anon', 'private.profile_match_exploits(uuid)', 'execute'
  ),
  'un visiteur anonyme non plus'
);

select throws_ok(
  $$update public.badges set auto_rule='hat_trick' where code='custom_test_manual'$$,
  '23514',
  null,
  'une règle inconnue est refusée'
);

select * from finish();
rollback;
