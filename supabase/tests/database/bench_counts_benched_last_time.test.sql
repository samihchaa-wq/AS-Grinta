begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- « Simuler la compo » titularise en priorité les joueurs qui ont commencé
-- remplaçants la dernière fois qu'ils ont joué. Le compteur banc le signale
-- donc pour chaque participant, d'après son dernier match de la saison où il
-- figure sur la feuille : un match entre nous n'en a pas.

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'b5000000-0000-0000-0000-000000000001',
    'banc-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'banc-joueur@example.invalid',
    '{"first_name":"Joueur"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'b5000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000002'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'b5000000-0000-0000-0000-000000000001'
where key = 'sports_management';

insert into public.seasons(id, name, status, created_at)
values ('b5100000-0000-0000-0000-000000000002', '2291-2292', 'open',
        '2291-07-01T00:00:00Z');

insert into public.opponents(id, name)
values ('b5200000-0000-0000-0000-000000000001', 'Banc FC');

-- Alix, Bao, Cléo et Dani, plus un invité.
insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position
)
values
  ('b5300000-0000-0000-0000-000000000001',
   'b5100000-0000-0000-0000-000000000002', 'Alix', 'Banc', false, true, 1),
  ('b5300000-0000-0000-0000-000000000002',
   'b5100000-0000-0000-0000-000000000002', 'Bao', 'Banc', false, true, 2),
  ('b5300000-0000-0000-0000-000000000003',
   'b5100000-0000-0000-0000-000000000002', 'Cléo', 'Banc', false, true, 3),
  ('b5300000-0000-0000-0000-000000000004',
   'b5100000-0000-0000-0000-000000000002', 'Dani', 'Banc', false, true, 4);

insert into public.players(id, display_name)
values ('b5400000-0000-0000-0000-000000000001', 'Invité Banc');

insert into public.guest_players(
  id, first_name, created_by, updated_by, player_id
)
values (
  'b5400000-0000-0000-0000-000000000002',
  'Invité',
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000001',
  'b5400000-0000-0000-0000-000000000001'
);

-- Dans l'ordre : deux matchs joués, un match entre nous plus récent sans
-- feuille, puis le match à composer.
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, match_type, score_as_grinta,
  score_adverse, created_by, result_validated_at
)
values
  ('b5500000-0000-0000-0000-000000000001',
   'b5100000-0000-0000-0000-000000000002',
   'b5200000-0000-0000-0000-000000000001',
   current_date - 20, time '20:00', 'domicile', 90, 'termine', 'amical',
   2, 1, 'b5000000-0000-0000-0000-000000000001', now()),
  ('b5500000-0000-0000-0000-000000000002',
   'b5100000-0000-0000-0000-000000000002',
   'b5200000-0000-0000-0000-000000000001',
   current_date - 10, time '20:00', 'exterieur', 90, 'termine', 'amical',
   0, 0, 'b5000000-0000-0000-0000-000000000001', now()),
  ('b5500000-0000-0000-0000-000000000003',
   'b5100000-0000-0000-0000-000000000002',
   null,
   current_date - 3, time '20:00', 'domicile', 90, 'termine', 'entre_nous',
   4, 4, 'b5000000-0000-0000-0000-000000000001', now()),
  ('b5500000-0000-0000-0000-000000000004',
   'b5100000-0000-0000-0000-000000000002',
   'b5200000-0000-0000-0000-000000000001',
   current_date + 5, time '20:00', 'domicile', 90, 'a_venir', 'amical',
   null, null, 'b5000000-0000-0000-0000-000000000001', null);

