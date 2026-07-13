-- Classement saison : état des lieux actuel uniquement.
--
-- Les points ne sont plus calculés à partir d'une projection sur 30 matchs.
-- Chaque pronostic est comparé au nombre de buts / clean sheets réellement
-- enregistré au moment où le classement est consulté.

create or replace view public.v_season_prediction_points
with (security_invoker = true) as
with base as (
  select
    sp.id,
    sp.season_id,
    sp.predictor_profile_id,
    sp.season_player_id,
    sp.category,
    sp.predicted_value_30,
    case sp.category
      when 'buts' then st.goals
      when 'clean_sheets' then st.clean_sheets
      else 0
    end::numeric as target
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  where sp.is_filled
    and sp.category in ('buts', 'clean_sheets')
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
)
select
  id,
  season_id,
  predictor_profile_id,
  season_player_id,
  category,
  (
    count(*) over (
      partition by season_id, season_player_id, category
    )
    - (
      rank() over (
        partition by season_id, season_player_id, category
        order by abs(predicted_value_30::numeric - target)
      ) - 1
    )
  )::integer
  * case when predicted_value_30::numeric = target then 2 else 1 end
  as points
from base;

create or replace view public.v_season_prediction_flags
with (security_invoker = true) as
with base as (
  select
    sp.season_id,
    sp.predictor_profile_id,
    sp.season_player_id,
    sp.category,
    sp.predicted_value_30,
    case sp.category
      when 'buts' then st.goals
      when 'clean_sheets' then st.clean_sheets
      else 0
    end::numeric as target
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  where sp.is_filled
    and sp.category in ('buts', 'clean_sheets')
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
), ranked as (
  select
    base.*,
    rank() over (
      partition by season_id, season_player_id, category
      order by abs(predicted_value_30::numeric - target)
    ) as closeness_rank
  from base
)
select
  season_id,
  predictor_profile_id,
  (closeness_rank = 1)::int as bon_pari,
  (predicted_value_30::numeric = target)::int as exact
from ranked;

create or replace view public.v_season_prediction_bonus
with (security_invoker = true) as
with current_goals as (
  select distinct
    sp.season_id,
    sp.season_player_id,
    st.goals::numeric as target
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_player_id = sp.season_player_id
  where sp.category = 'buts'
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
), actual_rank as (
  select
    season_id,
    season_player_id,
    rank() over (
      partition by season_id
      order by target desc
    ) as actual_rank
  from current_goals
), pred_rank as (
  select
    sp.season_id,
    sp.predictor_profile_id,
    sp.season_player_id,
    rank() over (
      partition by sp.season_id, sp.predictor_profile_id
      order by sp.predicted_value_30 desc
    ) as pred_rank
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  where sp.category = 'buts'
    and sp.is_filled
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
)
select
  pr.season_id,
  pr.predictor_profile_id,
  sum(
    case
      when pr.pred_rank = ar.actual_rank then 2
      when ceil(least(pr.pred_rank, 15) / 5.0)
        = ceil(least(ar.actual_rank, 15) / 5.0) then 1
      else 0
    end
  )::int as bonus_points
from pred_rank pr
join actual_rank ar
  on ar.season_id = pr.season_id
  and ar.season_player_id = pr.season_player_id
group by pr.season_id, pr.predictor_profile_id;

grant select on public.v_season_prediction_points to anon, authenticated;
grant select on public.v_season_prediction_flags to anon, authenticated;
grant select on public.v_season_prediction_bonus to anon, authenticated;
