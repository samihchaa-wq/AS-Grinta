begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Sept badges mystère automatiques de plus : « Une-deux », « La boucle est
-- bouclée », « Prêcher dans le désert », « Minimum syndical », « Rira bien
-- qui rira le dernier », « Jamais 2 sans 3 » et « Doublé HDM ».

insert into auth.users(id,email,raw_user_meta_data)
select ('c1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('mystery-badges-bis-%s@example.invalid',n),
       jsonb_build_object('first_name','Mystere','last_name','Badge')
from generate_series(1,16) n;

update public.profiles
set role=case when id='c1000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'c1000000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('c2000000-0000-0000-0000-000000000001','2209-2210','open');
insert into public.opponents(id,name)
values('c3000000-0000-0000-0000-000000000001','Mystery Rovers');

-- Joueur n (position n) = profil n+1. Le joueur 1 est gardien.
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('c4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'c2000000-0000-0000-0000-000000000001',
       format('Joueur%s',n),'Mystere',
       n=1,true,n,('c1000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,15) n;

-- Les sept badges tels que l'administration les a créés, avec leur règle.
insert into public.badges(
  code,name,description,emoji,family,auto,sort_order,kind,category,color,auto_rule
)
values
  ('custom_test_une_deux','Une-deux','Passe rendue.',
   '🏅','joueur',false,999911,'custom','faits_de_jeu','#F97316','one_two'),
  ('custom_test_boucle','La boucle est bouclée','Premier et dernier but.',
   '🏅','joueur',false,999912,'custom','faits_de_jeu','#F97316','first_and_last_goal'),
  ('custom_test_desert','Prêcher dans le désert','Triplé et défaite.',
   '🏅','joueur',false,999913,'custom','faits_de_jeu','#F97316','hat_trick_in_defeat'),
  ('custom_test_syndical','Minimum syndical','Unique but d’une victoire 1-0.',
   '🏅','joueur',false,999914,'custom','faits_de_jeu','#F97316','lone_winning_goal'),
  ('custom_test_rira_bien','Rira bien qui rira le dernier','Mené 0-1, gagné.',
   '🏅','joueur',false,999915,'custom','faits_de_jeu','#F97316','comeback_after_first_goal'),
  ('custom_test_jamais_2','Jamais 2 sans 3','Trois matchs de suite.',
   '🏅','joueur',false,999916,'custom','faits_de_jeu','#F97316','three_match_scoring_streak'),
  ('custom_test_double_hdm','Doublé HDM','Deux HDM de suite.',
   '🏅','joueur',false,999917,'custom','faits_de_jeu','#F97316','back_to_back_motm');

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='c1000000-0000-0000-0000-000000000001'
where key='sports_management';

-- ---------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------

create or replace function pg_temp.player(p_position integer)
returns uuid language sql immutable as $function$
  select ('c1000000-0000-0000-0000-'||lpad((p_position+1)::text,12,'0'))::uuid;
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
    '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
    true
  );
  set local role authenticated;
  v_match := public.create_match_with_odds_and_sport_limit(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
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
    '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
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
-- 1. Match 1 : mené 0-1, gagné 2-1
-- ---------------------------------------------------------------------------
--
-- 5' adverse, puis Joueur2 (servi par Joueur3) et Joueur3 (servi par
-- Joueur2) : une-deux.

select set_config('test.m1', pg_temp.finished_match(170)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m1')::uuid, 2, 1,
      jsonb_build_array(
        pg_temp.goal_them(5),
        pg_temp.goal_us(current_setting('test.m1')::uuid, 30, 2, 3),
        pg_temp.goal_us(current_setting('test.m1')::uuid, 60, 3, 2)
      )
    )$$,
  'le compte rendu du match 1 se valide'
);

select ok(
  pg_temp.has_badge(2,'custom_test_une_deux')
  and pg_temp.has_badge(3,'custom_test_une_deux'),
  'se servir mutuellement dans le même match décerne « Une-deux »'
);
select is(
  (
    select count(*)
    from generate_series(1,14) position
    where pg_temp.has_badge(position,'custom_test_rira_bien')
  ),
  14::bigint,
  'mené 0-1 puis vainqueur sans autre but encaissé : les quatorze présents reçoivent « Rira bien »'
);
select ok(
  not pg_temp.has_badge(15,'custom_test_rira_bien'),
  'un joueur absent ne reçoit pas « Rira bien »'
);
select ok(
  not pg_temp.exploit(2,'first_and_last_goal',current_setting('test.m1')::uuid)
  and not pg_temp.exploit(3,'first_and_last_goal',current_setting('test.m1')::uuid),
  'quand l’adversaire marque le premier but, personne ne boucle la boucle'
);

-- ---------------------------------------------------------------------------
-- 2. Match 2 : victoire 1-0, Joueur2 marque
-- ---------------------------------------------------------------------------

select set_config('test.m2', pg_temp.finished_match(146)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m2')::uuid, 1, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m2')::uuid, 40, 2, 4)
      )
    )$$,
  'le compte rendu du match 2 se valide'
);

select ok(
  pg_temp.has_badge(2,'custom_test_syndical'),
  'l’unique but d’une victoire 1-0 décerne « Minimum syndical »'
);
select ok(
  not pg_temp.has_badge(4,'custom_test_syndical'),
  'le passeur ne reçoit pas « Minimum syndical »'
);
select ok(
  not pg_temp.exploit(2,'first_and_last_goal',current_setting('test.m2')::uuid),
  'un seul but dans le match ne suffit pas pour « La boucle est bouclée »'
);
select ok(
  not pg_temp.exploit(2,'one_two',current_setting('test.m2')::uuid)
  and not pg_temp.exploit(4,'one_two',current_setting('test.m2')::uuid),
  'une passe non rendue n’est pas un « Une-deux »'
);

