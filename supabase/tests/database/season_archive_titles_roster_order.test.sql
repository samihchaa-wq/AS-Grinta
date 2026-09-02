-- Archiving a season must freeze the prediction roster before the titles are
-- computed, whether or not the season was prediction-locked first.
begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data) values
  ('c1100000-0000-0000-0000-000000000001', 'archive-order-admin@example.invalid', '{"first_name":"ArchiveAdmin"}'::jsonb),
  ('c1100000-0000-0000-0000-000000000002', 'archive-order-full@example.invalid', '{"first_name":"ArchiveFull"}'::jsonb),
  ('c1100000-0000-0000-0000-000000000003', 'archive-order-partial@example.invalid', '{"first_name":"ArchivePartial"}'::jsonb);

update public.profiles
set status = 'active',
    role = case
      when id = 'c1100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end
where id in (
  'c1100000-0000-0000-0000-000000000001',
  'c1100000-0000-0000-0000-000000000002',
  'c1100000-0000-0000-0000-000000000003'
);

-- ---------------------------------------------------------------------------
-- Season archived directly, without any prediction lock.
-- ---------------------------------------------------------------------------
insert into public.seasons(id, name, status)
values ('c1200000-0000-0000-0000-000000000001', '2081-2082', 'open');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, is_coach, position
) values
  ('c1300000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'Buteur', 'Direct', false, true, false, 1),
  ('c1300000-0000-0000-0000-000000000002', 'c1200000-0000-0000-0000-000000000001', 'Gardien', 'Direct', true, true, false, 2),
  ('c1300000-0000-0000-0000-000000000003', 'c1200000-0000-0000-0000-000000000001', 'Coach', 'Direct', false, true, true, 3),
  ('c1300000-0000-0000-0000-000000000004', 'c1200000-0000-0000-0000-000000000001', 'Retraite', 'Direct', false, true, false, 4);

-- Un joueur ne peut pas être créé inactif : le préremplissage des pronostics
-- refuse la ligne. On reproduit le vrai cycle de vie, il joue puis il sort de
-- l'effectif actif.
update public.season_players
set is_active = false
where id = 'c1300000-0000-0000-0000-000000000004';

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.save_my_season_predictions(
  'c1200000-0000-0000-0000-000000000001',
  jsonb_build_array(
    jsonb_build_object('season_player_id', 'c1300000-0000-0000-0000-000000000001', 'category', 'buts', 'predicted_value_30', 12),
    jsonb_build_object('season_player_id', 'c1300000-0000-0000-0000-000000000002', 'category', 'clean_sheets', 'predicted_value_30', 7)
  )
);
reset role;

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.set_season_status('c1200000-0000-0000-0000-000000000001', 'archived');
reset role;

select is(
  (select capture_reason from public.season_prediction_roster_captures
   where season_id = 'c1200000-0000-0000-0000-000000000001'),
  'archive',
  'archiving an unlocked season captures the roster'
);

select is(
  (select count(*) from public.season_prediction_roster_members
   where season_id = 'c1200000-0000-0000-0000-000000000001'),
  2::bigint,
  'the captured roster holds the active non-coach players only'
);

select ok(
  not exists (
    select 1 from public.season_prediction_roster_members
    where season_id = 'c1200000-0000-0000-0000-000000000001'
      and season_player_id in (
        'c1300000-0000-0000-0000-000000000003',
        'c1300000-0000-0000-0000-000000000004'
      )
  ),
  'coach and inactive player never enter the captured roster'
);

-- The regression: titles used to be computed against the raw season_players
-- list, where expected_count was 4 instead of 2, so no predictor was eligible.
select ok(
  exists (
    select 1 from public.season_awards
    where season_id = 'c1200000-0000-0000-0000-000000000001'
      and profile_id = 'c1100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_player'
  ),
  'the complete predictor wins the season prediction title on a direct archive'
);

select ok(
  exists (
    select 1 from public.season_awards
    where season_id = 'c1200000-0000-0000-0000-000000000001'
      and profile_id = 'c1100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_overall'
  ),
  'the overall prediction title follows the same roster on a direct archive'
);

select ok(
  not exists (
    select 1 from public.season_awards
    where season_id = 'c1200000-0000-0000-0000-000000000001'
      and profile_id = 'c1100000-0000-0000-0000-000000000003'
      and award_type = 'best_pred_player'
  ),
  'an incomplete predictor stays out of the season prediction title'
);

-- The awarded title matches what the leaderboard shows after the archive.
select is(
  (select count(distinct predictor_profile_id) from public.v_season_prediction_points
   where season_id = 'c1200000-0000-0000-0000-000000000001'),
  1::bigint,
  'only the complete predictor scores on the archived season'
);

-- ---------------------------------------------------------------------------
-- Season locked first, then archived: the lock capture must survive.
-- ---------------------------------------------------------------------------
insert into public.seasons(id, name, status)
values ('c1200000-0000-0000-0000-000000000002', '2082-2083', 'open');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, is_coach, position
) values
  ('c1300000-0000-0000-0000-000000000011', 'c1200000-0000-0000-0000-000000000002', 'Buteur', 'Lock', false, true, false, 1),
  ('c1300000-0000-0000-0000-000000000012', 'c1200000-0000-0000-0000-000000000002', 'Gardien', 'Lock', true, true, false, 2);

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.save_my_season_predictions(
  'c1200000-0000-0000-0000-000000000002',
  jsonb_build_array(
    jsonb_build_object('season_player_id', 'c1300000-0000-0000-0000-000000000011', 'category', 'buts', 'predicted_value_30', 9),
    jsonb_build_object('season_player_id', 'c1300000-0000-0000-0000-000000000012', 'category', 'clean_sheets', 'predicted_value_30', 4)
  )
);
reset role;

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.set_season_predictions_lock('c1200000-0000-0000-0000-000000000002', true);
reset role;

