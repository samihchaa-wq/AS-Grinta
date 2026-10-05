begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values (
  '43000000-0000-0000-0000-000000000001',
  'live-late-bench-admin@example.invalid',
  '{"first_name":"Live","last_name":"Bench"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '43000000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = null
where key = 'sports_management';

insert into public.seasons(id, name, status)
values (
  '43000000-0000-0000-0000-000000000010',
  '2096-2097',
  'open'
);

insert into public.players(id, display_name)
values (
  '43000000-0000-0000-0000-000000000015',
  'Late Bench Player'
);

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  player_id,
  is_active
)
values (
  '43000000-0000-0000-0000-000000000016',
  '43000000-0000-0000-0000-000000000010',
  'Late',
  'Bench',
  '43000000-0000-0000-0000-000000000015',
  true
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
  '43000000-0000-0000-0000-000000000020',
  '43000000-0000-0000-0000-000000000010',
  current_date,
  '20:00'::time,
  'domicile',
  90,
  'a_venir',
  '43000000-0000-0000-0000-000000000001'
);

insert into public.match_sport_workflows(
  match_id,
  availability_opens_at,
  created_by,
  updated_by
)
values (
  '43000000-0000-0000-0000-000000000020',
  now() - interval '6 days',
  '43000000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001'
);

insert into public.match_compositions(
  match_id,
  formation_code,
  status,
  version,
  has_unpublished_changes,
  last_modified_by
)
values (
  '43000000-0000-0000-0000-000000000020',
  '4-2-1-3',
  'draft',
  0,
  true,
  '43000000-0000-0000-0000-000000000001'
);

insert into public.match_sport_participants(
  id,
  match_id,
  season_player_id,
  is_eligible
)
values (
  '43000000-0000-0000-0000-000000000030',
  '43000000-0000-0000-0000-000000000020',
  '43000000-0000-0000-0000-000000000016',
  true
);

insert into public.match_live_sessions(
  match_id,
  state,
  planned_duration_minutes,
  elapsed_seconds,
  running_since,
  started_at,
  starting_lineup_snapshot,
  updated_by
)
values (
  '43000000-0000-0000-0000-000000000020',
  'running',
  90,
  60,
  now(),
  now() - interval '1 minute',
  '{}'::jsonb,
  '43000000-0000-0000-0000-000000000001'
);

reset role;
-- Seul le coach de la saison pilote le Live : le compte qui pilote ce test
-- est déclaré coach, sans être ajouté aux matchs déjà créés.
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,is_coach,profile_id
) values (
  '43000000-0000-0000-0000-0000000000c1','43000000-0000-0000-0000-000000000010','Pilote','Coach',false,false,true,'43000000-0000-0000-0000-000000000001'
);
set local session_replication_role=replica;
update public.season_players set is_active=true where id='43000000-0000-0000-0000-0000000000c1';
set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"43000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated","session_id":"43000000-0000-0000-0000-000000000099"}',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.claim_match_live_pilot(
    '43000000-0000-0000-0000-000000000020',
    90
  )$$,
  'le coach prend la place de pilote avant de modifier le Live'
);

select lives_ok(
  $$select public.coach_add_match_live_players(
    '43000000-0000-0000-0000-000000000020',
    '[{"kind":"roster","season_player_id":"43000000-0000-0000-0000-000000000016"}]'::jsonb,
    'pgTAP late bench regression'
  )$$,
  'un joueur ajouté pendant le Live peut rejoindre le banc'
);

select is(
  (
    public.get_match_live_state(
      '43000000-0000-0000-0000-000000000020'
    ) -> 'substitute_counts' ->> '43000000-0000-0000-0000-000000000030'
  )::integer,
  1,
  'un joueur ajouté pendant le Live démarre immédiatement avec un passage sur le banc'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

select is(
  (
    select starting_lineup_snapshot ->> '43000000-0000-0000-0000-000000000030'
    from public.match_live_sessions
    where match_id = '43000000-0000-0000-0000-000000000020'
  ),
  'bench',
  'le baseline Live mémorise cette première présence sur le banc'
);

select is(
  (
    select zone::text
    from public.match_composition_entries
    where match_id = '43000000-0000-0000-0000-000000000020'
      and participant_id = '43000000-0000-0000-0000-000000000030'
  ),
  'bench',
  'le joueur ajouté reste bien dans la zone banc'
);

select * from finish();
rollback;
