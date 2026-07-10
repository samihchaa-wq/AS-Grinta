begin;

create or replace function public.validate_season_prediction_category()
returns trigger
language plpgsql
set search_path='public'
as $$
declare goalkeeper boolean;
begin
  select is_goalkeeper_snapshot into goalkeeper
  from public.season_players
  where season_id=new.season_id and profile_id=new.player_profile_id;

  if goalkeeper is null then
    raise exception 'Player is not in the season squad';
  end if;

  if goalkeeper and new.category not in (
    'clean_sheets','hommes_du_match','penalty_faults'
  ) then
    raise exception 'Invalid goalkeeper prediction category';
  end if;

  if not goalkeeper and new.category not in (
    'buts','passes','hommes_du_match','penalty_faults'
  ) then
    raise exception 'Invalid outfield prediction category';
  end if;

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
      then array['clean_sheets','hommes_du_match','penalty_faults']::text[]
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
      then array['clean_sheets','hommes_du_match','penalty_faults']::text[]
      else array['buts','passes','hommes_du_match','penalty_faults']::text[]
    end
  ) c(category)
  where p.status='active'
  on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;
  return new;
end;
$$;

insert into public.season_predictions(
  season_id,predictor_profile_id,player_profile_id,category,predicted_value_20,is_filled
)
select sp.season_id,p.id,sp.profile_id,'hommes_du_match',0,false
from public.season_players sp
join public.seasons s on s.id=sp.season_id and s.status='open'
cross join public.profiles p
where sp.is_goalkeeper_snapshot=true
  and p.status='active'
on conflict(season_id,predictor_profile_id,player_profile_id,category) do nothing;

drop policy if exists matches_moderator_delete on public.matches;
drop policy if exists matches_staff_delete on public.matches;
create policy matches_staff_delete
on public.matches for delete to authenticated
using (public.is_match_staff());

commit;
