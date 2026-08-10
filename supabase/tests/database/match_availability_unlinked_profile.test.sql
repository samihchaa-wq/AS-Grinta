begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'availability-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Availability"}'::jsonb
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'availability-unlinked@example.invalid',
    '{"first_name":"Sans","last_name":"Joueur"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'a1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'a1000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000002'
);

insert into public.seasons (id, name, status)
values ('a2000000-0000-0000-0000-000000000001', '2098-2099', 'open');

insert into public.opponents (id, name)
values ('a3000000-0000-0000-0000-000000000001', 'Adversaire disponibilité');

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
  'a4000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'Joueur',
  'Éligible',
  false,
  true,
  1,
  null
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
  'a5000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001',
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::date,
  ((now() + interval '48 hours') at time zone 'Europe/Paris')::time,
  'domicile',
  90,
  'a_venir',
  'a1000000-0000-0000-0000-000000000001',
  now() + interval '48 hours';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'a1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.admin_sync_match_sport_workflow(
    'a5000000-0000-0000-0000-000000000001'
  ) is not null,
  'le workflow de disponibilité est créé normalement'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.get_my_match_availability(
    'a5000000-0000-0000-0000-000000000001'
  ) is null,
  'un compte actif non relié à un joueur reçoit une réponse vide sans erreur serveur'
);

select is(
  (
    select count(*)
    from public.match_sport_participants
    where match_id = 'a5000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'un compte non relié ne voit aucune ligne de disponibilité privée'
);

select * from finish();
rollback;
