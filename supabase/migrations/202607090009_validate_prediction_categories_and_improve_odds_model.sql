create or replace function public.validate_season_prediction_category()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  goalkeeper boolean;
begin
  select is_goalkeeper_snapshot into goalkeeper
  from public.season_players
  where season_id = new.season_id
    and profile_id = new.player_profile_id;

  if goalkeeper is null then
    raise exception 'Player is not in the season squad';
  end if;
  if goalkeeper and new.category <> 'clean_sheets' then
    raise exception 'Goalkeepers only support clean_sheets predictions';
  end if;
  if not goalkeeper and new.category = 'clean_sheets' then
    raise exception 'Outfield players do not support clean_sheets predictions';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_season_prediction_category
on public.season_predictions;
create trigger trg_validate_season_prediction_category
before insert or update of season_id,player_profile_id,category
on public.season_predictions
for each row execute function public.validate_season_prediction_category();

revoke execute on function public.validate_season_prediction_category()
from public, anon, authenticated;

create index if not exists idx_goals_scorer_profile on public.goals(scorer_profile_id);
create index if not exists idx_goals_assist_profile on public.goals(assist_profile_id);
create index if not exists idx_live_positions_profile on public.live_positions(profile_id);
create index if not exists idx_live_sessions_controller_profile on public.live_sessions(controller_profile_id);
create index if not exists idx_match_motm_profile on public.match_motm(profile_id);
create index if not exists idx_match_motm_created_by on public.match_motm(created_by);
create index if not exists idx_match_participants_profile on public.match_participants(profile_id);
create index if not exists idx_matches_opponent on public.matches(opponent_id);
create index if not exists idx_matches_created_by on public.matches(created_by);
create index if not exists idx_season_players_profile on public.season_players(profile_id);
create index if not exists idx_season_predictions_predictor on public.season_predictions(predictor_profile_id);
create index if not exists idx_season_predictions_player on public.season_predictions(player_profile_id);
create index if not exists idx_substitutions_live_session on public.substitutions(live_session_id);
create index if not exists idx_substitutions_profile on public.substitutions(profile_id);

create or replace function public.compute_match_odds(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_opponent uuid;
  v_location text;
  g_for numeric;
  g_against numeric;
  s_for numeric;
  s_against numeric;
  s_weight numeric;
  shrink numeric;
  lambda_for numeric;
  lambda_against numeric;
  gap numeric;
  p_draw numeric;
  p_win_share numeric;
  p_win numeric;
  p_loss numeric;
begin
  select opponent_id, location
  into v_opponent, v_location
  from public.matches
  where id = p_match_id;

  if v_opponent is null then
    raise exception 'Match not found';
  end if;

  with ranked_seasons as (
    select id, row_number() over(order by name desc)-1 as age
    from public.seasons
  ), history as (
    select
      m.opponent_id,
      m.location,
      m.score_as_grinta::numeric as goals_for,
      m.score_adverse::numeric as goals_against,
      case rs.age
        when 0 then 0.40
        when 1 then 0.25
        when 2 then 0.18
        when 3 then 0.10
        else 0.07
      end as season_weight
    from public.matches m
    join ranked_seasons rs on rs.id=m.season_id
    where m.status in ('termine','archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(goals_for*season_weight*case when location=v_location then 1.20 else 0.80 end)
      / nullif(sum(season_weight*case when location=v_location then 1.20 else 0.80 end),0),1.5),
    coalesce(sum(goals_against*season_weight*case when location=v_location then 1.20 else 0.80 end)
      / nullif(sum(season_weight*case when location=v_location then 1.20 else 0.80 end),0),1.5)
  into g_for,g_against
  from history;

  with ranked_seasons as (
    select id, row_number() over(order by name desc)-1 as age
    from public.seasons
  ), specific as (
    select
      m.score_as_grinta::numeric as goals_for,
      m.score_adverse::numeric as goals_against,
      (case rs.age
        when 0 then 0.40
        when 1 then 0.25
        when 2 then 0.18
        when 3 then 0.10
        else 0.07
      end) * case when m.location=v_location then 1.35 else 0.65 end as weight
    from public.matches m
    join ranked_seasons rs on rs.id=m.season_id
    where m.status in ('termine','archive')
      and m.opponent_id=v_opponent
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(goals_for*weight)/nullif(sum(weight),0),g_for),
    coalesce(sum(goals_against*weight)/nullif(sum(weight),0),g_against),
    coalesce(sum(weight),0)
  into s_for,s_against,s_weight
  from specific;

  shrink := least(0.75, s_weight/(s_weight+2.5));
  lambda_for := g_for*(1-shrink)+s_for*shrink;
  lambda_against := g_against*(1-shrink)+s_against*shrink;
  gap := (lambda_for-lambda_against)/(lambda_for+lambda_against+0.001);

  p_draw := case
    when abs(gap)<0.15 then 0.30
    when abs(gap)<0.35 then 0.25
    when abs(gap)<0.55 then 0.21
    else 0.17
  end;
  p_draw := greatest(p_draw,0.155);
  p_win_share := 0.5+least(0.32,abs(gap)/2);
  p_win := case
    when gap>0 then (1-p_draw)*p_win_share
    else (1-p_draw)*(1-p_win_share)
  end;
  p_win := least(p_win,0.82);
  p_loss := 1-p_draw-p_win;

  insert into public.match_odds(
    match_id,odds_victoire_as_grinta,odds_nul,odds_victoire_adverse,computed_at
  ) values (
    p_match_id,
    round((1/(p_win*1.05))::numeric,2),
    round((1/(p_draw*1.05))::numeric,2),
    round((1/(p_loss*1.05))::numeric,2),
    now()
  )
  on conflict(match_id) do nothing;
end;
$$;

revoke execute on function public.compute_match_odds(uuid)
from public, anon, authenticated;
