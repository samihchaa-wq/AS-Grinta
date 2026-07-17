-- CI-only compatibility shim for historical prediction/statistics views.
--
-- 20260710110000_post_match_only_workflow.sql drops legacy live functions with
-- CASCADE. In the hosted project those operations did not leave the following
-- views absent, but replaying only the tracked files removes them before
-- 20260710140000_v1_public_readiness.sql references them. Recreate the exact
-- pre-time-tracking view shapes only in the disposable local migration chain.

create or replace view public.v_player_season_stats
with (security_invoker = true)
as
with appearances as (
  select m.season_id, mp.profile_id,
         count(distinct mp.match_id)::integer as matches_played
  from public.match_participants mp
  join public.matches m on m.id = mp.match_id
  where m.status in ('termine', 'archive')
  group by m.season_id, mp.profile_id
), goal_stats as (
  select m.season_id, g.scorer_profile_id as profile_id,
         count(*) filter (
           where g.team = 'as_grinta' and g.scorer_profile_id is not null
         )::integer as goals
  from public.goals g
  join public.matches m on m.id = g.match_id
  where m.status in ('termine', 'archive')
  group by m.season_id, g.scorer_profile_id
), assist_stats as (
  select m.season_id, g.assist_profile_id as profile_id,
         count(*) filter (
           where g.team = 'as_grinta' and g.assist_profile_id is not null
         )::integer as assists
  from public.goals g
  join public.matches m on m.id = g.match_id
  where m.status in ('termine', 'archive')
  group by m.season_id, g.assist_profile_id
), motm_stats as (
  select m.season_id, mm.profile_id, count(*)::integer as motm
  from public.match_motm mm
  join public.matches m on m.id = mm.match_id
  group by m.season_id, mm.profile_id
), clean_sheet_stats as (
  select m.season_id, mp.profile_id,
         count(*) filter (where m.score_adverse = 0)::integer as clean_sheets
  from public.match_participants mp
  join public.matches m on m.id = mp.match_id
  join public.season_players sp
    on sp.season_id = m.season_id
   and sp.profile_id = mp.profile_id
   and sp.is_goalkeeper_snapshot
  where m.status in ('termine', 'archive')
  group by m.season_id, mp.profile_id
)
select sp.season_id, sp.profile_id,
       coalesce(a.matches_played, 0) as matches_played,
       coalesce(g.goals, 0) as goals,
       coalesce(ast.assists, 0) as assists,
       coalesce(mm.motm, 0) as motm,
       coalesce(cs.clean_sheets, 0) as clean_sheets
from public.season_players sp
left join appearances a using (season_id, profile_id)
left join goal_stats g using (season_id, profile_id)
left join assist_stats ast using (season_id, profile_id)
left join motm_stats mm using (season_id, profile_id)
left join clean_sheet_stats cs using (season_id, profile_id);

create or replace view public.v_player_career_stats
with (security_invoker = true)
as
select profile_id,
       sum(matches_played)::integer as matches_played,
       sum(goals)::integer as goals,
       sum(assists)::integer as assists,
       sum(motm)::integer as motm,
       sum(clean_sheets)::integer as clean_sheets
from public.v_player_season_stats
group by profile_id;

create or replace view public.v_season_prediction_points
with (security_invoker = true)
as
select sp.id, sp.season_id, sp.predictor_profile_id, sp.player_profile_id,
       sp.category,
       case
         when not sp.is_filled then 0
         when stats.matches_played = 0 then 0
         when s.status = 'archived' and stats.matches_played < 3 then 0
         else round(
           greatest(
             0,
             1 - abs(
               case sp.category
                 when 'buts' then stats.goals
                 when 'passes' then stats.assists
                 when 'hommes_du_match' then stats.motm
                 when 'clean_sheets' then stats.clean_sheets
                 else 0
               end
               - (sp.predicted_value_20 * stats.matches_played / 20.0)
             ) / greatest(sp.predicted_value_20 * stats.matches_played / 20.0, 1)
           ) * 20
         )::integer
       end as points
from public.season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id = sp.season_id
 and stats.profile_id = sp.player_profile_id
join public.seasons s on s.id = sp.season_id;

grant select on public.v_player_season_stats to authenticated;
grant select on public.v_player_career_stats to authenticated;
grant select on public.v_season_prediction_points to authenticated;
