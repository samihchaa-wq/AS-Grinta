-- Moteur de cotes V5 : fondé uniquement sur les RÉSULTATS (V / N / D) de
-- l'AS Grinta, avec pondération par récence continue et par rang des
-- confrontations directes. La date de référence est la date prévue du match
-- à venir. Les nuls occupent leur rang chronologique mais ne comptent ni dans
-- les victoires ni dans les défaites.
--
-- Le lieu (domicile/extérieur) n'est plus pris en compte : la signature de
-- calculate_match_odds_v4 est conservée pour compatibilité mais délègue à V5.

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

-- Compatibilité : preview_match_odds appelle toujours calculate_match_odds_v4.
-- On la redéfinit pour déléguer au moteur V5 (le lieu est ignoré). La date de
-- référence de la prévisualisation est le jour courant, faute de date de match
-- transmise par le client à ce stade.
create or replace function public.calculate_match_odds_v4(
  p_opponent_id uuid,
  p_location text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select public.calculate_match_odds_v5(p_opponent_id, current_date);
$function$;

-- Les cotes stockées d'un match à venir utilisent SA date prévue comme date de
-- référence (conformément à la méthode).
create or replace function public.upsert_match_odds_v4(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match record;
  v_result jsonb;
begin
  select id, opponent_id, match_date, status
  into v_match
  from public.matches
  where id = p_match_id;

  if not found or v_match.status <> 'a_venir' then
    return;
  end if;

  v_result := public.calculate_match_odds_v5(v_match.opponent_id, v_match.match_date);

  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul, odds_victoire_adverse,
    probability_win, probability_draw, probability_loss,
    model_version, computed_at
  ) values (
    v_match.id,
    (v_result->>'win')::numeric,
    (v_result->>'draw')::numeric,
    (v_result->>'loss')::numeric,
    (v_result->>'probability_win')::numeric,
    (v_result->>'probability_draw')::numeric,
    (v_result->>'probability_loss')::numeric,
    v_result->>'model_version',
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      probability_win = excluded.probability_win,
      probability_draw = excluded.probability_draw,
      probability_loss = excluded.probability_loss,
      expected_goals_as_grinta = null,
      expected_goals_adverse = null,
      confidence = null,
      model_version = excluded.model_version,
      computed_at = excluded.computed_at;
end;
$function$;

-- Fonction interne : jamais appelée directement depuis le client.
revoke all on function public.calculate_match_odds_v5(uuid, date)
  from public, anon, authenticated;

-- Recalcule les cotes de tous les matchs à venir avec le nouveau modèle.
select public.recalculate_upcoming_match_odds_v4();
