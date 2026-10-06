begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Statistiques → Prono : la colonne « Prono » compte les pronostics remplis
-- sur les matchs terminés, la base de « Bons », « Exacts » et « Points ».

insert into auth.users(id,email,raw_user_meta_data) values
('fe100000-0000-0000-0000-000000000001','prono-count-a@example.invalid','{"first_name":"PronoA"}'::jsonb),
('fe100000-0000-0000-0000-000000000002','prono-count-b@example.invalid','{"first_name":"PronoB"}'::jsonb);
update public.profiles
set status='active', role='pronostiqueur', is_test_account=false
where id in ('fe100000-0000-0000-0000-000000000001','fe100000-0000-0000-0000-000000000002');

insert into public.seasons(id,name,status)
values('fe200000-0000-0000-0000-000000000001','2213-2214','open');
insert into public.opponents(id,name)
values('fe300000-0000-0000-0000-000000000001','Count FC');

-- Deux matchs terminés (2-1 et 0-0) et un match à venir, écrits directement :
-- seul le comptage est testé ici, pas le parcours de saisie.
set local session_replication_role = replica;
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at, location,
  planned_duration_minutes, status, score_as_grinta, score_adverse,
  created_by, match_type, competition, result_validated_at
) values
  ('fe400000-0000-0000-0000-000000000001','fe200000-0000-0000-0000-000000000001',
   'fe300000-0000-0000-0000-000000000001', date '2014-04-01', time '21:00',
   timestamptz '2014-04-01 19:00:00+00', 'domicile', 90, 'archive', 2, 1,
   'fe100000-0000-0000-0000-000000000001', 'amical', 'championnat', now()),
  ('fe400000-0000-0000-0000-000000000002','fe200000-0000-0000-0000-000000000001',
   'fe300000-0000-0000-0000-000000000001', date '2014-04-08', time '21:00',
   timestamptz '2014-04-08 19:00:00+00', 'domicile', 90, 'termine', 0, 0,
   'fe100000-0000-0000-0000-000000000001', 'amical', 'championnat', now()),
  ('fe400000-0000-0000-0000-000000000003','fe200000-0000-0000-0000-000000000001',
   'fe300000-0000-0000-0000-000000000001', current_date + 3, time '21:00',
   now() + interval '3 days', 'domicile', 90, 'a_venir', null, null,
   'fe100000-0000-0000-0000-000000000001', 'amical', 'championnat', null);

-- A pronostique les trois matchs ; B ne remplit que le premier, sa ligne du
-- second reste vide.
delete from public.match_predictions
where profile_id in ('fe100000-0000-0000-0000-000000000001','fe100000-0000-0000-0000-000000000002');
insert into public.match_predictions(
  match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse, is_filled
) values
  ('fe400000-0000-0000-0000-000000000001','fe100000-0000-0000-0000-000000000001',2,1,true),
  ('fe400000-0000-0000-0000-000000000002','fe100000-0000-0000-0000-000000000001',1,0,true),
  ('fe400000-0000-0000-0000-000000000003','fe100000-0000-0000-0000-000000000001',3,0,true),
  ('fe400000-0000-0000-0000-000000000001','fe100000-0000-0000-0000-000000000002',0,1,true),
  ('fe400000-0000-0000-0000-000000000002','fe100000-0000-0000-0000-000000000002',0,0,false);
set local session_replication_role = origin;

-- Le classement se lit comme dans l'application : en membre connecté, à
-- travers la RLS des pronostics.
select set_config(
  'request.jwt.claims',
  '{"sub":"fe100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select match_pronos from public.v_classement_general
   where profile_id='fe100000-0000-0000-0000-000000000001'),
  2::bigint,
  'les pronostics des matchs terminés sont comptés, pas celui du match à venir'
);
select ok(
  (select match_bons <= match_pronos from public.v_classement_general
   where profile_id='fe100000-0000-0000-0000-000000000001'),
  '« Bons » ne dépasse jamais « Prono »'
);
select is(
  (select match_pronos from public.v_classement_general
   where profile_id='fe100000-0000-0000-0000-000000000002'),
  1::bigint,
  'une ligne de pronostic restée vide ne compte pas'
);
select is(
  (select count(*) from public.match_predictions
   where match_id='fe400000-0000-0000-0000-000000000003'
     and profile_id='fe100000-0000-0000-0000-000000000001'),
  0::bigint,
  'le pronostic du match à venir reste secret pour les autres membres'
);

reset role;

-- A voit son propre pronostic du match à venir : il ne compte pas pour autant.
select set_config(
  'request.jwt.claims',
  '{"sub":"fe100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select match_pronos from public.v_classement_general
   where profile_id='fe100000-0000-0000-0000-000000000001'),
  2::bigint,
  'son propre pronostic d’un match à venir ne compte qu’une fois le match terminé'
);

reset role;

select * from finish();
rollback;