-- ---------------------------------------------------------------------------
-- 3. Match 3 : défaite 3-4, triplé de Joueur2
-- ---------------------------------------------------------------------------

select set_config('test.m3', pg_temp.finished_match(122)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m3')::uuid, 3, 4,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m3')::uuid, 10, 2, 0),
        pg_temp.goal_us(current_setting('test.m3')::uuid, 20, 2, 0),
        pg_temp.goal_us(current_setting('test.m3')::uuid, 30, 2, 0),
        pg_temp.goal_them(50),
        pg_temp.goal_them(60),
        pg_temp.goal_them(70),
        pg_temp.goal_them(80)
      )
    )$$,
  'le compte rendu du match 3 se valide'
);

select ok(
  pg_temp.has_badge(2,'custom_test_desert'),
  'un triplé dans une défaite décerne « Prêcher dans le désert »'
);
select ok(
  pg_temp.has_badge(2,'custom_test_jamais_2')
  and pg_temp.exploit(2,'three_match_scoring_streak',current_setting('test.m3')::uuid),
  'marquer lors de trois matchs de suite décerne « Jamais 2 sans 3 » au troisième'
);
select ok(
  not pg_temp.has_badge(3,'custom_test_jamais_2'),
  'un match sans but casse la série'
);
select ok(
  not pg_temp.exploit(2,'first_and_last_goal',current_setting('test.m3')::uuid),
  'le dernier but du match est adverse : pas de boucle bouclée'
);

-- ---------------------------------------------------------------------------
-- 4. Match 4 : 2-0, Joueur6 marque les deux buts
-- ---------------------------------------------------------------------------

select set_config('test.m4', pg_temp.finished_match(98)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m4')::uuid, 2, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m4')::uuid, 10, 6, 0),
        pg_temp.goal_us(current_setting('test.m4')::uuid, 80, 6, 0)
      )
    )$$,
  'le compte rendu du match 4 se valide'
);

select ok(
  pg_temp.has_badge(6,'custom_test_boucle'),
  'marquer le premier et le dernier but décerne « La boucle est bouclée »'
);
select ok(
  not pg_temp.exploit(1,'comeback_after_first_goal',current_setting('test.m4')::uuid),
  'sans but encaissé, ce n’est pas « Rira bien »'
);

-- ---------------------------------------------------------------------------
-- 5. Match 5 : 2-0, mais une minute manquante
-- ---------------------------------------------------------------------------

select set_config('test.m5', pg_temp.finished_match(74)::text, true);

select lives_ok(
  $$select pg_temp.validate(
      current_setting('test.m5')::uuid, 2, 0,
      jsonb_build_array(
        pg_temp.goal_us(current_setting('test.m5')::uuid, null, 8, 0),
        pg_temp.goal_us(current_setting('test.m5')::uuid, 70, 8, 0)
      )
    )$$,
  'le compte rendu du match 5 se valide'
);

select ok(
  not pg_temp.exploit(8,'first_and_last_goal',current_setting('test.m5')::uuid),
  'sans la minute de chaque but, l’ordre n’est pas sûr : pas de boucle bouclée'
);

-- ---------------------------------------------------------------------------
-- 6. Doublé HDM
-- ---------------------------------------------------------------------------
--
-- Joueur9 est HDM des matchs 3 et 4 (consécutifs), Joueur10 des matchs 1
-- et 3 (pas consécutifs).

insert into public.match_man_of_match(match_id, season_player_id)
values
  (current_setting('test.m3')::uuid, 'c4000000-0000-0000-0000-000000000009'),
  (current_setting('test.m4')::uuid, 'c4000000-0000-0000-0000-000000000009'),
  (current_setting('test.m1')::uuid, 'c4000000-0000-0000-0000-000000000010'),
  (current_setting('test.m3')::uuid, 'c4000000-0000-0000-0000-000000000010');

select lives_ok(
  $$select public.recalculate_all_badges()$$,
  'le recalcul complet s’exécute'
);

select ok(
  pg_temp.has_badge(9,'custom_test_double_hdm')
  and pg_temp.exploit(9,'back_to_back_motm',current_setting('test.m4')::uuid),
  'HDM de deux matchs de suite décerne « Doublé HDM »'
);
select ok(
  not pg_temp.has_badge(10,'custom_test_double_hdm'),
  'deux HDM séparés par un autre match ne font pas un doublé'
);

-- ---------------------------------------------------------------------------
-- 7. Journal et idempotence
-- ---------------------------------------------------------------------------

select is(
  (
    select count(*)
    from private.profile_badge_audit_log audit
    where audit.profile_id=pg_temp.player(6)
      and audit.badge_code='custom_test_boucle'
      and audit.event_type='award'
      and audit.source='auto'
      and audit.metadata->>'reason'='match_exploit'
      and audit.metadata->>'rule'='first_and_last_goal'
      and audit.metadata->>'match_id'=current_setting('test.m4')
  ),
  1::bigint,
  'l’attribution est journalisée avec sa règle et son match'
);

select set_config(
  'test.audit_before',
  (
    select count(*)::text from private.profile_badge_audit_log
    where badge_code like 'custom\_test\_%'
  ),
  true
);
select lives_ok(
  $$select public.recalculate_all_badges()$$,
  'un nouveau recalcul complet s’exécute'
);
select is(
  (
    select count(*)::text from private.profile_badge_audit_log
    where badge_code like 'custom\_test\_%'
  ),
  current_setting('test.audit_before'),
  'un recalcul ne décerne rien deux fois'
);

select throws_ok(
  $$update public.badges set auto_rule='hat_trick' where code='custom_test_une_deux'$$,
  '23514',
  null,
  'une règle inconnue est refusée'
);

select * from finish();
rollback;
