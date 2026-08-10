-- Remise à zéro de la simulation de la saison 2026-2027 : on repart sur une
-- saison ouverte fraîche (la suite naturelle de 2025-2026). Les titres et
-- badges gagnés sur cette saison « qui n'a pas vraiment eu lieu » sont retirés.
-- Les badges carrière (issus de l'import historique) et le vrai match à venir
-- restent intacts.
do $$
declare
  v_season uuid;
begin
  select id into v_season from public.seasons where name = '2026-2027';
  if v_season is null then
    return;
  end if;

  -- Titres de saison simulés.
  delete from public.season_awards where season_id = v_season;

  -- Badges gagnés pendant la simulation : titres pronos + palier saisonnier.
  delete from public.profile_badges pb using public.badges b
  where pb.badge_id = b.id
    and b.code in (
      'title_best_pred_overall__1',
      'title_best_pred_player__1',
      'clean_sheets_season__3'
    );

  -- Pronostics de saison remis à vide (saison fraîche, non verrouillée).
  update public.season_predictions
    set predicted_value_30 = 0, is_filled = false, updated_at = now()
    where season_id = v_season;
end $$;

-- Recalcul des badges de Samih (ne réattribue pas les badges simulés puisque
-- les titres et matchs de la simulation n'existent plus).
select public.recalculate_profile_badges('89f24276-dac0-4046-87a3-6c28e48fef3a');
