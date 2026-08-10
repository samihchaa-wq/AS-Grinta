begin;

create or replace function public.seed_match_predictions()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  insert into public.match_predictions(
    match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
  )
  select new.id,id,0,0,false
  from public.profiles
  where status='active'
  on conflict(match_id,profile_id) do nothing;
  return new;
end;
$$;

create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  if new.status<>'active' then return new; end if;

  insert into public.match_predictions(
    match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
  )
  select id,new.id,0,0,false
  from public.matches
  where status='a_venir'
  on conflict(match_id,profile_id) do nothing;

  insert into public.season_predictions(
    season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
  )
  select sp.season_id,new.id,sp.profile_id,c.category,0,false
  from public.season_players sp
  join public.seasons s on s.id=sp.season_id and s.status='open'
  cross join lateral unnest(
    case when sp.is_goalkeeper_snapshot
      then array['clean_sheets','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;
  return new;
end;
$$;

create or replace function public.seed_season_predictions_for_player()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  insert into public.season_predictions(
    season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
  )
  select new.season_id,p.id,new.profile_id,c.category,0,false
  from public.profiles p
  cross join lateral unnest(
    case when new.is_goalkeeper_snapshot
      then array['clean_sheets','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  where p.status='active'
  on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;
  return new;
end;
$$;

insert into public.match_predictions(
  match_id,profile_id,predicted_score_as_grinta,predicted_score_adverse,is_filled
)
select m.id,p.id,0,0,false
from public.matches m
cross join public.profiles p
where m.status='a_venir' and p.status='active'
on conflict(match_id,profile_id) do nothing;

insert into public.season_predictions(
  season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
)
select sp.season_id,p.id,sp.profile_id,c.category,0,false
from public.season_players sp
join public.seasons s on s.id=sp.season_id and s.status='open'
cross join public.profiles p
cross join lateral unnest(
  case when sp.is_goalkeeper_snapshot
    then array['clean_sheets','penalty_faults']::text[]
    else array['buts','passes','hommes_du_match','penalty_faults']::text[]
  end
) c(category)
where p.status='active'
on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;

create or replace view public.v_classement_general
with (security_invoker=true)
as
with mt as (
  select profile_id,coalesce(sum(points),0::numeric) as match_points
  from public.v_match_prediction_points
  group by profile_id
), st as (
  select predictor_profile_id as profile_id,
         coalesce(sum(points),0::bigint)::numeric as season_points
  from public.v_season_prediction_points
  group by predictor_profile_id
), match_max as (
  select coalesce(sum(
    case
      when m.score_as_grinta>m.score_adverse then mo.odds_victoire_as_grinta
      when m.score_as_grinta=m.score_adverse then mo.odds_nul
      else mo.odds_victoire_adverse
    end * 15::numeric
  ),0::numeric) as max_points
  from public.matches m
  join public.match_odds mo on mo.match_id=m.id
  where m.status in ('termine','archive')
    and m.score_as_grinta is not null
    and m.score_adverse is not null
), season_expected as (
  select sp.predictor_profile_id as profile_id,count(*)::numeric*20::numeric as max_points
  from public.season_predictions sp
  join public.seasons s on s.id=sp.season_id
  left join public.v_player_season_stats stats
    on stats.season_id=sp.season_id and stats.profile_id=sp.player_profile_id
  where not (s.status='archived' and coalesce(stats.matches_played,0)<3)
  group by sp.predictor_profile_id
)
select p.id as profile_id,p.first_name,p.last_name,
       coalesce(mt.match_points,0::numeric) as match_points,
       coalesce(st.season_points,0::numeric) as season_points,
       coalesce(mt.match_points,0::numeric)+coalesce(st.season_points,0::numeric) as total_points,
       mm.max_points as match_max_points,
       coalesce(se.max_points,0::numeric) as season_max_points,
       case when mm.max_points>0 then round(100*coalesce(mt.match_points,0)/mm.max_points,2) else 0 end as match_percentage,
       case when coalesce(se.max_points,0)>0 then round(100*coalesce(st.season_points,0)/se.max_points,2) else 0 end as season_percentage,
       p.surnom
from public.profiles p
cross join match_max mm
left join mt on mt.profile_id=p.id
left join st on st.profile_id=p.id
left join season_expected se on se.profile_id=p.id
where p.status='active';

commit;
