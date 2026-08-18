-- Keep every season-prediction ranking component on the roster contract frozen
-- at lock/archive time. v_season_prediction_points already uses this contract;
-- flags and the order bonus must use the same scope so later roster activity
-- changes cannot rewrite the leaderboard.

create or replace view public.v_season_prediction_flags
with (security_invoker = true)
as
with eligible_seasons as (
  select
    season.id,
    season.status,
    exists (
      select 1
      from public.season_prediction_roster_captures capture
      where capture.season_id = season.id
    ) as has_roster_snapshot
  from public.seasons season
  where season.season_predictions_locked_at is not null
     or season.status = 'archived'
),
prediction_roster as (
  select
    member.season_id,
    member.season_player_id,
    member.category
  from public.season_prediction_roster_members member
  join eligible_seasons season
    on season.id = member.season_id
   and season.has_roster_snapshot

  union all

  select
    player.season_id,
    player.id as season_player_id,
    case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
  from public.season_players player
  join eligible_seasons season
    on season.id = player.season_id
   and not season.has_roster_snapshot
),
expected_predictions as (
  select roster.season_id, count(*) as expected_count
  from prediction_roster roster
  group by roster.season_id
),
predictor_completion as (
  select
    prediction.season_id,
    prediction.predictor_profile_id,
    count(*) filter (where prediction.is_filled) as filled_count
  from public.season_predictions prediction
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  group by prediction.season_id, prediction.predictor_profile_id
),
eligible_predictors as (
  select completion.season_id, completion.predictor_profile_id
  from predictor_completion completion
  join expected_predictions expected
    on expected.season_id = completion.season_id
  where expected.expected_count > 0
    and completion.filled_count = expected.expected_count
),
base as (
  select
    prediction.season_id,
    prediction.predictor_profile_id,
    prediction.season_player_id,
    prediction.category,
    prediction.predicted_value_30,
    case prediction.category
      when 'buts' then stats.goals
      when 'clean_sheets' then stats.clean_sheets
      else 0
    end as metric,
    season.status as season_status,
    match_count.matches_played
  from public.season_predictions prediction
  join eligible_predictors eligible
    on eligible.season_id = prediction.season_id
   and eligible.predictor_profile_id = prediction.predictor_profile_id
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  join eligible_seasons season
    on season.id = prediction.season_id
  join public.v_player_season_stats stats
    on stats.season_player_id = prediction.season_player_id
  left join public.v_season_match_count match_count
    on match_count.season_id = prediction.season_id
  where prediction.is_filled
),
targeted as (
  select
    base.*,
    case
      when base.season_status = 'archived' then base.metric::numeric
      when coalesce(base.matches_played, 0) > 0
        then round(base.metric::numeric * 30.0 / base.matches_played::numeric)
      else null::numeric
    end as target
  from base
),
ranked as (
  select
    targeted.*,
    rank() over (
      partition by targeted.season_id,
                   targeted.season_player_id,
                   targeted.category
      order by abs(targeted.predicted_value_30::numeric - targeted.target)
    ) as proximity_rank
  from targeted
  where targeted.target is not null
)
select
  season_id,
  predictor_profile_id,
  (proximity_rank = 1)::integer as bon_pari,
  (predicted_value_30::numeric = target)::integer as exact
from ranked;

revoke all privileges on table public.v_season_prediction_flags from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_flags from authenticated;
grant select on table public.v_season_prediction_flags to authenticated;

create or replace view public.v_season_prediction_bonus
with (security_invoker = true)
as
with eligible_seasons as (
  select
    season.id,
    exists (
      select 1
      from public.season_prediction_roster_captures capture
      where capture.season_id = season.id
    ) as has_roster_snapshot
  from public.seasons season
  where season.season_predictions_locked_at is not null
     or season.status = 'archived'
),
prediction_roster as (
  select
    member.season_id,
    member.season_player_id,
    member.category
  from public.season_prediction_roster_members member
  join eligible_seasons season
    on season.id = member.season_id
   and season.has_roster_snapshot

  union all

  select
    player.season_id,
    player.id as season_player_id,
    case when player.is_goalkeeper then 'clean_sheets' else 'buts' end
  from public.season_players player
  join eligible_seasons season
    on season.id = player.season_id
   and not season.has_roster_snapshot
),
expected_predictions as (
  select roster.season_id, count(*) as expected_count
  from prediction_roster roster
  group by roster.season_id
),
predictor_completion as (
  select
    prediction.season_id,
    prediction.predictor_profile_id,
    count(*) filter (where prediction.is_filled) as filled_count
  from public.season_predictions prediction
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  group by prediction.season_id, prediction.predictor_profile_id
),
eligible_predictors as (
  select completion.season_id, completion.predictor_profile_id
  from predictor_completion completion
  join expected_predictions expected
    on expected.season_id = completion.season_id
  where expected.expected_count > 0
    and completion.filled_count = expected.expected_count
),
participant_count as (
  select season_id, count(*)::integer as participant_count
  from eligible_predictors
  group by season_id
),
target_goals as (
  select
    roster.season_id,
    roster.season_player_id,
    stats.goals::numeric as target
  from prediction_roster roster
  join public.v_player_season_stats stats
    on stats.season_player_id = roster.season_player_id
  where roster.category = 'buts'
),
goal_predictions as (
  select
    prediction.season_id,
    prediction.predictor_profile_id,
    prediction.season_player_id,
    prediction.predicted_value_30
  from public.season_predictions prediction
  join eligible_predictors eligible
    on eligible.season_id = prediction.season_id
   and eligible.predictor_profile_id = prediction.predictor_profile_id
  join prediction_roster roster
    on roster.season_id = prediction.season_id
   and roster.season_player_id = prediction.season_player_id
   and roster.category = prediction.category
  where prediction.category = 'buts'
    and prediction.is_filled
),
pair_scores as (
  select
    a.season_id,
    a.predictor_profile_id,
    count(*)::integer as total_pairs,
    count(*) filter (
      where sign((a.predicted_value_30 - b.predicted_value_30)::double precision)
          = sign(ta.target - tb.target)::double precision
    )::integer as correct_pairs
  from goal_predictions a
  join goal_predictions b
    on b.season_id = a.season_id
   and b.predictor_profile_id = a.predictor_profile_id
   and a.season_player_id < b.season_player_id
  join target_goals ta
    on ta.season_id = a.season_id
   and ta.season_player_id = a.season_player_id
  join target_goals tb
    on tb.season_id = b.season_id
   and tb.season_player_id = b.season_player_id
  where ta.target is not null
    and tb.target is not null
  group by a.season_id, a.predictor_profile_id
)
select
  scores.season_id,
  scores.predictor_profile_id,
  case
    when scores.total_pairs = 0
      or scores.correct_pairs * 2 <= scores.total_pairs then 0
    else least(
      participants.participant_count * 30,
      round(
        participants.participant_count::numeric
        * 30.0
        * (2 * scores.correct_pairs - scores.total_pairs)::numeric
        / scores.total_pairs::numeric
      )::integer
    )
  end as bonus_points
from pair_scores scores
join participant_count participants
  on participants.season_id = scores.season_id;

revoke all privileges on table public.v_season_prediction_bonus from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.v_season_prediction_bonus from authenticated;
grant select on table public.v_season_prediction_bonus to authenticated;
