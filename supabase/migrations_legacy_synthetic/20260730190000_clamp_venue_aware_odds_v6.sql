-- Corrige un défaut du moteur V6 (déjà présent en V5) : quand l'historique
-- est très réduit (ex. un seul match joué), la probabilité décisive Q peut
-- saturer tout près de 1, et 1/(1-Q) explose vers des cotes absurdes
-- (des millions). Les cotes finales sont maintenant plafonnées à une
-- fourchette réaliste, comme le faisait l'ancien moteur V4.

create or replace function public.calculate_match_odds_v6(
  p_opponent_id uuid,
  p_reference_date date,
  p_location text
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
  v_venue_v numeric := 0;
  v_venue_d numeric := 0;
  v_venue_weight numeric := 0;
  v_q_forme numeric;
  v_q_venue numeric;
  v_venue_effect numeric := 0;
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
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide';
  end if;

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

  if (v_form_v + v_form_d) = 0 then
    v_q_forme := 0.50;
  else
    v_q_forme := v_form_v / (v_form_v + v_form_d);
  end if;

  with form_venue as (
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
      and m.location = p_location
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_venue_v, v_venue_d
  from form_venue;

  v_venue_weight := v_venue_v + v_venue_d;
  if v_venue_weight = 0 then
    v_q_venue := v_q_forme;
  else
    v_q_venue := v_venue_v / v_venue_weight;
  end if;

  v_venue_effect := greatest(-0.15, least(0.15,
    (v_q_venue - v_q_forme) * v_venue_weight / (v_venue_weight + 4.0)
  ));
  v_q_forme := least(0.999999, greatest(0.000001, v_q_forme + v_venue_effect));

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
    -- Plafond réaliste : évite qu'un historique très réduit (peu de matchs
    -- joués) ne produise des cotes à plusieurs millions.
    'win', greatest(1.05, least(15.00, round(1.0 / v_p_v, 2))),
    'draw', greatest(1.05, least(15.00, round(1.0 / v_p_n, 2))),
    'loss', greatest(1.05, least(15.00, round(1.0 / v_p_d, 2))),
    'probability_win', round(v_p_v, 6),
    'probability_draw', round(v_p_n, 6),
    'probability_loss', round(v_p_d, 6),
    'q_decisive', round(v_q, 6),
    'q_form', round(v_q_forme, 6),
    'venue_effect', round(v_venue_effect, 6),
    'venue_weight', round(v_venue_weight, 6),
    'h2h_win_weight', round(v_h_v, 6),
    'h2h_loss_weight', round(v_h_d, 6),
    'model_version', 'venue_aware_v6'
  );
end;
$function$;

-- Recalcule les cotes de tous les matchs à venir avec le plafond corrigé.
do $$
begin
  if to_regprocedure('public.recalculate_upcoming_match_odds_v4()') is not null then
    perform public.recalculate_upcoming_match_odds_v4();
  end if;
end;
$$;
