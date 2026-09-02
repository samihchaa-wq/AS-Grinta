begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from pg_trigger season_trigger
    where season_trigger.tgrelid = 'public.seasons'::regclass
      and season_trigger.tgname = 'trg_finalize_season_competition'
      and not season_trigger.tgisinternal
  )
  and not exists (
    select 1
    from pg_trigger season_trigger
    where season_trigger.tgrelid = 'public.seasons'::regclass
      and season_trigger.tgname in (
        'trg_award_titles',
        'trg_sync_season_prediction_roster_snapshot'
      )
      and not season_trigger.tgisinternal
  ),
  'snapshot and titles use one deterministic season trigger'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.assert_season_can_archive(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.finalize_season_competition_transition()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.guard_match_season_finality()',
    'EXECUTE'
  ),
  'season finalization helpers are not client-callable'
);

select ok(
  exists (
    select 1
    from pg_trigger match_trigger
    where match_trigger.tgrelid = 'public.matches'::regclass
      and match_trigger.tgname = 'trg_guard_match_season_finality'
      and not match_trigger.tgisinternal
  )
  and position(
    'for share' in lower(pg_get_functiondef(
      'private.guard_match_season_finality()'::regprocedure
    ))
  ) > 0,
  'match additions lock the parent season against a concurrent archive'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'a7100000-0000-0000-0000-000000000001',
    'season-archive-admin@example.invalid',
    '{"first_name":"ArchiveAdmin"}'::jsonb
  ),
  (
    'a7100000-0000-0000-0000-000000000002',
    'season-archive-a@example.invalid',
    '{"first_name":"ArchiveA"}'::jsonb
  ),
  (
    'a7100000-0000-0000-0000-000000000003',
    'season-archive-b@example.invalid',
    '{"first_name":"ArchiveB"}'::jsonb
  ),
  (
    'a7100000-0000-0000-0000-000000000004',
    'season-archive-test@example.invalid',
    '{"first_name":"ArchiveTest"}'::jsonb
  );

update public.profiles
set status = 'active',
    role = case
      when id = 'a7100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    is_test_account = id = 'a7100000-0000-0000-0000-000000000004'
where id between
  'a7100000-0000-0000-0000-000000000001'
  and 'a7100000-0000-0000-0000-000000000004';

-- Direct open -> archived: before this migration, the title trigger used all
-- roster rows (including the coach/inactive player), found nobody complete,
-- and ran before the final active non-coach snapshot was created.
insert into public.seasons(id, name, status)
values ('a7200000-0000-0000-0000-000000000001', '2099-2100', 'open');

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  is_coach,
  position
)
values
  (
    'a7300000-0000-0000-0000-000000000001',
    'a7200000-0000-0000-0000-000000000001',
    'Final', 'Target', false, true, false, 1
  ),
  (
    'a7300000-0000-0000-0000-000000000002',
    'a7200000-0000-0000-0000-000000000001',
    'Coach', 'Excluded', false, true, true, 2
  ),
  (
    'a7300000-0000-0000-0000-000000000003',
    'a7200000-0000-0000-0000-000000000001',
    'Inactive', 'Excluded', false, true, false, 3
  );

-- Un joueur ne peut pas naître inactif : seed_season_predictions_for_player()
-- crée aussitôt ses lignes de pronostic et validate_season_prediction_row()
-- les refuse pour un joueur inactif. On suit donc le vrai cycle de vie, le
-- joueur appartient d'abord à l'effectif puis en sort.
update public.season_players
set is_active = false
where id = 'a7300000-0000-0000-0000-000000000003';

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'a7200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'a7300000-0000-0000-0000-000000000001',
    'category', 'buts',
    'predicted_value_30', 0
  ))
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'a7200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'a7300000-0000-0000-0000-000000000001',
    'category', 'buts',
    'predicted_value_30', 0
  ))
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000004","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'a7200000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'season_player_id', 'a7300000-0000-0000-0000-000000000001',
    'category', 'buts',
    'predicted_value_30', 0
  ))
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);

-- L'archivage d'un compte est une action de staff : guard_sensitive_profile_fields()
-- refuse cette ecriture tant que l'identite courante est celle d'un autre membre.
update public.profiles
set status = 'archived'
where id = 'a7100000-0000-0000-0000-000000000003';

set local role authenticated;
select public.set_season_status(
  'a7200000-0000-0000-0000-000000000001',
  'archived'
);
reset role;

