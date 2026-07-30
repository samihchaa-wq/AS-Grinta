-- Restaure calculate_match_odds_v5 exactement telle qu'écrite le 18 juillet
-- (PR #270, commit 18a0d2d) : aucune modification par rapport à la formule
-- d'origine. Les ajustements testés depuis (garde-fou sur les cotes
-- finales, lissage de la forme générale) sont retirés à la demande
-- explicite du client — la méthode reste strictement celle sur laquelle on
-- s'était mis d'accord.

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
  v_h_v numeric := 0; -- somme des poids des victoires en confrontation directe
  v_h_d numeric := 0; -- somme des poids des défaites en confrontation directe
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

  -- Étapes 1 à 4 : confrontations directes classées de la plus récente
  -- (rang 1) à la plus ancienne. Les nuls gardent leur rang mais ne sont
  -- sommés ni dans H_V ni dans H_D.
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

  -- Étape 5 : forme générale récente, tous adversaires confondus.
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

  -- Étape 6 : probabilité décisive, prior de force = 1.
  v_q := (1.0 * v_q_forme + v_h_v) / (1.0 + v_h_v + v_h_d);
  -- Garde-fou anti division par zéro dans les cas dégénérés (aucune défaite
  -- ni victoire enregistrée) : garde Q strictement dans ]0 ; 1[.
  v_q := least(0.999999, greatest(0.000001, v_q));

  -- Étapes 7 et 8 : cotes provisoires.
  v_cote_v_prov := 1.0 / v_q;
  v_cote_d_prov := 1.0 / (1.0 - v_q);
  v_cote_n_prov := ((v_cote_v_prov + v_cote_d_prov) / 2.0) * 1.50;

  -- Étapes 9 et 10 : probabilités implicites puis normalisation.
  v_u_v := 1.0 / v_cote_v_prov;
  v_u_n := 1.0 / v_cote_n_prov;
  v_u_d := 1.0 / v_cote_d_prov;
  v_s := v_u_v + v_u_n + v_u_d;
  v_p_v := v_u_v / v_s;
  v_p_n := v_u_n / v_s;
  v_p_d := v_u_d / v_s;

  -- Étape 11 : cotes finales, arrondies à deux décimales uniquement ici.
  return jsonb_build_object(
    'win', round(1.0 / v_p_v, 2),
    'draw', round(1.0 / v_p_n, 2),
    'loss', round(1.0 / v_p_d, 2),
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

-- Recalcule les cotes de tous les matchs à venir avec la formule d'origine.
do $$
begin
  if to_regprocedure('public.recalculate_upcoming_match_odds_v4()') is not null then
    perform public.recalculate_upcoming_match_odds_v4();
  end if;
end;
$$;
