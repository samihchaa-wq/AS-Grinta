begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Contrat de la fonction groupée du calendrier.
select ok(
  to_regprocedure('public.get_my_upcoming_match_states(uuid[])') is not null,
  'la fonction groupée du calendrier existe'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.get_my_upcoming_match_states(uuid[])'::regprocedure
  ),
  'la fonction groupée s''exécute avec les droits de l''appelant'
);

select ok(
  (
    select proconfig @> array['search_path=""']
    from pg_proc
    where oid = 'public.get_my_upcoming_match_states(uuid[])'::regprocedure
  ),
  'la fonction groupée garde un search_path vide'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_my_upcoming_match_states(uuid[])',
    'execute'
  ),
  'un visiteur non connecté ne peut pas appeler la fonction groupée'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_my_upcoming_match_states(uuid[])',
    'execute'
  ),
  'un membre connecté peut appeler la fonction groupée'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'b1000000-0000-0000-0000-000000000001',
    'upcoming-states-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Calendrier"}'::jsonb
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'upcoming-states-player@example.invalid',
    '{"first_name":"Joueur","last_name":"Calendrier"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'b1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'b1000000-0000-0000-0000-000000000001',
  'b1000000-0000-0000-0000-000000000002'
);

insert into public.seasons (id, name, status)
values ('b2000000-0000-0000-0000-000000000001', '2096-2097', 'open');

insert into public.opponents (id, name)
values ('b3000000-0000-0000-0000-000000000001', 'Adversaire calendrier groupé');

insert into public.season_players (
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
values (
  'b4000000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000001',
  'Joueur',
  'Calendrier',
  false,
  true,
  1,
  'b1000000-0000-0000-0000-000000000002'
);

insert into public.matches (
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  created_by,
  kickoff_at
)
select
  'b5000000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::date,
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::time,
  'domicile',
  90,
  'a_venir',
  'b1000000-0000-0000-0000-000000000001',
  now() + interval '48 hours';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'b1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.admin_sync_match_sport_workflow(
    'b5000000-0000-0000-0000-000000000001'
  ) is not null,
  'le workflow de disponibilité est créé normalement'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.get_my_upcoming_match_states(array[
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b5ffffff-0000-0000-0000-000000000099'
  ]::uuid[])
    -> 'b5000000-0000-0000-0000-000000000001' -> 'availability',
  public.get_my_match_availability('b5000000-0000-0000-0000-000000000001'),
  'la disponibilité groupée est identique à l''appel individuel'
);

select is(
  public.get_my_upcoming_match_states(array[
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b5ffffff-0000-0000-0000-000000000099'
  ]::uuid[])
    -> 'b5000000-0000-0000-0000-000000000001' -> 'live_notifications',
  public.get_match_live_notification_subscription(
    'b5000000-0000-0000-0000-000000000001'
  ),
  'l''état de la cloche groupé est identique à l''appel individuel'
);

select is(
  (public.get_my_upcoming_match_states(array[
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b5ffffff-0000-0000-0000-000000000099'
  ]::uuid[])
    -> 'b5000000-0000-0000-0000-000000000001' ->> 'availability_ok')::boolean
  and (public.get_my_upcoming_match_states(array[
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b5ffffff-0000-0000-0000-000000000099'
  ]::uuid[])
    -> 'b5000000-0000-0000-0000-000000000001' ->> 'live_notifications_ok')::boolean,
  true,
  'un match valide est marqué comme lu sans erreur'
);

select is(
  (select count(*) from jsonb_object_keys(public.get_my_upcoming_match_states(array[
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b5ffffff-0000-0000-0000-000000000099'
  ]::uuid[]))),
  2::bigint,
  'un match demandé deux fois n''apparaît qu''une fois'
);

select is(
  (public.get_my_upcoming_match_states(array[
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b5ffffff-0000-0000-0000-000000000099'
  ]::uuid[])
    -> 'b5ffffff-0000-0000-0000-000000000099' ->> 'live_notifications_ok')::boolean,
  false,
  'un match introuvable est signalé sans faire échouer les autres'
);

select throws_ok(
  format(
    'select public.get_my_upcoming_match_states(%L::uuid[])',
    (select array_agg(gen_random_uuid()) from generate_series(1, 61))
  ),
  '22023',
  null,
  'une demande de plus de 60 matchs est refusée'
);

reset role;
select set_config('request.jwt.claims', '', true);
set local role authenticated;

select throws_ok(
  'select public.get_my_upcoming_match_states(array[]::uuid[])',
  '42501',
  null,
  'un appel sans identité est refusé'
);

reset role;

select * from finish();
rollback;
