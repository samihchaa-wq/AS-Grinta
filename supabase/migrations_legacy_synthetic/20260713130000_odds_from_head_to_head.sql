-- Cotes calculées à partir des PRÉCÉDENTES RENCONTRES face à l'adversaire,
-- pondérées par récence (la dernière confrontation pèse le plus). Repli sur la
-- forme générale d'AS Grinta s'il n'y a aucun historique face à cet adversaire,
-- puis valeur neutre. Ajustement domicile / extérieur.
create or replace function public.preview_match_odds(p_opponent_id uuid, p_location text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  lambda_for numeric;
  lambda_against numeric;
  n_h2h integer := 0;
  gap numeric;
  p_draw numeric;
  p_win_share numeric;
  p_win numeric;
  p_loss numeric;
begin
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide';
  end if;

  -- 1) Précédentes rencontres face à CET adversaire, pondérées par récence.
  with h2h as (
    select
      m.score_as_grinta::numeric as goals_for,
      m.score_adverse::numeric as goals_against,
      row_number() over (order by m.match_date desc, m.created_at desc) as rank
    from public.matches m
    where m.opponent_id = p_opponent_id
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    order by m.match_date desc, m.created_at desc
    limit 5
  ), weighted as (
    select goals_for, goals_against,
      case rank
        when 1 then 0.40
        when 2 then 0.25
        when 3 then 0.18
        when 4 then 0.11
        else 0.06
      end as weight
    from h2h
  )
  select
    sum(goals_for * weight) / nullif(sum(weight), 0),
    sum(goals_against * weight) / nullif(sum(weight), 0),
    count(*)
  into lambda_for, lambda_against, n_h2h
  from weighted;

  -- 2) Repli : aucune confrontation connue -> forme générale des 4 derniers.
  if coalesce(n_h2h, 0) = 0 then
    with last_matches as (
      select
        m.score_as_grinta::numeric as goals_for,
        m.score_adverse::numeric as goals_against,
        row_number() over (order by m.match_date desc, m.created_at desc) as rank
      from public.matches m
      where m.status in ('termine', 'archive')
        and m.score_as_grinta is not null
        and m.score_adverse is not null
      order by m.match_date desc, m.created_at desc
      limit 4
    ), weighted as (
      select goals_for, goals_against,
        case rank when 1 then 0.40 when 2 then 0.30 when 3 then 0.20 else 0.10 end as weight
      from last_matches
    )
    select
      coalesce(sum(goals_for * weight) / nullif(sum(weight), 0), 1.5),
      coalesce(sum(goals_against * weight) / nullif(sum(weight), 0), 1.5)
    into lambda_for, lambda_against
    from weighted;
  end if;

  lambda_for := coalesce(lambda_for, 1.5);
  lambda_against := coalesce(lambda_against, 1.5);

  -- 3) Avantage du terrain.
  if p_location = 'domicile' then
    lambda_for := lambda_for * 1.10;
    lambda_against := lambda_against * 0.92;
  else
    lambda_for := lambda_for * 0.92;
    lambda_against := lambda_against * 1.10;
  end if;

  -- 4) Écart de forme -> probabilités -> cotes (modèle inchangé).
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
$function$;