select is(
  (select capture_reason from public.season_prediction_roster_captures
   where season_id = 'c1200000-0000-0000-0000-000000000002'),
  'lock',
  'locking a season captures the roster'
);

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.set_season_status('c1200000-0000-0000-0000-000000000002', 'archived');
reset role;

select is(
  (select capture_reason from public.season_prediction_roster_captures
   where season_id = 'c1200000-0000-0000-0000-000000000002'),
  'lock',
  'archiving never overwrites the lock capture'
);

select ok(
  exists (
    select 1 from public.season_awards
    where season_id = 'c1200000-0000-0000-0000-000000000002'
      and profile_id = 'c1100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_player'
  ),
  'the lock-then-archive path still awards the season prediction title'
);

-- ---------------------------------------------------------------------------
-- Implicit archive: opening another season closes the previous one.
-- ---------------------------------------------------------------------------
insert into public.seasons(id, name, status)
values ('c1200000-0000-0000-0000-000000000003', '2083-2084', 'open');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, is_coach, position
) values
  ('c1300000-0000-0000-0000-000000000021', 'c1200000-0000-0000-0000-000000000003', 'Buteur', 'Rollover', false, true, false, 1),
  ('c1300000-0000-0000-0000-000000000022', 'c1200000-0000-0000-0000-000000000003', 'Coach', 'Rollover', false, true, true, 2);

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.save_my_season_predictions(
  'c1200000-0000-0000-0000-000000000003',
  jsonb_build_array(
    jsonb_build_object('season_player_id', 'c1300000-0000-0000-0000-000000000021', 'category', 'buts', 'predicted_value_30', 5)
  )
);
reset role;

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;
select public.open_or_create_season('2084-2085');
reset role;

select is(
  (select status from public.seasons where id = 'c1200000-0000-0000-0000-000000000003'),
  'archived',
  'opening a new season archives the previous one'
);

select ok(
  exists (
    select 1 from public.season_awards
    where season_id = 'c1200000-0000-0000-0000-000000000003'
      and profile_id = 'c1100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_player'
  ),
  'the implicit rollover archive awards the season prediction title too'
);

-- ---------------------------------------------------------------------------
-- Invariant: the legacy roster fallback in the scoring views must stay dead.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.seasons season
   where (season.season_predictions_locked_at is not null or season.status = 'archived')
     and not exists (
       select 1 from public.season_prediction_roster_captures capture
       where capture.season_id = season.id
     )),
  0::bigint,
  'every locked or archived season owns a roster capture'
);

select * from finish();
rollback;
