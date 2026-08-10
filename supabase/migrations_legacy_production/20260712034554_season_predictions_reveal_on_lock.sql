-- Les pronostics de saison des autres ne sont visibles (et scorés) qu'une
-- fois la saison verrouillée (season_predictions_locked_at renseigné) ou
-- archivée. Avant ça, chacun ne voit que les siens.

drop policy if exists authenticated_read_season_predictions on public.season_predictions;
create policy authenticated_read_season_predictions on public.season_predictions
  for select to authenticated
  using (
    predictor_profile_id = (select auth.uid())
    or exists (
      select 1 from public.seasons s
      where s.id = season_predictions.season_id
        and (s.season_predictions_locked_at is not null or s.status = 'archived')
    )
  );

-- Les points de saison ne comptent qu'après verrouillage (ou en fin de saison).
create or replace view public.v_season_prediction_points
with (security_invoker = true) as
with base as (
  select
    sp.id, sp.season_id, sp.predictor_profile_id, sp.player_profile_id,
    sp.category, sp.predicted_value_30,
    case sp.category
      when 'buts' then st.goals
      when 'clean_sheets' then st.clean_sheets
      else 0
    end as metric,
    s.status as season_status,
    (s.season_predictions_locked_at is not null) as locked,
    mc.matches_played
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_id = sp.season_id and st.profile_id = sp.player_profile_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.is_filled and sp.category in ('buts', 'clean_sheets')
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
),
targeted as (
  select *,
    case
      when season_status = 'archived' then metric::numeric
      when coalesce(matches_played, 0) > 0
        then round(metric::numeric * 30.0 / matches_played)
      else null
    end as target
  from base
)
select
  id, season_id, predictor_profile_id, player_profile_id, category,
  (count(*) over (
      partition by season_id, player_profile_id, category)
   - (rank() over (
      partition by season_id, player_profile_id, category
      order by abs(predicted_value_30 - target)) - 1))::int as points
from targeted
where target is not null;

create or replace view public.v_season_prediction_bonus
with (security_invoker = true) as
with target_goals as (
  select
    sp.season_id, sp.player_profile_id,
    case
      when s.status = 'archived' then st.goals::numeric
      when coalesce(mc.matches_played, 0) > 0
        then round(st.goals::numeric * 30.0 / mc.matches_played)
      else null
    end as target
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  join public.v_player_season_stats st
    on st.season_id = sp.season_id and st.profile_id = sp.player_profile_id
  left join public.v_season_match_count mc on mc.season_id = sp.season_id
  where sp.category = 'buts'
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
  group by sp.season_id, sp.player_profile_id, target
),
actual_rank as (
  select season_id, player_profile_id,
    rank() over (partition by season_id order by target desc) as actual_rank
  from target_goals
  where target is not null
),
pred_rank as (
  select sp.season_id, sp.predictor_profile_id, sp.player_profile_id,
    rank() over (
      partition by sp.season_id, sp.predictor_profile_id
      order by sp.predicted_value_30 desc) as pred_rank
  from public.season_predictions sp
  join public.seasons s on s.id = sp.season_id
  where sp.category = 'buts' and sp.is_filled
    and (s.season_predictions_locked_at is not null or s.status = 'archived')
)
select
  pr.season_id, pr.predictor_profile_id,
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
  and ar.player_profile_id = pr.player_profile_id
group by pr.season_id, pr.predictor_profile_id;;
