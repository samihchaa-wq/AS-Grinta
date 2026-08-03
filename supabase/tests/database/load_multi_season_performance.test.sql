begin;

set local search_path = public, extensions, pg_catalog;
set local statement_timeout = '8s';
select no_plan();

-- Jeu de charge déterministe : 8 saisons, 60 comptes et 480 matchs.
-- Les écritures sont directes et les triggers sont désactivés uniquement dans
-- cette transaction de test afin de mesurer les lectures métier, pas le coût
-- des workflows de création.
set local session_replication_role = replica;

create temporary table load_profiles (
  player_index integer primary key,
  profile_id uuid not null unique
) on commit drop;

insert into load_profiles(player_index, profile_id)
select player_index, extensions.gen_random_uuid()
from generate_series(1, 60) as player_index;

insert into auth.users(id, email, raw_user_meta_data)
select
  profile_id,
  format('load-player-%s@example.invalid', player_index),
  jsonb_build_object(
    'first_name', format('LoadPlayer %s', player_index),
    'last_name', 'Tester'
  )
from load_profiles;

insert into public.profiles(
  id,
  first_name,
  last_name,
  email,
  role,
  is_goalkeeper,
  status,
  surnom,
  username
)
select
  profile_id,
  format('LoadPlayer %s', player_index),
  'Tester',
  format('load-player-%s@example.invalid', player_index),
  case when player_index = 1 then 'admin' else 'pronostiqueur' end,
  player_index <= 6,
  'active',
  format('LP%s', player_index),
  format('load_player_%s', player_index)
from load_profiles;

create temporary table load_seasons (
  season_index integer primary key,
  season_id uuid not null unique,
  season_name text not null,
  season_status text not null
) on commit drop;

insert into load_seasons(season_index, season_id, season_name, season_status)
select
  season_index,
  extensions.gen_random_uuid(),
  format('%s-%s', 2019 + season_index, 2020 + season_index),
  case when season_index = 8 then 'open' else 'archived' end
from generate_series(1, 8) as season_index;

insert into public.seasons(id, name, status, created_at)
select
  season_id,
  season_name,
  season_status,
  timestamptz '2020-07-01 00:00:00+00'
    + ((season_index - 1) * interval '1 year')
from load_seasons;

create temporary table load_opponents (
  opponent_index integer primary key,
  opponent_id uuid not null unique
) on commit drop;

insert into load_opponents(opponent_index, opponent_id)
select opponent_index, extensions.gen_random_uuid()
from generate_series(1, 24) as opponent_index;

insert into public.opponents(id, name)
select opponent_id, format('Load Opponent %s', opponent_index)
from load_opponents;

create temporary table load_season_players (
  season_index integer not null,
  player_index integer not null,
  season_player_id uuid not null unique,
  primary key(season_index, player_index)
) on commit drop;

insert into load_season_players(season_index, player_index, season_player_id)
select
  season_index,
  player_index,
  extensions.gen_random_uuid()
from generate_series(1, 8) as season_index
cross join generate_series(1, 60) as player_index;

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
select
  lsp.season_player_id,
  ls.season_id,
  format('LoadPlayer %s', lsp.player_index),
  'Tester',
  lsp.player_index <= 6,
  true,
  lsp.player_index,
  lp.profile_id
from load_season_players lsp
join load_seasons ls using (season_index)
join load_profiles lp using (player_index);

create temporary table load_matches (
  season_index integer not null,
  match_index integer not null,
  match_id uuid not null unique,
  primary key(season_index, match_index)
) on commit drop;

insert into load_matches(season_index, match_index, match_id)
select
  season_index,
  match_index,
  extensions.gen_random_uuid()
from generate_series(1, 8) as season_index
cross join generate_series(1, 60) as match_index;

