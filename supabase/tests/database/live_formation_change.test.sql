begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_change_match_live_formation'
      and pg_get_function_identity_arguments(proc.oid) =
        'p_match_id uuid, p_formation_code text, p_entries jsonb, p_expected_lineup_revision integer'
  ),
  'la RPC de changement de dispositif Live existe'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.coach_change_match_live_formation(uuid,text,jsonb,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.coach_change_match_live_formation(uuid,text,jsonb,integer)',
    'EXECUTE'
  ),
  'la RPC est réservée aux clients authentifiés'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  '42100000-0000-0000-0000-000000000001',
  'live-formation-admin@example.invalid',
  '{"first_name":"Live","last_name":"Formation"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '42100000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = null
where key = 'sports_management';

insert into public.seasons(id, name, status)
values (
  '42100000-0000-0000-0000-000000000010',
  '2098-2099',
  'open'
);

insert into public.matches(
  id,
  season_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  created_by
)
values (
  '42100000-0000-0000-0000-000000000020',
  '42100000-0000-0000-0000-000000000010',
  current_date + 1,
  '20:00'::time,
  'domicile',
  90,
  'a_venir',
  '42100000-0000-0000-0000-000000000001'
);

insert into public.match_sport_workflows(
  match_id,
  availability_opens_at,
  created_by,
  updated_by
)
values (
  '42100000-0000-0000-0000-000000000020',
  now() - interval '1 day',
  '42100000-0000-0000-0000-000000000001',
  '42100000-0000-0000-0000-000000000001'
);

insert into public.match_compositions(
  match_id,
  formation_code,
  status,
  version,
  has_unpublished_changes,
  published_at,
  published_by,
  last_modified_by
)
values (
  '42100000-0000-0000-0000-000000000020',
  '4-2-1-3',
  'published',
  1,
  false,
  now(),
  '42100000-0000-0000-0000-000000000001',
  '42100000-0000-0000-0000-000000000001'
);

insert into public.match_live_sessions(
  match_id,
  planned_duration_minutes,
  lineup_revision,
  updated_by
)
values (
  '42100000-0000-0000-0000-000000000020',
  90,
  7,
  '42100000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.sub = '42100000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.coach_change_match_live_formation(
    '42100000-0000-0000-0000-000000000020',
    '3-5-2',
    '[]'::jsonb,
    7
  )$$,
  'un coach peut changer le dispositif pendant une session Live ouverte'
);

select throws_ok(
  $$select public.coach_change_match_live_formation(
    '42100000-0000-0000-0000-000000000020',
    '4-2-1-3',
    '[]'::jsonb,
    7
  )$$,
  '40001',
  'une révision Live obsolète est refusée'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select formation_code
    from public.match_compositions
    where match_id = '42100000-0000-0000-0000-000000000020'
  ),
  '3-5-2',
  'le nouveau dispositif est persisté'
);

select is(
  (
    select lineup_revision
    from public.match_live_sessions
    where match_id = '42100000-0000-0000-0000-000000000020'
  ),
  8,
  'le changement avance la révision du lineup'
);

select is(
  (
    select count(*)::integer
    from public.match_live_events
    where match_id = '42100000-0000-0000-0000-000000000020'
  ),
  0,
  'un changement de dispositif ne crée aucun événement de remplacement'
);

select * from finish();
rollback;
