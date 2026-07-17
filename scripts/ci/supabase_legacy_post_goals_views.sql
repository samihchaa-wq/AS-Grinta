-- CI-only compatibility shim after the historical removal of public.goals.
-- The tracked migration drops public.goals CASCADE, which removes statistics
-- views that a later tracked scoring migration expects. Rebuild the historical
-- contracts from match_player_stats only in the disposable local runner.

create or replace view public.v_player_season_stats
with (security_invoker = true) as
select
  sp.season_id,
  sp.profile_id,
  coalesce(count(distinct mps.match_id) filter (
    where m.status in ('termine','archive') and coalesce(mps.present,true)
  ),0)::integer as matches_played,
  coalesce(sum(mps.goals) filter (where m.status in ('termine','archive')),0)::integer as goals,
  coalesce(sum(mps.assists) filter (where m.status in ('termine','archive')),0)::integer as assists,
  coalesce((select count(*) from public.match_motm mm join public.matches mx on mx.id=mm.match_id where mx.season_id=sp.season_id and mm.profile_id=sp.profile_id),0)::integer as motm,
  coalesce(count(*) filter (where m.status in ('termine','archive') and mps.clean_sheet),0)::integer as clean_sheets,
  coalesce(sum(mps.penalty_faults) filter (where m.status in ('termine','archive')),0)::integer as penalty_faults
from public.season_players sp
left join public.match_player_stats mps on mps.profile_id=sp.profile_id
left join public.matches m on m.id=mps.match_id and m.season_id=sp.season_id
group by sp.season_id, sp.profile_id;

create or replace view public.v_player_career_stats
with (security_invoker = true) as
select profile_id,
       sum(matches_played)::integer as matches_played,
       sum(goals)::integer as goals,
       sum(assists)::integer as assists,
       sum(motm)::integer as motm,
       sum(clean_sheets)::integer as clean_sheets,
       sum(penalty_faults)::integer as penalty_faults
from public.v_player_season_stats group by profile_id;

create or replace view public.v_season_prediction_points
with (security_invoker = true) as
select sp.id, sp.season_id, sp.predictor_profile_id, sp.player_profile_id,
       sp.category,
       case
         when not sp.is_filled then 0
         when stats.matches_played = 0 then 0
         when s.status = 'archived' and stats.matches_played < 3 then 0
         else round(greatest(0, 1 - abs(
           case sp.category
             when 'buts' then stats.goals
             when 'passes' then stats.assists
             when 'hommes_du_match' then stats.motm
             when 'clean_sheets' then stats.clean_sheets
             when 'penalty_faults' then stats.penalty_faults
             else 0 end
           - (sp.predicted_value_20 * stats.matches_played / 20.0)
         ) / greatest(sp.predicted_value_20 * stats.matches_played / 20.0, 1)) * 20)::integer
       end as points
from public.season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id=sp.season_id and stats.profile_id=sp.player_profile_id
join public.seasons s on s.id=sp.season_id;

grant select on public.v_player_season_stats to authenticated;
grant select on public.v_player_career_stats to authenticated;
grant select on public.v_season_prediction_points to authenticated;
