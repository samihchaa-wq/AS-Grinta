begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
  '97000000-0000-0000-0000-000000000001',
  'prediction-retry@example.invalid',
  '{"first_name":"Retry","last_name":"Prediction"}'::jsonb
);

update public.profiles
set role = 'pronostiqueur',
    status = 'active',
    updated_at = now()
where id = '97000000-0000-0000-0000-000000000001';

insert into public.seasons (id, name, status)
values ('97000000-0000-0000-0000-000000000002', '2099-2100', 'open');

insert into public.opponents (id, name)
values ('97000000-0000-0000-0000-000000000003', 'Adversaire Retry');

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  kickoff_at,
  location,
  planned_duration_minutes,
  status,
  created_by
)
select
  '97000000-0000-0000-0000-000000000004',
  '97000000-0000-0000-0000-000000000002',
  '97000000-0000-0000-0000-000000000003',
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::date,
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::time,
  now() + interval '48 hours',
  'domicile',
  90,
  'a_venir',
  '97000000-0000-0000-0000-000000000001';

create temporary table prediction_retry_update_counter (
  updates integer not null default 0
) on commit drop;
insert into prediction_retry_update_counter default values;

create function pg_temp.count_prediction_retry_update()
returns trigger
language plpgsql
security definer
set search_path to pg_temp
as $function$
begin
  update prediction_retry_update_counter
  set updates = updates + 1;
  return null;
end;
$function$;

create trigger test_count_prediction_retry_update
after update on public.match_predictions
for each row execute function pg_temp.count_prediction_retry_update();

select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.save_match_prediction(
    '97000000-0000-0000-0000-000000000004',
    2,
    1
  ),
  'le premier enregistrement du pronostic réussit'
);

reset role;
update prediction_retry_update_counter set updates = 0;

select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.save_match_prediction(
    '97000000-0000-0000-0000-000000000004',
    2,
    1
  ),
  'un retry avec le même payload retourne toujours succès'
);

reset role;
select is(
  (select updates from prediction_retry_update_counter),
  0,
  'un retry identique ne déclenche aucun UPDATE de match_predictions'
);
select is(
  (
    select count(*)
    from public.match_predictions
    where match_id = '97000000-0000-0000-0000-000000000004'
      and profile_id = '97000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'un retry identique conserve une seule mutation métier en base'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.save_match_prediction(
    '97000000-0000-0000-0000-000000000004',
    3,
    1
  ),
  'une vraie modification du score reste enregistrable'
);

reset role;
select is(
  (select updates from prediction_retry_update_counter),
  1,
  'une vraie modification déclenche exactement un UPDATE'
);
select is(
  (
    select predicted_score_as_grinta
    from public.match_predictions
    where match_id = '97000000-0000-0000-0000-000000000004'
      and profile_id = '97000000-0000-0000-0000-000000000001'
  ),
  3,
  'la vraie modification conserve le nouveau score'
);

select * from finish();
rollback;