insert into public.matches(
  id,
  season_id,
  opponent_id,
  match_date,
  match_time,
  location,
  status,
  score_as_grinta,
  score_adverse,
  created_by,
  created_at,
  updated_at,
  result_validated_at,
  predictions_closed_at
)
select
  lm.match_id,
  ls.season_id,
  lo.opponent_id,
  date '2020-07-01' + ((lm.season_index - 1) * 70 + lm.match_index - 1),
  time '20:00:00',
  case when lm.match_index % 2 = 0 then 'domicile' else 'exterieur' end,
  case when lm.season_index = 8 then 'termine' else 'archive' end,
  (lm.match_index + lm.season_index) % 5,
  (lm.match_index * 2 + lm.season_index) % 4,
  admin_profile.profile_id,
  now() - ((480 - ((lm.season_index - 1) * 60 + lm.match_index)) * interval '1 day'),
  now(),
  now(),
  now()
from load_matches lm
join load_seasons ls using (season_index)
join load_opponents lo
  on lo.opponent_index = ((lm.match_index - 1) % 24) + 1
cross join lateral (
  select profile_id from load_profiles where player_index = 1
) admin_profile;

insert into public.match_odds(
  match_id,
  odds_victoire_as_grinta,
  odds_nul,
  odds_victoire_adverse,
  probability_win,
  probability_draw,
  probability_loss,
  expected_goals_as_grinta,
  expected_goals_adverse,
  confidence,
  model_version
)
select
  match_id,
  1.8 + ((match_index % 5)::numeric / 10),
  3.0 + ((match_index % 4)::numeric / 10),
  2.4 + ((match_index % 6)::numeric / 10),
  0.45,
  0.25,
  0.30,
  1.8,
  1.2,
  0.8,
  'load-v1'
from load_matches;

insert into public.match_predictions(
  match_id,
  profile_id,
  predicted_score_as_grinta,
  predicted_score_adverse,
  is_filled,
  created_at,
  updated_at
)
select
  lm.match_id,
  lp.profile_id,
  (lm.match_index + lp.player_index) % 5,
  (lm.match_index * 2 + lp.player_index) % 4,
  true,
  now(),
  now()
from load_matches lm
cross join load_profiles lp;

insert into public.match_attendance(match_id, season_player_id)
select
  lm.match_id,
  lsp.season_player_id
from load_matches lm
cross join generate_series(1, 20) as present_slot
join load_season_players lsp
  on lsp.season_index = lm.season_index
 and lsp.player_index = ((lm.match_index + present_slot - 2) % 60) + 1;

insert into public.match_player_stats(
  match_id,
  season_player_id,
  goals,
  clean_sheet,
  created_at,
  updated_at
)
select
  lm.match_id,
  lsp.season_player_id,
  case when stat_slot = 1 then m.score_as_grinta else 0 end,
  stat_slot = 5 and m.score_adverse = 0,
  now(),
  now()
from load_matches lm
join public.matches m on m.id = lm.match_id
cross join generate_series(1, 5) as stat_slot
join load_season_players lsp
  on lsp.season_index = lm.season_index
 and lsp.player_index = ((lm.match_index + stat_slot - 2) % 60) + 1;

insert into public.match_man_of_match(match_id, season_player_id)
select
  lm.match_id,
  lsp.season_player_id
from load_matches lm
join load_season_players lsp
  on lsp.season_index = lm.season_index
 and lsp.player_index = ((lm.match_index * 3 - 1) % 60) + 1;

insert into public.season_predictions(
  season_id,
  predictor_profile_id,
  season_player_id,
  category,
  predicted_value_30,
  is_filled,
  created_at,
  updated_at
)
select
  ls.season_id,
  lp.profile_id,
  lsp.season_player_id,
  category,
  (lp.player_index + target_player_index + ls.season_index) % 31,
  true,
  now(),
  now()
from load_seasons ls
cross join load_profiles lp
cross join generate_series(1, 5) as target_player_index
cross join (values ('buts'::text), ('clean_sheets'::text)) categories(category)
join load_season_players lsp
  on lsp.season_index = ls.season_index
 and lsp.player_index = target_player_index;