insert into public.match_sport_participants(
  match_id, season_player_id, guest_player_id, availability_status,
  final_selection_status
)
values
  -- Premier match : Bao, Cléo et Dani remplaçants.
  ('b5500000-0000-0000-0000-000000000001',
   'b5300000-0000-0000-0000-000000000001', null, 'available', 'starter'),
  ('b5500000-0000-0000-0000-000000000001',
   'b5300000-0000-0000-0000-000000000002', null, 'available', 'substitute'),
  ('b5500000-0000-0000-0000-000000000001',
   'b5300000-0000-0000-0000-000000000003', null, 'available', 'substitute'),
  ('b5500000-0000-0000-0000-000000000001',
   'b5300000-0000-0000-0000-000000000004', null, 'available', 'substitute'),
  -- Dernier match joué : Alix et l'invité remplaçants, Bao et Cléo
  -- titulaires, Dani absent : son dernier match reste le premier.
  ('b5500000-0000-0000-0000-000000000002',
   'b5300000-0000-0000-0000-000000000001', null, 'available', 'substitute'),
  ('b5500000-0000-0000-0000-000000000002',
   'b5300000-0000-0000-0000-000000000002', null, 'available', 'starter'),
  ('b5500000-0000-0000-0000-000000000002',
   'b5300000-0000-0000-0000-000000000003', null, 'available', 'starter'),
  ('b5500000-0000-0000-0000-000000000002',
   null, 'b5400000-0000-0000-0000-000000000002', 'not_applicable',
   'substitute'),
  -- Match entre nous, plus récent : personne n'y est titulaire ou remplaçant.
  ('b5500000-0000-0000-0000-000000000003',
   'b5300000-0000-0000-0000-000000000001', null, 'available', 'undecided'),
  ('b5500000-0000-0000-0000-000000000003',
   'b5300000-0000-0000-0000-000000000002', null, 'available', 'undecided'),
  -- Match à composer.
  ('b5500000-0000-0000-0000-000000000004',
   'b5300000-0000-0000-0000-000000000001', null, 'available', 'undecided'),
  ('b5500000-0000-0000-0000-000000000004',
   'b5300000-0000-0000-0000-000000000002', null, 'available', 'undecided'),
  ('b5500000-0000-0000-0000-000000000004',
   'b5300000-0000-0000-0000-000000000003', null, 'available', 'undecided'),
  ('b5500000-0000-0000-0000-000000000004',
   'b5300000-0000-0000-0000-000000000004', null, 'available', 'undecided'),
  ('b5500000-0000-0000-0000-000000000004',
   null, 'b5400000-0000-0000-0000-000000000002', 'not_applicable',
   'undecided');

select set_config(
  'request.jwt.claims',
  '{"sub":"b5000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.bench_next_match',
  public.admin_get_finished_bench_counts(
    'b5500000-0000-0000-0000-000000000004'
  )::text,
  true
);
select set_config(
  'test.bench_first_match',
  public.admin_get_finished_bench_counts(
    'b5500000-0000-0000-0000-000000000001'
  )::text,
  true
);

reset role;

-- Les lignes renvoyées à l'administrateur, avec le prénom du participant.
create or replace function pg_temp.bench_rows(p_setting text)
returns table(
  first_name text,
  finished_bench_count integer,
  benched_last_time boolean
)
language sql
stable
as $function$
  select coalesce(season_player.first_name, guest.first_name),
         (bench_row ->> 'finished_bench_count')::integer,
         (bench_row ->> 'benched_last_time')::boolean
  from jsonb_array_elements(current_setting(p_setting)::jsonb) bench_row
  join public.match_sport_participants participant
    on participant.id = (bench_row ->> 'participant_id')::uuid
  left join public.season_players season_player
    on season_player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id;
$function$;

select results_eq(
  $$
    select first_name
    from pg_temp.bench_rows('test.bench_next_match')
    where benched_last_time
    order by first_name
  $$,
  $$ values ('Alix'::text), ('Dani'::text), ('Invité'::text) $$,
  'les remplaçants de leur dernier match joué sont signalés, invité compris'
);

select is(
  (
    select benched_last_time
    from pg_temp.bench_rows('test.bench_next_match')
    where first_name = 'Bao'
  ),
  false,
  'remplaçant puis titulaire : le dernier match joué fait foi'
);

select is(
  (
    select benched_last_time
    from pg_temp.bench_rows('test.bench_next_match')
    where first_name = 'Dani'
  ),
  true,
  'absent du dernier match de l’équipe, un remplaçant garde son tour'
);

select results_eq(
  $$
    select first_name, finished_bench_count
    from pg_temp.bench_rows('test.bench_next_match')
    order by first_name
  $$,
  $$
    values
      ('Alix'::text, 1),
      ('Bao'::text, 1),
      ('Cléo'::text, 1),
      ('Dani'::text, 1),
      ('Invité'::text, 1)
  $$,
  'le compteur banc cumulé est inchangé'
);

select is(
  (
    select count(*)::integer
    from pg_temp.bench_rows('test.bench_first_match')
    where benched_last_time
  ),
  0,
  'personne n’est signalé avant d’avoir joué un match de la saison'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b5000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.admin_get_finished_bench_counts(
      'b5500000-0000-0000-0000-000000000004'
    )
  $$,
  '42501',
  null,
  'un joueur non administrateur ne lit pas le banc'
);

reset role;

select * from finish();
rollback;
