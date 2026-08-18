begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_table_privilege('authenticated', 'public.match_predictions', 'SELECT'),
  'authenticated keeps read access to match predictions through RLS'
);
select ok(
  has_table_privilege('authenticated', 'public.match_predictions', 'INSERT'),
  'authenticated legacy direct inserts remain supported behind RLS and trigger guards'
);
select ok(
  has_table_privilege('authenticated', 'public.match_predictions', 'UPDATE'),
  'authenticated legacy direct updates remain supported behind RLS and trigger guards'
);
select ok(
  not has_table_privilege('authenticated', 'public.match_predictions', 'DELETE'),
  'authenticated cannot delete match predictions directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.match_predictions', 'TRUNCATE'),
  'authenticated cannot truncate match predictions'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'fc100000-0000-0000-0000-000000000001',
    'prediction-history-viewer@example.invalid',
    '{"first_name":"Viewer","last_name":"History"}'::jsonb
  ),
  (
    'fc100000-0000-0000-0000-000000000002',
    'prediction-history-archived@example.invalid',
    '{"first_name":"Archived","last_name":"Participant"}'::jsonb
  ),
  (
    'fc100000-0000-0000-0000-000000000003',
    'prediction-history-nonparticipant@example.invalid',
    '{"first_name":"Archived","last_name":"Nonparticipant"}'::jsonb
  );

update public.profiles
set status = 'active',
    role = 'pronostiqueur',
    is_test_account = false,
    updated_at = now()
where id in (
  'fc100000-0000-0000-0000-000000000001',
  'fc100000-0000-0000-0000-000000000002',
  'fc100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('fc200000-0000-0000-0000-000000000001', '2086-2087', 'open');

insert into public.opponents(id, name)
values ('fc300000-0000-0000-0000-000000000001', 'Prediction History FC');

-- Historical prediction: fill while the player is active and the match is open,
-- then move the fixture to the past and validate it before archiving the account.
insert into public.matches(
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  match_type,
  created_by
) values (
  'fc400000-0000-0000-0000-000000000001',
  'fc200000-0000-0000-0000-000000000001',
  'fc300000-0000-0000-0000-000000000001',
  current_date + 1,
  time '20:00',
  'domicile',
  90,
  'a_venir',
  'championnat',
  'fc100000-0000-0000-0000-000000000001'
);

insert into public.match_odds(
  match_id,
  odds_victoire_as_grinta,
  odds_nul,
  odds_victoire_adverse
) values (
  'fc400000-0000-0000-0000-000000000001',
  2.00,
  3.20,
  4.00
)
on conflict (match_id) do update
set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
    odds_nul = excluded.odds_nul,
    odds_victoire_adverse = excluded.odds_victoire_adverse;

update public.match_predictions
set predicted_score_as_grinta = 2,
    predicted_score_adverse = 1,
    is_filled = true,
    updated_at = now()
where match_id = 'fc400000-0000-0000-0000-000000000001'
  and profile_id = 'fc100000-0000-0000-0000-000000000002';

update public.matches
set match_date = current_date - 1,
    match_time = time '20:00'
where id = 'fc400000-0000-0000-0000-000000000001';

update public.matches
set status = 'termine',
    score_as_grinta = 2,
    score_adverse = 1,
    result_validated_at = now()
where id = 'fc400000-0000-0000-0000-000000000001';

update public.profiles
set status = 'archived',
    updated_at = now()
where id in (
  'fc100000-0000-0000-0000-000000000002',
  'fc100000-0000-0000-0000-000000000003'
);

-- Internal fixture used to prove that the direct Data API path cannot bypass
-- the save_match_prediction RPC rule.
insert into public.matches(
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  match_type,
  created_by
) values (
  'fc400000-0000-0000-0000-000000000002',
  'fc200000-0000-0000-0000-000000000001',
  null,
  current_date + 1,
  time '20:30',
  'domicile',
  90,
  'a_venir',
  'entre_nous',
  'fc100000-0000-0000-0000-000000000001'
);

-- Normal fixture already inside T-15. Its seeded empty row must not be fillable
-- by a direct UPDATE even though authenticated keeps UPDATE for old clients.
insert into public.matches(
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  match_type,
  created_by
) values (
  'fc400000-0000-0000-0000-000000000003',
  'fc200000-0000-0000-0000-000000000001',
  'fc300000-0000-0000-0000-000000000001',
  ((now() + interval '10 minutes') at time zone 'Europe/Paris')::date,
  ((now() + interval '10 minutes') at time zone 'Europe/Paris')::time,
  'domicile',
  90,
  'a_venir',
  'championnat',
  'fc100000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fc100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  exists (
    select 1
    from public.v_classement_general
    where profile_id = 'fc100000-0000-0000-0000-000000000002'
      and match_points > 0
  ),
  'an archived real pronosticator remains visible after a revealed historical prediction'
);

select ok(
  not exists (
    select 1
    from public.v_classement_general
    where profile_id = 'fc100000-0000-0000-0000-000000000003'
  ),
  'an archived account with no filled prediction is not added to the leaderboard'
);

select throws_ok(
  $$
    insert into public.match_predictions(
      match_id,
      profile_id,
      predicted_score_as_grinta,
      predicted_score_adverse,
      is_filled
    ) values (
      'fc400000-0000-0000-0000-000000000002',
      'fc100000-0000-0000-0000-000000000001',
      1,
      0,
      true
    )
  $$,
  '22023',
  'a direct authenticated insert cannot create a prediction for an internal match'
);

select throws_ok(
  $$
    update public.match_predictions
    set predicted_score_as_grinta = 1,
        predicted_score_adverse = 0,
        is_filled = true
    where match_id = 'fc400000-0000-0000-0000-000000000003'
      and profile_id = 'fc100000-0000-0000-0000-000000000001'
  $$,
  '22023',
  'a direct authenticated update cannot fill a prediction inside T-15'
);

reset role;

select * from finish();
rollback;
