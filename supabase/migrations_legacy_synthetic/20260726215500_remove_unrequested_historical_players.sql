begin;

-- Retire les lignes ajoutées depuis les captures qui ne correspondent à aucun
-- joueur déjà présent dans un effectif de l'application. Elles ne doivent pas
-- apparaître comme de nouveaux joueurs dans les statistiques.
delete from public.historical_player_statistics h
where h.scope = 'previous'
  and h.season_name = '2025-2026'
  and h.source_label = 'captures_stats_joueurs_2025_2026'
  and not exists (
    select 1
    from public.season_players sp
    where lower(btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, ''))))
          = lower(btrim(h.player_name))
  );

-- Vérifie qu'il ne reste que les 19 joueurs déjà connus de l'effectif.
do $validation$
begin
  if (
    select count(*)
    from public.historical_player_statistics
    where scope = 'previous'
      and season_name = '2025-2026'
  ) <> 19 then
    raise exception 'Expected 19 previous-season players after cleanup';
  end if;
end;
$validation$;

commit;
