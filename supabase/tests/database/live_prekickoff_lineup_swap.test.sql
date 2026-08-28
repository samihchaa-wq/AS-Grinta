begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values (
  '42200000-0000-0000-0000-000000000001',
  'live-prekickoff-admin@example.invalid',
  '{"first_name":"Live","last_name":"Prekickoff"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '42200000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = null
where key = 'sports_management';

insert into public.seasons(id, name, status)
values (
  '42200000-0000-0000-0000-000000000010',
  '2099-2100',
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
  '42200000-0000-0000-0000-000000000020',
  '42200000-0000-0000-0000-000000000010',
  current_date + 1,
  '20:00'::time,
  'domicile',
  90,
  'a_venir',
  '42200000-0000-0000-0000-000000000001'
);

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position
)
values
  (
    '42200000-0000-0000-0000-000000000031',
    '42200000-0000-0000-0000-000000000010',
    'Titulaire',
    'Test',
    false,
    true,
    1
  ),
  (
    '42200000-0000-0000-0000-000000000032',
    '42200000-0000-0000-0000-000000000010',
    'Remplacant',
    'Test',
    false,
    true,
    2
  );

insert into public.match_sport_participants(
  id, match_id, season_player_id, is_eligible, selection_status
)
values
  (
    '42200000-0000-0000-0000-000000000041',
    '42200000-0000-0000-0000-000000000020',
    '42200000-0000-0000-0000-000000000031',
    true,
    'starter'
  ),
  (
    '42200000-0000-0000-0000-000000000042',
    '42200000-0000-0000-0000-000000000020',
    '42200000-0000-0000-0000-000000000032',
    true,
    'substitute'
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
  '42200000-0000-0000-0000-000000000020',
  '4-2-1-3',
  'published',
  1,
  false,
  now(),
  '42200000-0000-0000-0000-000000000001',
  '42200000-0000-0000-0000-000000000001'
);

insert into public.match_composition_entries(
  match_id, participant_id, zone, x, y, sort_order
)
values
  (
    '42200000-0000-0000-0000-000000000020',
    '42200000-0000-0000-0000-000000000041',
    'field',
    0.5,
    0.5,
    0
  ),
  (
    '42200000-0000-0000-0000-000000000020',
    '42200000-0000-0000-0000-000000000042',
    'bench',
    null,
    null,
    0
  );

insert into public.match_live_sessions(
  match_id,
  state,
  planned_duration_minutes,
  lineup_revision,
  updated_by
)
values (
  '42200000-0000-0000-0000-000000000020',
  'not_started',
  90,
  3,
  '42200000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.sub = '42200000-0000-0000-0000-000000000001';

-- Avant le coup d'envoi, echanger le titulaire et le remplacant est une simple
-- correction de composition : aucun remplacement n'est declare.
select lives_ok(
  $$select public.coach_save_match_live_lineup(
    '42200000-0000-0000-0000-000000000020',
    '[
      {"participant_id":"42200000-0000-0000-0000-000000000041","zone":"bench","sort_order":0},
      {"participant_id":"42200000-0000-0000-0000-000000000042","zone":"field","x":0.5,"y":0.5,"sort_order":0}
    ]'::jsonb,
    null,
    3
  )$$,
  'un echange titulaire/remplacant est accepte avant le coup d’envoi'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select zone::text
    from public.match_composition_entries
    where match_id = '42200000-0000-0000-0000-000000000020'
      and participant_id = '42200000-0000-0000-0000-000000000042'
  ),
  'field',
  'le remplacant est bien passe titulaire'
);

select is(
  (
    select selection_status::text
    from public.match_sport_participants
    where id = '42200000-0000-0000-0000-000000000041'
  ),
  'substitute',
  'l’ancien titulaire est repasse remplacant'
);

select is(
  (
    select count(*)::integer
    from public.match_live_events
    where match_id = '42200000-0000-0000-0000-000000000020'
  ),
  0,
  'aucun evenement de remplacement n’est cree avant le coup d’envoi'
);

-- Une fois le match lance, le garde-fou reste entier : franchir la frontiere
-- terrain/banc sans declarer de remplacement fausserait les Faits du match.
update public.match_live_sessions
set state = 'running',
    running_since = now(),
    started_at = now()
where match_id = '42200000-0000-0000-0000-000000000020';

set local role authenticated;
set local request.jwt.claim.sub = '42200000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.coach_save_match_live_lineup(
    '42200000-0000-0000-0000-000000000020',
    '[
      {"participant_id":"42200000-0000-0000-0000-000000000041","zone":"field","x":0.5,"y":0.5,"sort_order":0},
      {"participant_id":"42200000-0000-0000-0000-000000000042","zone":"bench","sort_order":0}
    ]'::jsonb,
    null,
    4
  )$$,
  '22023',
  'match lance : un echange terrain/banc non declare reste refuse'
);

-- Le meme echange declare comme remplacement passe et cree l'evenement.
select lives_ok(
  $$select public.coach_save_match_live_lineup(
    '42200000-0000-0000-0000-000000000020',
    '[
      {"participant_id":"42200000-0000-0000-0000-000000000041","zone":"field","x":0.5,"y":0.5,"sort_order":0},
      {"participant_id":"42200000-0000-0000-0000-000000000042","zone":"bench","sort_order":0}
    ]'::jsonb,
    '[{"player_in":"42200000-0000-0000-0000-000000000041","player_out":"42200000-0000-0000-0000-000000000042"}]'::jsonb,
    4
  )$$,
  'match lance : le meme echange declare comme remplacement est accepte'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)::integer
    from public.match_live_events
    where match_id = '42200000-0000-0000-0000-000000000020'
      and event_type = 'substitution'
  ),
  1,
  'le remplacement declare pendant le match cree bien son evenement'
);

select * from finish();
rollback;
