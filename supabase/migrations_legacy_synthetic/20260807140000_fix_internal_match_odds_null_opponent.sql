-- upsert_match_odds_v4() ne s'arrêtait plus sur un match sans adversaire
-- (match_type = 'entre_nous', opponent_id null) : la garde correspondante,
-- introduite pour les matchs entre nous, avait été perdue lors du passage à
-- la version "v4" du calcul des cotes. calculate_match_odds_v5() lève alors
-- « Adversaire introuvable », ce qui casse à la fois la création d'un match
-- entre nous (déclencheur trg_auto_match_odds_v4) et le recalcul groupé des
-- cotes des matchs à venir (recalculate_upcoming_match_odds_v4(), appelé à
-- chaque validation de résultat).
create or replace function public.upsert_match_odds_v4(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_match record;
  v_result jsonb;
begin
  select id, opponent_id, match_date, status
  into v_match
  from public.matches
  where id = p_match_id;

  if not found or v_match.status <> 'a_venir' or v_match.opponent_id is null then
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
$$;
