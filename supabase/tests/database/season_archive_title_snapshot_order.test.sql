begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'fa100000-0000-0000-0000-000000000001',
    'archive-title-admin@example.invalid',
    '{"first_name":"Archive Admin"}'::jsonb
  ),
  (
    'fa100000-0000-0000-0000-000000000002',
    'archive-title-a@example.invalid',
    '{"first_name":"Archive A"}'::jsonb
  ),
  (
    'fa100000-0000-0000-0000-000000000003',
    'archive-title-b@example.invalid',
    '{"first_name":"Archive B"}'::jsonb
  );

update public.profiles
set status = 'active',
    role = case
      when id = 'fa100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    is_test_account = false,
    updated_at = now()
where id in (
  'fa100000-0000-0000-0000-000000000001',
  'fa100000-0000-0000-0000-000000000002',
  'fa100000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status, season_predictions_locked_at)
values (
  'fa200000-0000-0000-0000-000000000001',
  '2074-2075',
  'open',
  null
);

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position
)
values
  (
    'fa300000-0000-0000-0000-000000000001',
    'fa200000-0000-0000-0000-000000000001',
    'Final', 'Roster', false, true, 1
  ),
  (
    'fa300000-0000-0000-0000-000000000002',
    'fa200000-0000-0000-0000-000000000001',
    'Removed', 'One', false, true, 2
  ),
  (
    'fa300000-0000-0000-0000-000000000003',
    'fa200000-0000-0000-0000-000000000001',
    'Removed', 'Two', false, true, 3
  );

-- Both predictors submit the complete three-player grid while every player is
-- active. With zero actual goals, A is exact only on the player who will stay
-- active, while B is exact only on the two players removed before archive.
select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'fa200000-0000-0000-0000-000000000001',
  jsonb_build_array(
    jsonb_build_object(
      'season_player_id', 'fa300000-0000-0000-0000-000000000001',
      'category', 'buts',
      'predicted_value_30', 0
    ),
    jsonb_build_object(
      'season_player_id', 'fa300000-0000-0000-0000-000000000002',
      'category', 'buts',
      'predicted_value_30', 99
    ),
    jsonb_build_object(
      'season_player_id', 'fa300000-0000-0000-0000-000000000003',
      'category', 'buts',
      'predicted_value_30', 99
    )
  )
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.save_my_season_predictions(
  'fa200000-0000-0000-0000-000000000001',
  jsonb_build_array(
    jsonb_build_object(
      'season_player_id', 'fa300000-0000-0000-0000-000000000001',
      'category', 'buts',
      'predicted_value_30', 99
    ),
    jsonb_build_object(
      'season_player_id', 'fa300000-0000-0000-0000-000000000002',
      'category', 'buts',
      'predicted_value_30', 0
    ),
    jsonb_build_object(
      'season_player_id', 'fa300000-0000-0000-0000-000000000003',
      'category', 'buts',
      'predicted_value_30', 0
    )
  )
);
reset role;

-- There is deliberately no explicit prediction lock. The two removed players
-- must disappear from the final archive snapshot before titles are computed.
update public.season_players
set is_active = false
where id in (
  'fa300000-0000-0000-0000-000000000002',
  'fa300000-0000-0000-0000-000000000003'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"fa100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.set_season_status(
    'fa200000-0000-0000-0000-000000000001',
    'archived'
  ),
  'archive without an explicit prediction lock succeeds'
);
reset role;

select is(
  (
    select capture_reason
    from public.season_prediction_roster_captures
    where season_id = 'fa200000-0000-0000-0000-000000000001'
  ),
  'archive'::text,
  'archive captures a final prediction roster before title calculation'
);

select is(
  (
    select count(*)
    from public.season_prediction_roster_members
    where season_id = 'fa200000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'only the player still active at archive belongs to the final snapshot'
);

select is(
  (
    select coalesce(sum(points), 0)
    from public.v_season_prediction_points
    where season_id = 'fa200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'fa100000-0000-0000-0000-000000000002'
  ),
  12::bigint,
  'A scores 12 points on the final one-player roster'
);

select is(
  (
    select coalesce(sum(points), 0)
    from public.v_season_prediction_points
    where season_id = 'fa200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'fa100000-0000-0000-0000-000000000003'
  ),
  3::bigint,
  'B scores 3 points on the final one-player roster'
);

select ok(
  exists (
    select 1
    from public.season_awards
    where season_id = 'fa200000-0000-0000-0000-000000000001'
      and profile_id = 'fa100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_player'
  ),
  'final Buteurs leader A receives best_pred_player'
);

select ok(
  not exists (
    select 1
    from public.season_awards
    where season_id = 'fa200000-0000-0000-0000-000000000001'
      and profile_id = 'fa100000-0000-0000-0000-000000000003'
      and award_type = 'best_pred_player'
  ),
  'removed-roster leader B does not keep best_pred_player'
);

select ok(
  exists (
    select 1
    from public.season_awards
    where season_id = 'fa200000-0000-0000-0000-000000000001'
      and profile_id = 'fa100000-0000-0000-0000-000000000002'
      and award_type = 'best_pred_overall'
  ),
  'final Global leader A receives best_pred_overall'
);

select ok(
  not exists (
    select 1
    from public.season_awards
    where season_id = 'fa200000-0000-0000-0000-000000000001'
      and profile_id = 'fa100000-0000-0000-0000-000000000003'
      and award_type = 'best_pred_overall'
  ),
  'removed-roster leader B does not keep best_pred_overall'
);

select * from finish();
rollback;
