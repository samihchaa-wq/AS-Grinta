begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- « Doublé HDM » et « Coup du chapeau » sont décernés par le recalcul des
-- badges, sans action de l'administrateur.
--
-- Joueur 1 : HDM aux matchs 1 et 2 (qui se suivent)          -> Doublé HDM
-- Joueur 2 : HDM aux matchs 1 et 3, absent au match 2         -> Doublé HDM
-- Joueur 3 : HDM aux matchs 1 et 3, joue le match 2 sans l'être -> rien
--
-- Joueur 1 : trois trophées la même saison                     -> Coup du chapeau
-- Joueur 2 : deux trophées + « saison complète »               -> rien
-- Joueur 3 : deux trophées une saison, un la suivante           -> rien

insert into auth.users(id,email,raw_user_meta_data)
select ('c1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('mystery-hdm-%s@example.invalid',n),
       jsonb_build_object('first_name','Mystere','last_name','Hdm')
from generate_series(1,3) n;

update public.profiles
set role='pronostiqueur',status='active',updated_at=now()
where id::text like 'c1000000-0000-0000-0000-%';

insert into public.badges(
  code,name,description,emoji,family,auto,sort_order,kind,category,color,auto_rule
)
values
  ('custom_test_double_hdm','Doublé HDM','Deux fois HDM de suite.',
   '🏅','joueur',false,999911,'custom','faits_de_jeu','#F97316','motm_back_to_back'),
  ('custom_test_hat_trick','Coup du chapeau','Trois trophées la même saison.',
   '🏅','joueur',false,999912,'custom','faits_de_jeu','#F97316','season_hat_trick');

-- Données de match posées directement, sans les déclencheurs, puis recalcul
-- explicite : on teste la règle, pas le parcours de saisie.
set local session_replication_role = replica;

insert into public.seasons(id,name,status)
values
  ('c2000000-0000-0000-0000-000000000001','2209-2210','open'),
  ('c2000000-0000-0000-0000-000000000002','2210-2211','archived');
insert into public.opponents(id,name)
values('c3000000-0000-0000-0000-000000000001','Hdm United');

insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('c4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'c2000000-0000-0000-0000-000000000001',
       format('Joueur%s',n),'Hdm',false,true,n,
       ('c1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid
from generate_series(1,3) n;

insert into public.matches(
  id,season_id,opponent_id,match_date,match_time,location,
  planned_duration_minutes,status,kickoff_at,score_as_grinta,score_adverse
)
select ('c5000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'c2000000-0000-0000-0000-000000000001',
       'c3000000-0000-0000-0000-000000000001',
       date '2209-10-01' + n*7, time '20:00','domicile',90,'termine',
       (date '2209-10-01' + n*7)::timestamp at time zone 'Europe/Paris',1,0
from generate_series(1,3) n;

-- Présences : tout le monde joue les trois matchs, sauf le joueur 2 au match 2.
insert into public.match_attendance(match_id,season_player_id)
select ('c5000000-0000-0000-0000-'||lpad(m::text,12,'0'))::uuid,
       ('c4000000-0000-0000-0000-'||lpad(p::text,12,'0'))::uuid
from generate_series(1,3) m, generate_series(1,3) p
where not (p=2 and m=2);

insert into public.match_man_of_match(match_id,season_player_id)
values
  ('c5000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001'),
  ('c5000000-0000-0000-0000-000000000002','c4000000-0000-0000-0000-000000000001'),
  ('c5000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000002'),
  ('c5000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000002'),
  ('c5000000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000003'),
  ('c5000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000003');

insert into public.season_awards(season_id,profile_id,award_type)
values
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','top_scorer'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','mvp_king'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','most_present'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','top_assists'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','best_winrate'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','season_complete'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000003','top_scorer'),
  ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000003','mvp_king'),
  ('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003','most_present');

set local session_replication_role = origin;

select public.recalculate_profile_badges(
  ('c1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid
)
from generate_series(1,3) n;

create or replace function pg_temp.has_badge(p_player integer, p_code text)
returns boolean language sql stable as $function$
  select exists (
    select 1
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.profile_id =
            ('c1000000-0000-0000-0000-'||lpad(p_player::text,12,'0'))::uuid
      and b.code = p_code
      and pb.source = 'auto'
  );
$function$;

-- ---------------------------------------------------------------------------
-- Doublé HDM
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.has_badge(1,'custom_test_double_hdm'),
  'HDM sur deux matchs qui se suivent décerne « Doublé HDM »'
);
select ok(
  pg_temp.has_badge(2,'custom_test_double_hdm'),
  'un match manqué entre deux HDM ne casse pas la série'
);
select ok(
  not pg_temp.has_badge(3,'custom_test_double_hdm'),
  'un match joué sans être HDM casse la série'
);

-- ---------------------------------------------------------------------------
-- Coup du chapeau
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.has_badge(1,'custom_test_hat_trick'),
  'trois trophées la même saison décernent « Coup du chapeau »'
);
select ok(
  not pg_temp.has_badge(2,'custom_test_hat_trick'),
  '« saison complète » ne compte pas comme trophée'
);
select ok(
  not pg_temp.has_badge(3,'custom_test_hat_trick'),
  'des trophées répartis sur deux saisons ne suffisent pas'
);

select ok(
  exists (
    select 1
    from private.profile_badge_audit_log log
    where log.profile_id = 'c1000000-0000-0000-0000-000000000001'
      and log.badge_code = 'custom_test_hat_trick'
      and log.metadata ->> 'rule' = 'season_hat_trick'
  ),
  'l’attribution automatique est tracée dans le journal'
);

-- ---------------------------------------------------------------------------
-- Cloisonnement
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege(
    'authenticated', 'private.profile_match_exploits(uuid)', 'execute'
  ),
  'un compte connecté ne peut toujours pas interroger les faits d’autrui'
);

select throws_ok(
  $$update public.badges set auto_rule='hat_trick' where code='custom_test_double_hdm'$$,
  '23514',
  null,
  'une règle inconnue reste refusée'
);

select * from finish();
rollback;
