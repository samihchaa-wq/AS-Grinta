-- Le classement du pari saison ne doit pas bouger au seul changement de statut.
--
-- Avant correction, les points comparaient le pronostic a une projection sur 30
-- matchs tant que la saison n'etait pas archivee, puis au total reel une fois
-- archivee. Sur une saison qui ne fait pas exactement 30 matchs, le vainqueur
-- pouvait donc changer a l'archivage sans qu'aucun match soit joue.
begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data) values
  ('d2100000-0000-0000-0000-000000000001', 'target-stable-admin@example.invalid', '{"first_name":"TargetAdmin"}'::jsonb),
  ('d2100000-0000-0000-0000-000000000002', 'target-stable-exact@example.invalid', '{"first_name":"TargetExact"}'::jsonb),
  ('d2100000-0000-0000-0000-000000000003', 'target-stable-far@example.invalid', '{"first_name":"TargetFar"}'::jsonb);

update public.profiles
set status = 'active',
    role = case
      when id = 'd2100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end
where id in (
  'd2100000-0000-0000-0000-000000000001',
  'd2100000-0000-0000-0000-000000000002',
  'd2100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('d2200000-0000-0000-0000-000000000001', '2079-2080', 'open');

insert into public.opponents(id, name)
values ('d2400000-0000-0000-0000-000000000001', 'Target Stable FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, is_coach, position
) values (
  'd2300000-0000-0000-0000-000000000001',
  'd2200000-0000-0000-0000-000000000001',
  'Buteur', 'Unique', false, true, false, 1
);

-- Le pronostiqueur exact vise le total reel, l'autre vise une valeur qui ne
-- serait gagnante que sur une projection a 30 matchs.
select set_config('request.jwt.claims', '{"sub":"d2100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.save_my_season_predictions(
  'd2200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'd2300000-0000-0000-0000-000000000001',
    'category', 'buts',
    'predicted_value_30', 3
  ))
);
reset role;

select set_config('request.jwt.claims', '{"sub":"d2100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.save_my_season_predictions(
  'd2200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'd2300000-0000-0000-0000-000000000001',
    'category', 'buts',
    'predicted_value_30', 80
  ))
);
reset role;

select set_config('request.jwt.claims', '{"sub":"d2100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.set_season_predictions_lock('d2200000-0000-0000-0000-000000000001', true);
select set_config(
  'test.stable_match',
  public.admin_create_match_complete(
    'd2200000-0000-0000-0000-000000000001',
    'd2400000-0000-0000-0000-000000000001',
    ((now() + interval '2 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile', 2, 3, 4, null, null, false, 'championnat', null
  )::text,
  true
);
reset role;

-- Un seul match joue : la projection sur 30 matchs multipliait la cible par 30.
set local session_replication_role = replica;
update public.matches
set kickoff_at = '2011-03-17 20:00:00+00',
    match_date = '2011-03-17',
    match_time = '21:00:00'
where id = current_setting('test.stable_match')::uuid;
set local session_replication_role = origin;

select set_config('request.jwt.claims', '{"sub":"d2100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
select public.finalize_match_postgame(
  current_setting('test.stable_match')::uuid,
  0,
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'd2300000-0000-0000-0000-000000000001',
    'goals', 3
  )),
  null,
  3
);
set local role authenticated;
select public.archive_match(current_setting('test.stable_match')::uuid);
reset role;

select is(
  (select matches_played from public.v_season_match_count
   where season_id = 'd2200000-0000-0000-0000-000000000001'),
  1,
  'la saison se termine sur un seul match, loin des 30 de la projection'
);

-- Points lus avant l'archivage.
select set_config(
  'test.points_before_exact',
  coalesce((select sum(points)::text from public.v_season_prediction_points
    where season_id = 'd2200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'd2100000-0000-0000-0000-000000000002'), '0'),
  true
);
select set_config(
  'test.points_before_far',
  coalesce((select sum(points)::text from public.v_season_prediction_points
    where season_id = 'd2200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'd2100000-0000-0000-0000-000000000003'), '0'),
  true
);

select is(
  current_setting('test.points_before_exact'),
  '12',
  'avant archivage, le prono exact vaut deja le maximum double'
);
select is(
  current_setting('test.points_before_far'),
  '3',
  'avant archivage, le prono eloigne est deja dernier'
);

select set_config('request.jwt.claims', '{"sub":"d2100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.set_season_status('d2200000-0000-0000-0000-000000000001', 'archived');
reset role;

select is(
  coalesce((select sum(points)::text from public.v_season_prediction_points
    where season_id = 'd2200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'd2100000-0000-0000-0000-000000000002'), '0'),
  current_setting('test.points_before_exact'),
  'archiver ne change pas les points du prono exact'
);

select is(
  coalesce((select sum(points)::text from public.v_season_prediction_points
    where season_id = 'd2200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'd2100000-0000-0000-0000-000000000003'), '0'),
  current_setting('test.points_before_far'),
  'archiver ne change pas les points du prono eloigne'
);

select ok(
  exists (
    select 1 from public.season_awards
    where season_id = 'd2200000-0000-0000-0000-000000000001'
      and profile_id = 'd2100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_player'
  ),
  'le titre revient au pronostiqueur en tete avant comme apres archivage'
);

select * from finish();
rollback;
