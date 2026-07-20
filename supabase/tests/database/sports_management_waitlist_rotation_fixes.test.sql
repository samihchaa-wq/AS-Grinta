begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regprocedure('private.normalize_waitlisted_withdrawal()') is not null,
  'la normalisation des désistements de non-convoqués existe'
);
select is(
  (
    select count(*)::integer
    from pg_trigger trigger
    where trigger.tgrelid = 'public.match_sport_participants'::regclass
      and trigger.tgname = 'normalize_waitlisted_withdrawal_before_update'
      and not trigger.tgisinternal
  ),
  1,
  'le trigger de normalisation est installé une seule fois'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '81000000-0000-0000-0000-000000000001',
    'waitlist-fix-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Fix"}'::jsonb
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    'waitlist-fix-player@example.invalid',
    '{"first_name":"Player","last_name":"Fix"}'::jsonb
  );

update public.profiles
set role = case
      when id = '81000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('82000000-0000-0000-0000-000000000001', '2096-2097', 'open');

insert into public.opponents(id, name)
values ('83000000-0000-0000-0000-000000000001', 'Fairness FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values (
  '84000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  'Player', 'Fix', false, true, 1,
  '81000000-0000-0000-0000-000000000002'
);

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at,
  location, planned_duration_minutes, status, created_by
)
values
  (
    '85000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    time '20:00', now() + interval '3 days',
    'domicile', 90, 'a_venir',
    '81000000-0000-0000-0000-000000000001'
  ),
  (
    '85000000-0000-0000-0000-000000000002',
    '82000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000001',
    ((now() + interval '2 hours') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 hours') at time zone 'Europe/Paris')::time,
    now() + interval '2 hours',
    'exterieur', 90, 'a_venir',
    '81000000-0000-0000-0000-000000000001'
  );

insert into public.match_sport_workflows(
  match_id,
  availability_state,
  availability_opens_at,
  availability_opened_at,
  squad_size_limit,
  convocation_state,
  late_withdrawal_cutoff_at,
  created_by,
  updated_by
)
values
  (
    '85000000-0000-0000-0000-000000000001',
    'open', now() - interval '1 day', now() - interval '1 day',
    14, 'published', now() + interval '1 day',
    '81000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001'
  ),
  (
    '85000000-0000-0000-0000-000000000002',
    'open', now() - interval '1 day', now() - interval '1 day',
    14, 'published', now() - interval '1 minute',
    '81000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001'
  );

insert into public.match_sport_participants(
  id,
  match_id,
  season_player_id,
  availability_status,
  convocation_status,
  waitlist_turn_should_consume,
  waitlist_turn_state
)
values
  (
    '86000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    'available', 'not_convoked', true, 'pending'
  ),
  (
    '86000000-0000-0000-0000-000000000002',
    '85000000-0000-0000-0000-000000000002',
    '84000000-0000-0000-0000-000000000001',
    'available', 'not_convoked', true, 'pending'
  );

update public.match_sport_participants
set availability_status = 'absent',
    availability_comment_private = 'Indisponible'
where id = '86000000-0000-0000-0000-000000000001';

select ok(
  (
    select convocation_status = 'not_applicable'
      and waitlist_turn_state = 'waived'
      and not waitlist_turn_should_consume
    from public.match_sport_participants
    where id = '86000000-0000-0000-0000-000000000001'
  ),
  'avant la coupure, le non-convoqué devenu absent conserve son tour'
);

update public.match_sport_participants
set availability_status = 'absent',
    availability_comment_private = 'Indisponible tardivement'
where id = '86000000-0000-0000-0000-000000000002';

select ok(
  (
    select convocation_status = 'not_applicable'
      and waitlist_turn_state = 'pending'
      and waitlist_turn_should_consume
    from public.match_sport_participants
    where id = '86000000-0000-0000-0000-000000000002'
  ),
  'après la coupure, un tour déjà dû reste à consommer'
);

select * from finish();
rollback;
