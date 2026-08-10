begin;

-- Import complet du classement joueurs 2025-2026 depuis les captures validées.
-- « Saison précédente » reste dynamique dans v_statistics_players : cet import
-- sert de repli jusqu'à l'ouverture de la saison suivante, puis la saison
-- actuelle de l'application prendra automatiquement sa place.
delete from public.historical_player_statistics
where scope = 'previous';

insert into public.historical_player_statistics (
  scope,
  season_name,
  display_rank,
  player_name,
  is_goalkeeper,
  matches_played,
  wins,
  draws,
  losses,
  goals,
  hdm,
  clean_sheets,
  source_label,
  profile_id
)
values
  ('previous', '2025-2026',  1, 'Philippe Cou…',                 true,  30, 20, 2, 7,  0, 1, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  2, 'Milan Couzin',                  false, 29, 19, 2, 7, 30, 5, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  3, 'Allan Bamokena',                false, 28, 20, 1, 7, 23, 2, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  4, 'Flo Arnauduc',                  false, 28, 19, 2, 6,  6, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  5, 'Stéphane Fernandez',            false, 28, 19, 2, 6,  1, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  6, 'Alban Ricard',                  false, 27, 17, 2, 7, 15, 5, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  7, 'Luka Brunel',                   false, 27, 19, 2, 6, 11, 6, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  8, 'Samuel Granier',                false, 25, 16, 2, 6,  1, 1, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026',  9, 'Romain Spigolon',               false, 21, 13, 1, 6,  1, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 10, 'Samih Châa',                    true,  21, 15, 2, 3,  0, 4, 6,    'captures_stats_joueurs_2025_2026', '89f24276-dac0-4046-87a3-6c28e48fef3a'),
  ('previous', '2025-2026', 11, 'Alyoun Cherfi',                 false, 20, 14, 1, 4,  0, 1, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 12, 'Nicolas Belmonte',              false, 20, 15, 1, 4, 28, 4, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 13, 'Julio Vignard',                 false, 19, 12, 2, 5,  1, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 14, 'Amine Salhi',                   false, 17, 13, 2, 2,  7, 2, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 15, 'Julien Cesar',                  false, 15,  8, 1, 5,  3, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 16, 'Aki Salabee',                   false, 14, 10, 1, 2,  3, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 17, 'Anis Messaou…',                 false, 14, 10, 1, 2,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 18, 'Olivier Millet',                false, 14,  7, 1, 5,  0, 1, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 19, 'François De La Bourdonnaye',    false,  9,  6, 0, 3,  1, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 20, 'Hakim Cherfi',                  false,  9,  8, 0, 1,  2, 1, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 21, 'Simon Reis',                    false,  4,  3, 0, 1,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 22, 'Thibaut Mélet',                 false,  2,  1, 0, 1,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 23, 'Clément Pote…',                 false,  1,  0, 0, 1,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 24, 'Pote Milan',                    false,  1,  0, 0, 1,  1, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 25, 'Théo Pote D…',                  false,  1,  0, 0, 1,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 26, 'Vitorio Maldini',               false,  1,  0, 0, 1,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 27, 'Xavier Grossin',                false,  1,  0, 0, 1,  0, 0, null, 'captures_stats_joueurs_2025_2026', null),
  ('previous', '2025-2026', 28, 'Yoann Canal',                   false,  1,  0, 0, 1,  1, 0, null, 'captures_stats_joueurs_2025_2026', null);

do $validation$
begin
  if (select count(*) from public.historical_player_statistics where scope = 'previous' and season_name = '2025-2026') <> 28 then
    raise exception 'Expected 28 previous-season player statistics rows';
  end if;
end;
$validation$;

commit;
