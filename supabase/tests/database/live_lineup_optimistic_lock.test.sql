begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regprocedure(
    'public.coach_save_match_live_lineup(uuid,jsonb,jsonb,integer)'
  ) is not null,
  'la RPC Live versionnée existe'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.coach_save_match_live_lineup(uuid,jsonb,jsonb,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.coach_save_match_live_lineup(uuid,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'seul un client authentifié peut appeler la RPC versionnée'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.save_match_live_lineup_versioned(uuid,jsonb,jsonb,integer)',
    'EXECUTE'
  ),
  'le helper privé versionné reste inaccessible directement au client'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  '42000000-0000-0000-0000-000000000001',
  'live-lock-admin@example.invalid',
  '{"first_name":"Live","last_name":"Lock"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '42000000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = null
where key = 'sports_management';

insert into public.seasons(id, name, status)
values (
  '42000000-0000-0000-0000-000000000010',
  'Saison test verrou Live',
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
  '42000000-0000-0000-0000-000000000020',
  '42000000-0000-0000-0000-000000000010',
  current_date + 1,
  '20:00'::time,
  'Terrain test',
  90,
  'a_venir',
  '42000000-0000-0000-0000-000000000001'
);

insert into public.match_live_sessions(
  match_id,
  planned_duration_minutes,
  lineup_revision,
  updated_by
)
values (
  '42000000-0000-0000-0000-000000000020',
  90,
  7,
  '42000000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    public.coach_save_match_live_lineup(
      '42000000-0000-0000-0000-000000000020',
      '[]'::jsonb,
      null,
      7
    ) ->> 'lineup_revision'
  )::integer,
  8,
  'la première sauvegarde fondée sur la révision 7 passe et produit la révision 8'
);

select throws_ok(
  $$select public.coach_save_match_live_lineup(
    '42000000-0000-0000-0000-000000000020',
    '[]'::jsonb,
    null,
    7
  )$$,
  '40001',
  'une seconde sauvegarde fondée sur la révision obsolète 7 est refusée'
);

reset role;

select is(
  (
    select lineup_revision
    from public.match_live_sessions
    where match_id = '42000000-0000-0000-0000-000000000020'
  ),
  8,
  'le conflit n’écrit rien et laisse la révision serveur à 8'
);

select * from finish();
rollback;
