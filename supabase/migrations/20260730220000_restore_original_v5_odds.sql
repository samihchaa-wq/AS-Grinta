-- Restaure calculate_match_odds_v5 à sa dernière version correcte avant les
-- errements du 30 juillet : celle du 25 juillet (compact_archived_match_
-- history.sql), qui combine les matchs récents (public.matches, status
-- 'termine') ET les 156 matchs d'historique archivé (public.
-- historical_match_scores) via UNION ALL.
--
-- Une première tentative de retour en arrière, plus tôt dans la journée,
-- avait par erreur restauré la version du 18 juillet — antérieure à cette
-- fusion des deux sources — ce qui faisait perdre l'accès à l'historique
-- archivé et rendait les cotes non représentatives (calculées sur 1 ou 2
-- matchs de test au lieu des ~158 matchs réels). Cette migration corrige
-- cette erreur et rétablit le calcul exact du 25 juillet, sans aucune
-- autre modification.

create or replace function public.calculate_match_odds_v5(
  p_opponent_id uuid,
  p_reference_date date
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

  with all_results as (
    select m.id, m.opponent_id, m.match_date,
      m.score_as_grinta, m.score_adverse
    from public.matches m
    where m.status = 'termine'
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    union all
    select h.id, h.opponent_id, h.match_date,
      h.score_as_grinta::integer, h.score_adverse::integer
    from public.historical_match_scores h
  ), h2h as (
    select
      case
        when r.score_as_grinta > r.score_adverse then 'V'
        when r.score_as_grinta = r.score_adverse then 'N'
        else 'D'
      end as result,
      row_number() over (
        order by r.match_date desc, r.id desc
      ) as rang,
      greatest(0, (v_ref - r.match_date))::numeric as age
    from all_results r
    where r.opponent_id = p_opponent_id
      and r.match_date < v_ref
  ), weighted as (
    select result,
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

  with all_results as (
    select m.id, m.match_date, m.score_as_grinta, m.score_adverse
    from public.matches m
    where m.status = 'termine'
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    union all
    select h.id, h.match_date,
      h.score_as_grinta::integer, h.score_adverse::integer
    from public.historical_match_scores h
  ), form as (
    select
      case
        when r.score_as_grinta > r.score_adverse then 'V'
        when r.score_as_grinta = r.score_adverse then 'N'
        else 'D'
      end as result,
      power(
        0.5::numeric,
        greatest(0, (v_ref - r.match_date))::numeric / 180.0
      ) as poids
    from all_results r
    where r.match_date < v_ref
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
    'model_version', 'compact_history_v6'
  );
end;
$$;

-- Recalcule les cotes de tous les matchs à venir avec l'historique complet.
do $$
begin
  if to_regprocedure('public.recalculate_upcoming_match_odds_v4()') is not null then
    perform public.recalculate_upcoming_match_odds_v4();
  end if;
end;
$$;