insert into public.historical_player_statistics(
  scope,
  season_name,
  display_rank,
  player_name,
  is_goalkeeper,
  matches_played,
  wins,
  draws,
  losses,
  goals,
  hdm,
  clean_sheets,
  source_label,
  profile_id
)
select
  'all_time',
  null,
  player_index,
  format('LoadPlayer %s Tester', player_index),
  player_index <= 6,
  120 + player_index,
  70,
  20,
  30 + player_index,
  case when player_index <= 6 then 0 else 20 + player_index end,
  player_index % 15,
  case when player_index <= 6 then 15 + player_index else 0 end,
  'load_fixture',
  profile_id
from load_profiles;

insert into public.profile_badges(
  profile_id,
  badge_id,
  source,
  awarded_at,
  featured
)
select
  lp.profile_id,
  extensions.gen_random_uuid(),
  'load_fixture',
  now() - (badge_index * interval '1 day'),
  badge_index <= 2
from load_profiles lp
cross join generate_series(1, 12) as badge_index;

set local session_replication_role = origin;

analyze public.profiles;
analyze public.seasons;
analyze public.opponents;
analyze public.season_players;
analyze public.matches;
analyze public.match_odds;
analyze public.match_predictions;
analyze public.season_predictions;
analyze public.match_attendance;
analyze public.match_player_stats;
analyze public.match_man_of_match;
analyze public.historical_player_statistics;
analyze public.profile_badges;

select is((select count(*) from public.seasons), 8::bigint,
  'le scénario contient huit saisons');
select is((select count(*) from public.matches), 480::bigint,
  'le scénario contient plusieurs centaines de matchs');
select is((select count(*) from public.match_predictions), 28800::bigint,
  'le scénario contient 28 800 pronostics de match');
select is((select count(*) from public.season_predictions), 4800::bigint,
  'le scénario contient 4 800 pronostics de saison');
select is((select count(*) from public.match_attendance), 9600::bigint,
  'le scénario contient 9 600 lignes de présence');
select is((select count(*) from public.match_player_stats), 2400::bigint,
  'le scénario contient 2 400 lignes de statistiques joueur');
select is((select count(*) from public.profile_badges), 720::bigint,
  'le scénario contient 720 attributions de badges');

create temporary view load_recent_matches as
select
  m.id,
  m.match_date,
  m.status,
  m.score_as_grinta,
  m.score_adverse,
  o.name as opponent_name,
  mo.odds_victoire_as_grinta,
  mo.odds_nul,
  mo.odds_victoire_adverse
from public.matches m
join public.opponents o on o.id = m.opponent_id
left join public.match_odds mo on mo.match_id = m.id
order by m.match_date desc
limit 50;

create temporary view load_player_statistics as
select *
from public.v_statistics_players
where period_key in ('current', 'previous', 'all_time')
order by period_key, is_goalkeeper, display_rank, display_order;

create temporary view load_general_ranking as
with match_scores as (
  select
    mp.profile_id,
    sum(
      (
        case
          when not mp.is_filled then 0
          when mp.predicted_score_as_grinta = m.score_as_grinta
           and mp.predicted_score_adverse = m.score_adverse then 300
          when sign(mp.predicted_score_as_grinta - mp.predicted_score_adverse)
             = sign(m.score_as_grinta - m.score_adverse) then 100
          else 0
        end
      )
    )::bigint as match_points,
    count(*) filter (
      where mp.is_filled
        and sign(mp.predicted_score_as_grinta - mp.predicted_score_adverse)
          = sign(m.score_as_grinta - m.score_adverse)
    )::bigint as correct_results,
    count(*) filter (
      where mp.is_filled
        and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse
    )::bigint as exact_scores
  from public.match_predictions mp
  join public.matches m on m.id = mp.match_id
   and m.status in ('termine', 'archive')
  group by mp.profile_id
), actual_season_values as (
  select
    sp.season_id,
    sp.id as season_player_id,
    coalesce(sum(mps.goals), 0)::integer as goals,
    count(*) filter (where mps.clean_sheet)::integer as clean_sheets
  from public.season_players sp
  left join public.match_player_stats mps on mps.season_player_id = sp.id
  group by sp.season_id, sp.id
), season_scores as (
  select
    prediction.predictor_profile_id as profile_id,
    sum(
      case prediction.category
        when 'buts' then greatest(
          0,
          100 - abs(prediction.predicted_value_30 - actual.goals) * 10
        )
        else greatest(
          0,
          100 - abs(prediction.predicted_value_30 - actual.clean_sheets) * 10
        )
      end
    )::bigint as season_points
  from public.season_predictions prediction
  join actual_season_values actual
    on actual.season_id = prediction.season_id
   and actual.season_player_id = prediction.season_player_id
  where prediction.is_filled
  group by prediction.predictor_profile_id
)
select
  p.id as profile_id,
  p.surnom,
  coalesce(ms.match_points, 0) as match_points,
  coalesce(ss.season_points, 0) as season_points,
  coalesce(ms.match_points, 0) + coalesce(ss.season_points, 0) as total_points,
  coalesce(ms.correct_results, 0) as correct_results,
  coalesce(ms.exact_scores, 0) as exact_scores
