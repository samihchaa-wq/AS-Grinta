drop policy if exists match_predictions_owner_update_window
on public.match_predictions;
create policy match_predictions_owner_update_window
on public.match_predictions
for update to authenticated
using (profile_id=(select auth.uid()))
with check (
  profile_id=(select auth.uid())
  and exists (
    select 1
    from public.matches m
    where m.id=match_id
      and m.status='a_venir'
      and now() >= ((m.match_date+m.match_time) at time zone 'Europe/Paris')-interval '6 days'
      and now() < ((m.match_date+m.match_time) at time zone 'Europe/Paris')-interval '12 hours'
  )
);

create or replace view public.v_season_prediction_points
with (security_invoker=true)
as
select
  sp.id,
  sp.season_id,
  sp.predictor_profile_id,
  sp.player_profile_id,
  sp.category,
  round(
    greatest(
      0,
      1-abs(
        case sp.category
          when 'buts' then stats.goals
          when 'passes' then stats.assists
          when 'hommes_du_match' then stats.motm
          when 'clean_sheets' then stats.clean_sheets
          else 0
        end-(sp.predicted_value_20*stats.matches_played/20.0)
      )/greatest(sp.predicted_value_20*stats.matches_played/20.0,1)
    )*20
  )::integer as points
from public.season_predictions sp
join public.v_player_season_stats stats
  on stats.season_id=sp.season_id
 and stats.profile_id=sp.player_profile_id
join public.seasons s on s.id=sp.season_id
where sp.is_filled
  and stats.matches_played>0
  and not (s.status='archived' and stats.matches_played<3);

create or replace view public.v_classement_general
with (security_invoker=true)
as
with mt as(
  select profile_id,coalesce(sum(points),0)::numeric match_points
  from public.v_match_prediction_points
  group by profile_id
), st as(
  select predictor_profile_id profile_id,
         coalesce(sum(points),0)::numeric season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
), match_max as(
  select coalesce(sum(
    case
      when m.score_as_grinta>m.score_adverse then mo.odds_victoire_as_grinta
      when m.score_as_grinta=m.score_adverse then mo.odds_nul
      else mo.odds_victoire_adverse
    end*15
  ),0)::numeric max_points
  from public.matches m
  join public.match_odds mo on mo.match_id=m.id
  where m.status in('termine','archive')
    and m.score_as_grinta is not null
    and m.score_adverse is not null
), season_expected as(
  select predictor_profile_id profile_id,count(*)::numeric*20 max_points
  from public.season_predictions sp
  join public.seasons s on s.id=sp.season_id
  left join public.v_player_season_stats stats
    on stats.season_id=sp.season_id
   and stats.profile_id=sp.player_profile_id
  where not (s.status='archived' and coalesce(stats.matches_played,0)<3)
  group by predictor_profile_id
)
select
  p.id profile_id,
  p.first_name,
  p.last_name,
  coalesce(mt.match_points,0) match_points,
  coalesce(st.season_points,0) season_points,
  coalesce(mt.match_points,0)+coalesce(st.season_points,0) total_points,
  mm.max_points match_max_points,
  coalesce(se.max_points,0) season_max_points,
  case
    when mm.max_points>0
      then round(100*coalesce(mt.match_points,0)/mm.max_points,2)
    else 0
  end match_percentage,
  case
    when coalesce(se.max_points,0)>0
      then round(100*coalesce(st.season_points,0)/se.max_points,2)
    else 0
  end season_percentage
from public.profiles p
cross join match_max mm
left join mt on mt.profile_id=p.id
left join st on st.profile_id=p.id
left join season_expected se on se.profile_id=p.id
where p.status='active';

grant select on public.v_season_prediction_points to authenticated;
grant select on public.v_classement_general to authenticated;
