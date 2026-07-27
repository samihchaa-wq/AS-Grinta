\set ON_ERROR_STOP on
\timing on

begin;

-- Jeu synthétique exclusivement local : 8 saisons, 25 joueurs par saison,
-- 500 matchs et 6 000 lignes de présence/statistiques. La transaction est
-- annulée à la fin et ne peut donc pas polluer un environnement partagé.
set local session_replication_role = replica;

insert into auth.users(id, email, raw_user_meta_data)
values (
  'f0000000-0000-0000-0000-000000000001',
  'load-admin@example.invalid',
  '{"first_name":"Load","last_name":"Admin"}'::jsonb
);

insert into public.profiles(
  id, first_name, last_name, email, role, status, is_goalkeeper
)
values (
  'f0000000-0000-0000-0000-000000000001',
  'Load', 'Admin', 'load-admin@example.invalid', 'admin', 'active', false
)
on conflict (id) do nothing;

insert into public.seasons(id, name, status, created_at)
select
  md5('load-season-' || season_number)::uuid,
  (2079 + season_number)::text || '-' || (2080 + season_number)::text,
  case when season_number = 8 then 'open' else 'archived' end,
  make_timestamptz(2079 + season_number, 7, 1, 0, 0, 0, 'UTC')
from generate_series(1, 8) season_number;

insert into public.opponents(id, name)
select md5('load-opponent-' || opponent_number)::uuid,
       'Adversaire charge ' || opponent_number
from generate_series(1, 50) opponent_number;

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position
)
select
  md5('load-player-' || season_number || '-' || player_number)::uuid,
  md5('load-season-' || season_number)::uuid,
  'Joueur ' || player_number,
  'Charge',
  player_number = 1,
  true,
  player_number
from generate_series(1, 8) season_number
cross join generate_series(1, 25) player_number;

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, score_as_grinta, score_adverse,
  created_by, result_validated_at, predictions_closed_at
)
select
  md5('load-match-' || match_number)::uuid,
  md5('load-season-' || least(8, ((match_number - 1) / 63) + 1))::uuid,
  md5('load-opponent-' || (((match_number - 1) % 50) + 1))::uuid,
  date '2080-01-01' + match_number,
  time '20:00',
  case when match_number % 2 = 0 then 'domicile' else 'exterieur' end,
  90,
  'archive',
  match_number % 6,
  (match_number + 2) % 5,
  'f0000000-0000-0000-0000-000000000001',
  now(),
  now()
from generate_series(1, 500) match_number;

insert into public.match_attendance(match_id, season_player_id, created_at)
select
  md5('load-match-' || match_number)::uuid,
  md5(
    'load-player-' || least(8, ((match_number - 1) / 63) + 1) || '-' || player_number
  )::uuid,
  now()
from generate_series(1, 500) match_number
cross join generate_series(1, 12) player_number;

insert into public.match_player_stats(
  id, match_id, season_player_id, goals, clean_sheet, created_at, updated_at
)
select
  md5('load-stat-' || match_number || '-' || player_number)::uuid,
  md5('load-match-' || match_number)::uuid,
  md5(
    'load-player-' || least(8, ((match_number - 1) / 63) + 1) || '-' || player_number
  )::uuid,
  case when player_number = 1 then 0 else (match_number + player_number) % 3 end,
  player_number = 1 and ((match_number + 2) % 5) = 0,
  now(),
  now()
from generate_series(1, 500) match_number
cross join generate_series(1, 12) player_number;

insert into public.match_man_of_match(match_id, season_player_id, created_at)
select
  md5('load-match-' || match_number)::uuid,
  md5(
    'load-player-' || least(8, ((match_number - 1) / 63) + 1) || '-' ||
    (((match_number - 1) % 11) + 2)
  )::uuid,
  now()
from generate_series(1, 500) match_number;

set local session_replication_role = origin;

analyze public.seasons;
analyze public.season_players;
analyze public.matches;
analyze public.match_attendance;
analyze public.match_player_stats;
analyze public.match_man_of_match;

select 'fixture' as section,
       (select count(*) from public.seasons where name like '208%') as seasons,
       (select count(*) from public.matches where id = md5('load-match-1')::uuid
          or created_by = 'f0000000-0000-0000-0000-000000000001') as matches,
       (select count(*) from public.match_attendance
          where match_id = md5('load-match-1')::uuid
             or match_id = md5('load-match-500')::uuid) as sampled_attendance;

explain (analyze, buffers, format text)
select *
from public.v_statistics_players
where period_key = 'previous'
order by is_goalkeeper, display_rank, display_order;

explain (analyze, buffers, format text)
select *
from public.v_statistics_players
where period_key = 'all_time'
order by is_goalkeeper, display_rank, display_order;

rollback;