from public.profiles p
left join match_scores ms on ms.profile_id = p.id
left join season_scores ss on ss.profile_id = p.id
where p.status = 'active'
order by total_points desc, p.id;

create temporary view load_badge_metrics as
with attendance as (
  select
    sp.profile_id,
    count(distinct ma.match_id)::bigint as matches_played
  from public.season_players sp
  join public.match_attendance ma on ma.season_player_id = sp.id
  where sp.profile_id is not null
  group by sp.profile_id
), player_stats as (
  select
    sp.profile_id,
    sum(mps.goals)::bigint as goals,
    max(mps.goals)::integer as max_match_goals,
    count(*) filter (where mps.goals = 2)::bigint as doubles,
    count(*) filter (where mps.clean_sheet)::bigint as clean_sheets
  from public.season_players sp
  join public.match_player_stats mps on mps.season_player_id = sp.id
  where sp.profile_id is not null
  group by sp.profile_id
), mvp as (
  select
    sp.profile_id,
    count(distinct mom.match_id)::bigint as mvp_count
  from public.season_players sp
  join public.match_man_of_match mom on mom.season_player_id = sp.id
  where sp.profile_id is not null
  group by sp.profile_id
), prediction_metrics as (
  select
    mp.profile_id,
    count(*) filter (
      where mp.is_filled
        and sign(mp.predicted_score_as_grinta - mp.predicted_score_adverse)
          = sign(m.score_as_grinta - m.score_adverse)
    )::bigint as good_results,
    count(*) filter (
      where mp.is_filled
        and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse
    )::bigint as exact_scores
  from public.match_predictions mp
  join public.matches m on m.id = mp.match_id
  group by mp.profile_id
), badge_counts as (
  select
    pb.profile_id,
    count(*)::bigint as badge_count,
    count(*) filter (where pb.featured)::bigint as featured_count
  from public.profile_badges pb
  group by pb.profile_id
)
select
  p.id as profile_id,
  coalesce(a.matches_played, 0) as matches_played,
  coalesce(ps.goals, 0) as goals,
  coalesce(ps.max_match_goals, 0) as max_match_goals,
  coalesce(ps.doubles, 0) as doubles,
  coalesce(ps.clean_sheets, 0) as clean_sheets,
  coalesce(mv.mvp_count, 0) as mvp_count,
  coalesce(pm.good_results, 0) as good_results,
  coalesce(pm.exact_scores, 0) as exact_scores,
  coalesce(bc.badge_count, 0) as badge_count,
  coalesce(bc.featured_count, 0) as featured_count
from public.profiles p
left join attendance a on a.profile_id = p.id
left join player_stats ps on ps.profile_id = p.id
left join mvp mv on mv.profile_id = p.id
left join prediction_metrics pm on pm.profile_id = p.id
left join badge_counts bc on bc.profile_id = p.id
where p.status = 'active'
order by p.id;

