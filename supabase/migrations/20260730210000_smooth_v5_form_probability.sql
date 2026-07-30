-- La forme générale (v_q_forme) n'avait aucune régularisation propre : avec
-- très peu de matchs joués et aucune défaite enregistrée, elle saturait
-- exactement à 1.0 (puis 0.999999 après garde-fou). Deux issues différentes
-- (nul et victoire adverse) finissaient alors toutes les deux plafonnées à
-- la même cote maximale (15.00), ce qui a l'air cassé même si le calcul
-- n'est pas faux. Un lissage additif (règle de Laplace, un "match neutre"
-- de chaque côté) évite cette saturation prématurée avec un historique
-- encore très réduit.

create or replace function public.calculate_match_odds_v5(
  p_opponent_id uuid,
  p_reference_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_ref date := coalesce(p_reference_date, current_date);
  v_h_v numeric := 0;
  v_h_d numeric := 0;
  v_form_v numeric := 0;
  v_form_d numeric := 0;
  v_q_forme numeric;
  v_q numeric;
  v_cote_v_prov numeric;
  v_cote_d_prov numeric;
  v_cote_n_prov numeric;
  v_u_v numeric;
  v_u_n numeric;
  v_u_d numeric;
  v_s numeric;
  v_p_v numeric;
  v_p_n numeric;
  v_p_d numeric;
begin
  if not exists (select 1 from public.opponents where id = p_opponent_id) then
    raise exception 'Adversaire introuvable';
  end if;

  with h2h as (
    select
      case
        when m.score_as_grinta > m.score_adverse then 'V'
        when m.score_as_grinta = m.score_adverse then 'N'
        else 'D'
      end as result,
      row_number() over (
        order by m.match_date desc, m.match_time desc nulls last, m.id desc
      ) as rang,
      greatest(0, (v_ref - m.match_date))::numeric as age
    from public.matches m
    where m.opponent_id = p_opponent_id
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  ), weighted as (
    select
      result,
      case
        when rang <= 5 then
          (array[1.0, 0.95, 0.90, 0.85, 0.80])[rang::int]
            * power(0.5::numeric, age / 900.0)
        else
          0.35 * power(0.75::numeric, (rang - 6)::numeric)
            * power(0.5::numeric, age / 900.0)
      end as poids
    from h2h
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_h_v, v_h_d
  from weighted;

  with form as (
    select
      case
        when m.score_as_grinta > m.score_adverse then 'V'
        when m.score_as_grinta = m.score_adverse then 'N'
        else 'D'
      end as result,
      power(
        0.5::numeric,
        greatest(0, (v_ref - m.match_date))::numeric / 180.0
      ) as poids
    from public.matches m
    where m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_form_v, v_form_d
  from form;

  -- Lissage de Laplace : évite qu'un historique très réduit (ex. deux
  -- victoires, zéro défaite) ne fasse saturer la probabilité à 100%.
  v_q_forme := (v_form_v + 1.0) / (v_form_v + v_form_d + 2.0);

  v_q := (1.0 * v_q_forme + v_h_v) / (1.0 + v_h_v + v_h_d);
  v_q := least(0.999999, greatest(0.000001, v_q));

  v_cote_v_prov := 1.0 / v_q;
  v_cote_d_prov := 1.0 / (1.0 - v_q);
  v_cote_n_prov := ((v_cote_v_prov + v_cote_d_prov) / 2.0) * 1.50;

  v_u_v := 1.0 / v_cote_v_prov;
  v_u_n := 1.0 / v_cote_n_prov;
  v_u_d := 1.0 / v_cote_d_prov;
  v_s := v_u_v + v_u_n + v_u_d;
  v_p_v := v_u_v / v_s;
  v_p_n := v_u_n / v_s;
  v_p_d := v_u_d / v_s;

  return jsonb_build_object(
    'win', greatest(1.05, least(15.00, round(1.0 / v_p_v, 2))),
    'draw', greatest(1.05, least(15.00, round(1.0 / v_p_n, 2))),
    'loss', greatest(1.05, least(15.00, round(1.0 / v_p_d, 2))),
    'probability_win', round(v_p_v, 6),
    'probability_draw', round(v_p_n, 6),
    'probability_loss', round(v_p_d, 6),
    'q_decisive', round(v_q, 6),
    'q_form', round(v_q_forme, 6),
    'h2h_win_weight', round(v_h_v, 6),
    'h2h_loss_weight', round(v_h_d, 6),
    'model_version', 'results_weighted_v5'
  );
end;
$function$;

-- Recalcule les cotes de tous les matchs à venir avec le lissage corrigé.
do $$
begin
  if to_regprocedure('public.recalculate_upcoming_match_odds_v4()') is not null then
    perform public.recalculate_upcoming_match_odds_v4();
  end if;
end;
$$;
