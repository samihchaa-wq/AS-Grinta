do $$
declare
  v_season uuid;
begin
  select id into v_season from public.seasons where name = '2026-2027';
  if v_season is null then
    return;
  end if;

  delete from public.season_awards where season_id = v_season;

  delete from public.profile_badges pb using public.badges b
  where pb.badge_id = b.id
    and b.code in (
      'title_best_pred_overall__1',
      'title_best_pred_player__1',
      'clean_sheets_season__3'
    );

  update public.season_predictions
    set predicted_value_30 = 0, is_filled = false, updated_at = now()
    where season_id = v_season;
end $$;

select public.recalculate_profile_badges('89f24276-dac0-4046-87a3-6c28e48fef3a');;