create temporary view load_season_prediction_summary as
with actual as (
  select
    sp.season_id,
    sp.id as season_player_id,
    coalesce(sum(mps.goals), 0)::integer as actual_goals,
    count(*) filter (where mps.clean_sheet)::integer as actual_clean_sheets
  from public.season_players sp
  left join public.match_player_stats mps on mps.season_player_id = sp.id
  group by sp.season_id, sp.id
)
select
  prediction.predictor_profile_id,
  count(*)::bigint as predictions,
  count(*) filter (
    where prediction.category = 'buts'
      and prediction.predicted_value_30 = actual.actual_goals
  )::bigint as exact_goal_predictions,
  count(*) filter (
    where prediction.category = 'clean_sheets'
      and prediction.predicted_value_30 = actual.actual_clean_sheets
  )::bigint as exact_clean_sheet_predictions,
  sum(
    case prediction.category
      when 'buts' then abs(prediction.predicted_value_30 - actual.actual_goals)
      else abs(prediction.predicted_value_30 - actual.actual_clean_sheets)
    end
  )::bigint as total_absolute_error
from public.season_predictions prediction
join actual
  on actual.season_id = prediction.season_id
 and actual.season_player_id = prediction.season_player_id
where prediction.is_filled
group by prediction.predictor_profile_id
order by prediction.predictor_profile_id;

create temporary table load_benchmark_results (
  query_name text not null,
  iteration integer not null,
  elapsed_ms numeric not null,
  rows_seen bigint not null
) on commit drop;

create or replace function pg_temp.run_load_benchmark(
  p_query_name text,
  p_sql text,
  p_iterations integer default 5
)
returns void
language plpgsql
as $function$
declare
  iteration_index integer;
  started_at timestamptz;
  elapsed numeric;
  result_rows bigint;
begin
  for iteration_index in 1..p_iterations loop
    started_at := clock_timestamp();
    execute 'select count(*)::bigint from (' || p_sql || ') benchmark_rows'
      into result_rows;
    elapsed := round(
      (extract(epoch from clock_timestamp() - started_at) * 1000)::numeric,
      3
    );
    insert into load_benchmark_results(
      query_name,
      iteration,
      elapsed_ms,
      rows_seen
    ) values (
      p_query_name,
      iteration_index,
      elapsed,
      result_rows
    );
  end loop;
end;
$function$;

select pg_temp.run_load_benchmark(
  'recent_matches',
  'select * from pg_temp.load_recent_matches'
);
select pg_temp.run_load_benchmark(
  'player_statistics',
  'select * from pg_temp.load_player_statistics'
);
select pg_temp.run_load_benchmark(
  'general_ranking',
  'select * from pg_temp.load_general_ranking'
);
select pg_temp.run_load_benchmark(
  'badge_metrics',
  'select * from pg_temp.load_badge_metrics'
);
select pg_temp.run_load_benchmark(
  'season_prediction_summary',
  'select * from pg_temp.load_season_prediction_summary'
);

select diag(format(
  'charge %s: lignes=%s, min=%s ms, moyenne=%s ms, max=%s ms',
  query_name,
  max(rows_seen),
  min(elapsed_ms),
  round(avg(elapsed_ms), 3),
  max(elapsed_ms)
))
from load_benchmark_results
group by query_name
order by query_name;

select ok(
  max(rows_seen) > 0,
  format('%s renvoie des données sous charge', query_name)
)
from load_benchmark_results
group by query_name
order by query_name;

select ok(
  max(elapsed_ms) < 5000,
  format(
    '%s reste sous 5 secondes (maximum mesuré : %s ms)',
    query_name,
    max(elapsed_ms)
  )
)
from load_benchmark_results
group by query_name
order by query_name;

select is(
  (
    select count(*)
    from public.v_statistics_players
    where period_key = 'current'
  ),
  60::bigint,
  'les statistiques de la saison courante conservent les 60 joueurs'
);

select is(
  (
    select count(*)
    from public.v_statistics_players
    where period_key = 'previous'
  ),
  60::bigint,
  'la saison précédente reste calculable sous charge'
);

select is(
  (
    select count(*)
    from public.v_statistics_players
    where period_key = 'all_time'
  ),
  60::bigint,
  'le cumul toutes saisons fusionne correctement les profils historiques et actifs'
);

select * from finish();
rollback;
