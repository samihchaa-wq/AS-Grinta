begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Badge « Traître » : « Pronostiquer contre l’AS Grinta… et avoir raison ».
-- Le pronostic doit annoncer la défaite de l'AS Grinta ET l'AS Grinta doit
-- avoir réellement perdu.

select ok(
  exists (
    select 1 from public.badges
    where code = 'bet_against_grinta__1'
      and metric = 'bet_against_grinta'
      and threshold = 1
      and auto
  ),
  'le badge Traître est un badge automatique au seuil 1'
);

insert into auth.users(id, email, raw_user_meta_data)
select ('fa100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('traitre-%s@example.invalid', n),
       jsonb_build_object(
         'first_name', (array['Perdant', 'Traitre', 'Nul', 'Fidele'])[n]
       )
from generate_series(1, 4) n;

update public.profiles
set status = 'active', role = 'pronostiqueur', is_test_account = false
where id::text like 'fa100000-0000-0000-0000-%';

insert into public.seasons(id, name, status)
values ('fa200000-0000-0000-0000-000000000001', '2217-2218', 'open');
insert into public.opponents(id, name)
values ('fa300000-0000-0000-0000-000000000001', 'Traitre FC');

-- Trois matchs terminés : défaite 1-3, nul 2-2, victoire 2-1. Écrits
-- directement : seul le calcul du badge est testé ici.
set local session_replication_role = replica;
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at, location,
  planned_duration_minutes, status, score_as_grinta, score_adverse,
  created_by, match_type, competition, result_validated_at
)
select
  ('fa400000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
  'fa200000-0000-0000-0000-000000000001',
  'fa300000-0000-0000-0000-000000000001',
  date '2014-05-01' + n, time '21:00',
  (date '2014-05-01' + n) + time '19:00', 'domicile', 90, 'termine',
  score.us, score.them,
  'fa100000-0000-0000-0000-000000000001', 'amical', 'championnat', now()
from (values (1, 1, 3), (2, 2, 2), (3, 2, 1)) as score(n, us, them);

delete from public.match_predictions
where profile_id::text like 'fa100000-0000-0000-0000-%';

-- Joueur 1 : contre l'AS Grinta (0-2), elle gagne 2-1 — il a tort.
-- Joueur 2 : contre l'AS Grinta (1-2), elle perd 1-3 — il a raison.
-- Joueur 3 : contre l'AS Grinta (1-3), match nul 2-2 — il a tort.
-- Joueur 4 : pour l'AS Grinta (3-1), elle perd 1-3 — pas un pari contre.
insert into public.match_predictions(
  match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse,
  is_filled
) values
  ('fa400000-0000-0000-0000-000000000003', 'fa100000-0000-0000-0000-000000000001', 0, 2, true),
  ('fa400000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000002', 1, 2, true),
  ('fa400000-0000-0000-0000-000000000002', 'fa100000-0000-0000-0000-000000000003', 1, 3, true),
  ('fa400000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000004', 3, 1, true);
set local session_replication_role = origin;

select public.recalculate_profile_badges(profile.id)
from public.profiles profile
where profile.id::text like 'fa100000-0000-0000-0000-%';

create or replace function pg_temp.has_traitre(p_profile uuid)
returns boolean language sql stable as $function$
  select exists (
    select 1
    from public.profile_badges owned
    join public.badges badge on badge.id = owned.badge_id
    where owned.profile_id = p_profile
      and badge.code = 'bet_against_grinta__1'
  );
$function$;

select ok(
  not pg_temp.has_traitre('fa100000-0000-0000-0000-000000000001'),
  'parier contre l’AS Grinta quand elle gagne ne rend pas Traître'
);
select is(
  (select bet_against_grinta
   from private.profile_badge_metrics('fa100000-0000-0000-0000-000000000001')),
  0,
  'un pari perdant contre l’AS Grinta ne compte pas'
);
select ok(
  pg_temp.has_traitre('fa100000-0000-0000-0000-000000000002'),
  'parier contre l’AS Grinta quand elle perd rend Traître'
);
select ok(
  not pg_temp.has_traitre('fa100000-0000-0000-0000-000000000003'),
  'un match nul n’est pas une défaite'
);
select ok(
  not pg_temp.has_traitre('fa100000-0000-0000-0000-000000000004'),
  'parier pour l’AS Grinta quand elle perd ne rend pas Traître'
);

select * from finish();
rollback;
