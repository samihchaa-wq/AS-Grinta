-- Rétablit le calcul automatique des cotes (modèle V2.1) comme suggestion à
-- la création d'un match : pondération des saisons 40/25/18/10/7 %, historique
-- spécifique à l'adversaire avec rétrécissement bayésien, bonus domicile /
-- extérieur, probabilité de nul liée à l'écart et marge bookmaker de 5 %.
-- L'admin reste libre d'ajuster les valeurs proposées avant enregistrement.
create or replace function public.preview_match_odds(
  p_opponent_id uuid,
  p_location text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
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
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide';
  end if;

  with ranked_seasons as (
    select id, row_number() over(order by name desc) - 1 as age
    from public.seasons
  ), history as (
    select
      m.score_as_grinta::numeric as goals_for,
      m.score_adverse::numeric as goals_against,
      case rs.age
        when 0 then 0.40
        when 1 then 0.25
        when 2 then 0.18
        when 3 then 0.10
        else 0.07
      end as season_weight,
      m.location
    from public.matches m
    join ranked_seasons rs on rs.id = m.season_id
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(goals_for * season_weight * case when location = p_location then 1.20 else 0.80 end)
      / nullif(sum(season_weight * case when location = p_location then 1.20 else 0.80 end), 0), 1.5),
    coalesce(sum(goals_against * season_weight * case when location = p_location then 1.20 else 0.80 end)
      / nullif(sum(season_weight * case when location = p_location then 1.20 else 0.80 end), 0), 1.5)
  into g_for, g_against
  from history;

  with ranked_seasons as (
    select id, row_number() over(order by name desc) - 1 as age
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
      end) * case when m.location = p_location then 1.35 else 0.65 end as weight
    from public.matches m
    join ranked_seasons rs on rs.id = m.season_id
    where m.status in ('termine', 'archive')
      and m.opponent_id = p_opponent_id
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(goals_for * weight) / nullif(sum(weight), 0), g_for),
    coalesce(sum(goals_against * weight) / nullif(sum(weight), 0), g_against),
    coalesce(sum(weight), 0)
  into s_for, s_against, s_weight
  from specific;

  shrink := least(0.75, s_weight / (s_weight + 2.5));
  lambda_for := g_for * (1 - shrink) + s_for * shrink;
  lambda_against := g_against * (1 - shrink) + s_against * shrink;
  gap := (lambda_for - lambda_against) / (lambda_for + lambda_against + 0.001);

  p_draw := case
    when abs(gap) < 0.15 then 0.30
    when abs(gap) < 0.35 then 0.25
    when abs(gap) < 0.55 then 0.21
    else 0.17
  end;
  p_draw := greatest(p_draw, 0.155);
  p_win_share := 0.5 + least(0.32, abs(gap) / 2);
  p_win := case
    when gap > 0 then (1 - p_draw) * p_win_share
    else (1 - p_draw) * (1 - p_win_share)
  end;
  p_win := least(p_win, 0.82);
  p_loss := 1 - p_draw - p_win;

  return jsonb_build_object(
    'win', round((1 / (p_win * 1.05))::numeric, 2),
    'draw', round((1 / (p_draw * 1.05))::numeric, 2),
    'loss', round((1 / (p_loss * 1.05))::numeric, 2)
  );
end;
$$;

revoke all on function public.preview_match_odds(uuid, text) from public, anon;
grant execute on function public.preview_match_odds(uuid, text) to authenticated;
