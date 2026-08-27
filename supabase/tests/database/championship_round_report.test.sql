begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
  '95000000-0000-0000-0000-000000000001',
  'championship-round-regression@example.invalid',
  '{"first_name":"Round","last_name":"Regression"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '95000000-0000-0000-0000-000000000001';

insert into public.seasons (id, name, status)
values ('95000000-0000-0000-0000-000000000010', '2098-2099', 'terminee');

insert into public.opponents (id, name)
values
  ('95000000-0000-0000-0000-000000000020', 'Round Test FC'),
  ('95000000-0000-0000-0000-000000000021', 'Friendly Test FC'),
  ('95000000-0000-0000-0000-000000000022', 'Round Test FC 2');

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  match_type,
  created_by
)
values (
  '95000000-0000-0000-0000-000000000100',
  '95000000-0000-0000-0000-000000000010',
  '95000000-0000-0000-0000-000000000020',
  date '2098-09-05',
  time '20:00',
  'domicile',
  90,
  'championnat',
  '95000000-0000-0000-0000-000000000001'
);

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000100'),
  1,
  'le premier match de championnat reçoit J1'
);

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  match_type,
  created_by
)
values (
  '95000000-0000-0000-0000-000000000101',
  '95000000-0000-0000-0000-000000000010',
  '95000000-0000-0000-0000-000000000021',
  date '2098-09-21',
  time '20:00',
  'exterieur',
  90,
  'amical',
  '95000000-0000-0000-0000-000000000001'
);

update public.matches
set match_date = date '2098-09-28'
where id = '95000000-0000-0000-0000-000000000100';

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000100'),
  1,
  'reporter J1 après un amical conserve J1 quand aucun autre championnat existe'
);

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000101'),
  null::integer,
  'un match amical ne reçoit jamais de numéro de journée'
);

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  match_type,
  created_by
)
values (
  '95000000-0000-0000-0000-000000000102',
  '95000000-0000-0000-0000-000000000010',
  '95000000-0000-0000-0000-000000000022',
  date '2098-10-05',
  time '20:00',
  'domicile',
  90,
  'championnat',
  '95000000-0000-0000-0000-000000000001'
);

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000102'),
  2,
  'le championnat suivant reçoit J2'
);

update public.matches
set match_date = date '2098-10-12'
where id = '95000000-0000-0000-0000-000000000100';

-- La journée appartient au calendrier de la ligue : elle survit à un report,
-- y compris derrière une autre rencontre de championnat. L'ancienne règle
-- « le report est ajouté après le dernier J existant » écrasait le numéro
-- réel de la ligue à chaque changement de date.
select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000100'),
  1,
  'un report derrière un autre championnat conserve la journée de la ligue'
);

update public.matches
set championship_round = 9
where id = '95000000-0000-0000-0000-000000000100';

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000100'),
  9,
  'la journée se corrige à la main quand la ligue en saute une'
);

update public.matches
set match_date = date '2098-11-02'
where id = '95000000-0000-0000-0000-000000000100';

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000100'),
  9,
  'une journée corrigée survit à un changement de date'
);

update public.matches
set match_type = 'amical'
where id = '95000000-0000-0000-0000-000000000100';

select is(
  (select championship_round from public.matches where id = '95000000-0000-0000-0000-000000000100'),
  null::integer,
  'une rencontre qui quitte le championnat perd sa journée'
);

select has_function(
  'public',
  'admin_set_match_championship_round',
  array['uuid', 'integer'],
  'la correction de journée est exposée aux administrateurs'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_set_match_championship_round(uuid,integer)',
    'EXECUTE'
  ),
  'la correction de journée reste inaccessible aux anonymes'
);

select * from finish();
rollback;
