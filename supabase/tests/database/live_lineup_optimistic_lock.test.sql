begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'coach_save_match_live_lineup'
      and proc.pronargs = 4
      and pg_get_function_arguments(proc.oid)
        like '%p_expected_lineup_revision integer%'
  ),
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
  '2097-2098',
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
  'domicile',
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

reset role;
-- Seul le coach de la saison pilote le Live : le compte qui pilote ce test
-- est déclaré coach, sans être ajouté aux matchs déjà créés.
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,is_coach,profile_id
) values (
  '42000000-0000-0000-0000-0000000000c1','42000000-0000-0000-0000-000000000010','Pilote','Coach',false,false,true,'42000000-0000-0000-0000-000000000001'
);
set local session_replication_role=replica;
update public.season_players set is_active=true where id='42000000-0000-0000-0000-0000000000c1';
set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"42000000-0000-0000-0000-000000000099"}',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.claim_match_live_pilot(
    '42000000-0000-0000-0000-000000000020',
    90
  )$$,
  'le coach prend la place de pilote avant de sauver la composition'
);

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
select set_config('request.jwt.claims', '{}', true);

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
