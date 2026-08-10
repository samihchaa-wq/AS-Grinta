-- Les cotes suggérées reflètent la forme du moment : moyenne des buts
-- marqués/encaissés sur les 4 derniers matchs joués, pondérée 40 % pour le
-- dernier, 30 % l'avant-dernier, 20 % puis 10 %. S'il y a moins de 4 matchs,
-- les poids sont renormalisés sur les matchs disponibles. Les cotes restent
-- équitables (1 / probabilité), arrondies à une décimale.
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

  with last_matches as (
    select
      m.score_as_grinta::numeric as goals_for,
      m.score_adverse::numeric as goals_against,
      row_number() over (
        order by m.match_date desc, m.created_at desc
      ) as rank
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    order by m.match_date desc, m.created_at desc
    limit 4
  ), weighted as (
    select
      goals_for,
      goals_against,
      case rank
        when 1 then 0.40
        when 2 then 0.30
        when 3 then 0.20
        else 0.10
      end as weight
    from last_matches
  )
  select
    coalesce(sum(goals_for * weight) / nullif(sum(weight), 0), 1.5),
    coalesce(sum(goals_against * weight) / nullif(sum(weight), 0), 1.5)
  into lambda_for, lambda_against
  from weighted;

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
    'win', round((1 / p_win)::numeric, 1),
    'draw', round((1 / p_draw)::numeric, 1),
    'loss', round((1 / p_loss)::numeric, 1)
  );
end;
$$;