select is(
  (
    select capture.capture_reason
    from public.season_prediction_roster_captures capture
    where capture.season_id = 'a7200000-0000-0000-0000-000000000001'
  ),
  'archive',
  'direct archive records an archive snapshot'
);

select is(
  (
    select count(*)
    from public.season_prediction_roster_members member
    where member.season_id = 'a7200000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'direct archive freezes only the final active non-coach roster'
);

select ok(
  exists (
    select 1
    from public.season_awards award
    where award.season_id = 'a7200000-0000-0000-0000-000000000001'
      and award.profile_id = 'a7100000-0000-0000-0000-000000000002'
      and award.award_type = 'best_pred_player'
  )
  and exists (
    select 1
    from public.season_awards award
    where award.season_id = 'a7200000-0000-0000-0000-000000000001'
      and award.profile_id = 'a7100000-0000-0000-0000-000000000003'
      and award.award_type = 'best_pred_player'
  ),
  'active and archived real co-leaders receive the tied season title'
);

select ok(
  not exists (
    select 1
    from public.season_awards award
    where award.season_id = 'a7200000-0000-0000-0000-000000000001'
      and award.profile_id = 'a7100000-0000-0000-0000-000000000004'
  ),
  'test predictor is excluded before tied titles are awarded'
);

-- Lock -> roster changes -> archive: the committed lock snapshot wins and is
-- the exact scope used by both titles and the final leaderboard.
update public.profiles
set status = 'active'
where id = 'a7100000-0000-0000-0000-000000000003';

insert into public.seasons(id, name, status)
values ('a7200000-0000-0000-0000-000000000002', '2098-2099', 'open');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, is_coach, position
)
values
  (
    'a7300000-0000-0000-0000-000000000011',
    'a7200000-0000-0000-0000-000000000002',
    'Locked', 'One', false, true, false, 1
  ),
  (
    'a7300000-0000-0000-0000-000000000012',
    'a7200000-0000-0000-0000-000000000002',
    'Locked', 'Two', false, true, false, 2
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'a7200000-0000-0000-0000-000000000002',
  jsonb_build_array(
    jsonb_build_object(
      'season_player_id', 'a7300000-0000-0000-0000-000000000011',
      'category', 'buts', 'predicted_value_30', 0
    ),
    jsonb_build_object(
      'season_player_id', 'a7300000-0000-0000-0000-000000000012',
      'category', 'buts', 'predicted_value_30', 0
    )
  )
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.set_season_predictions_lock(
  'a7200000-0000-0000-0000-000000000002',
  true
);
reset role;

update public.season_players
set is_active = false
where id = 'a7300000-0000-0000-0000-000000000012';

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, is_coach, position
)
values (
  'a7300000-0000-0000-0000-000000000013',
  'a7200000-0000-0000-0000-000000000002',
  'Added', 'AfterLock', false, true, false, 3
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.set_season_status(
  'a7200000-0000-0000-0000-000000000002',
  'archived'
);
reset role;

select ok(
  (
    select capture.capture_reason = 'lock'
    from public.season_prediction_roster_captures capture
    where capture.season_id = 'a7200000-0000-0000-0000-000000000002'
  )
  and exists (
    select 1 from public.season_prediction_roster_members
    where season_player_id = 'a7300000-0000-0000-0000-000000000012'
  )
  and not exists (
    select 1 from public.season_prediction_roster_members
    where season_player_id = 'a7300000-0000-0000-0000-000000000013'
  ),
  'archive preserves the prior lock snapshot after roster changes'
);

select ok(
  exists (
    select 1
    from public.season_awards award
    where award.season_id = 'a7200000-0000-0000-0000-000000000002'
      and award.profile_id = 'a7100000-0000-0000-0000-000000000002'
      and award.award_type = 'best_pred_player'
  ),
  'locked-roster leader receives the title computed on that same snapshot'
);

-- Empty archive -> reopen -> later lock: safe recovery must remove the old
-- archive snapshot so the later lock can capture the new roster.
insert into public.seasons(id, name, status)
values ('a7200000-0000-0000-0000-000000000003', '2097-2098', 'open');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, is_coach, position
)
values (
  'a7300000-0000-0000-0000-000000000021',
  'a7200000-0000-0000-0000-000000000003',
  'Recovery', 'One', false, true, false, 1
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.set_season_status(
  'a7200000-0000-0000-0000-000000000003',
  'archived'
);
select public.set_season_status(
  'a7200000-0000-0000-0000-000000000003',
  'open'
);
reset role;

select ok(
  not exists (
    select 1
    from public.season_prediction_roster_captures
    where season_id = 'a7200000-0000-0000-0000-000000000003'
  ),
  'safe empty-season reopen removes the obsolete archive snapshot'
);

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, is_coach, position
)
values (
  'a7300000-0000-0000-0000-000000000022',
  'a7200000-0000-0000-0000-000000000003',
  'Recovery', 'Two', false, true, false, 2
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.set_season_predictions_lock(
  'a7200000-0000-0000-0000-000000000003',
  true
);
reset role;

select is(
  (
    select count(*)
    from public.season_prediction_roster_members
    where season_id = 'a7200000-0000-0000-0000-000000000003'
  ),
  2::bigint,
  'later lock captures the roster added after safe reopen'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.set_season_status(
  'a7200000-0000-0000-0000-000000000003',
  'archived'
);
reset role;

-- No archive may award titles while a match is unfinished or still inside
-- its 24-hour correction window. A failed archive is fully rolled back.
insert into public.seasons(id, name, status)
values ('a7200000-0000-0000-0000-000000000004', '2096-2097', 'open');
insert into public.opponents(id, name)
values ('a7400000-0000-0000-0000-000000000001', 'Archive Atomicity FC');

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.archive_match',
  public.admin_create_match_complete(
    'a7200000-0000-0000-0000-000000000004',
    'a7400000-0000-0000-0000-000000000001',
    ((now() + interval '2 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 days') at time zone 'Europe/Paris')::time,
    'domicile', 2, 3, 4, null, null, false, 'championnat', null
  )::text,
  true
);

select throws_ok(
  $$
    select public.set_season_status(
      'a7200000-0000-0000-0000-000000000004'::uuid,
      'archived'
    )
  $$,
  '22023',
  'Une saison avec des matchs non terminés ne peut pas être archivée.',
  'unfinished match blocks season archive'
);
reset role;

select ok(
  (select status = 'open' from public.seasons
   where id = 'a7200000-0000-0000-0000-000000000004')
  and not exists (
    select 1 from public.season_prediction_roster_captures
    where season_id = 'a7200000-0000-0000-0000-000000000004'
  ),
  'rejected unfinished archive leaves status and snapshot unchanged'
);

set local session_replication_role = replica;
update public.matches
set kickoff_at = '2007-03-17 20:00:00+00',
    match_date = '2007-03-17',
    match_time = '21:00:00'
where id = current_setting('test.archive_match')::uuid;
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"a7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
select public.finalize_match_postgame(
  current_setting('test.archive_match')::uuid,
  1,
  '[]'::jsonb,
  null,
  0
);
set local role authenticated;
select throws_ok(
  $$
    select public.set_season_status(
      'a7200000-0000-0000-0000-000000000004'::uuid,
      'archived'
    )
  $$,
  '22023',
  'Une saison ne peut pas être archivée pendant une fenêtre de correction de match.',
  'open post-match correction window blocks season archive'
);
select public.archive_match(current_setting('test.archive_match')::uuid);
select public.set_season_status(
  'a7200000-0000-0000-0000-000000000004',
  'archived'
);
reset role;

select ok(
  (select status = 'archived' from public.seasons
   where id = 'a7200000-0000-0000-0000-000000000004')
  and exists (
    select 1 from public.season_prediction_roster_captures
    where season_id = 'a7200000-0000-0000-0000-000000000004'
  ),
  'season archive succeeds atomically once the match is explicitly final'
);

select throws_ok(
  format(
    'update public.matches set status = %L where id = %L::uuid',
    'a_venir',
    current_setting('test.archive_match')
  ),
  '22023',
  'Les matchs d''une saison archivée sont immuables.',
  'a stale direct write cannot reopen a match after season archival'
);

select throws_ok(
  $$
    insert into public.matches(
      season_id,
      opponent_id,
      match_date,
      match_time,
      location,
      planned_duration_minutes,
      status
    ) values (
      'a7200000-0000-0000-0000-000000000004'::uuid,
      'a7400000-0000-0000-0000-000000000001'::uuid,
      ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
      ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
      'domicile',
      90,
      'a_venir'
    )
  $$,
  '22023',
  'Un match ne peut être ajouté qu''à une saison ouverte.',
  'a stale direct insert cannot add a match after season archival'
);

select * from finish();
rollback;
