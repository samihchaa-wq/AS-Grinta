begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into public.historical_player_statistics(
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
  source_label
)
values (
  'previous',
  '2025-2026',
  1,
  'Import Historique',
  false,
  29,
  20,
  2,
  7,
  10,
  2,
  0,
  'test_rollover'
);

insert into public.seasons(id, name, status, created_at)
values
  (
    '71000000-0000-0000-0000-000000000001',
    '2025-2026',
    'archived',
    '2025-07-01T00:00:00Z'
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    '2026-2027',
    'open',
    '2026-07-01T00:00:00Z'
  );

select is(
  (
    select player_name
    from public.v_statistics_players
    where period_key = 'previous'
    limit 1
  ),
  'Import Historique',
  'l’import historique sert de repli quand la saison précédente n’a aucun effectif applicatif'
);

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position
)
values (
  '72000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000001',
  'Joueur',
  'Application',
  false,
  true,
  1
);

select is(
  (
    select player_name
    from public.v_statistics_players
    where period_key = 'previous'
    limit 1
  ),
  'Joueur',
  'un effectif applicatif remplace immédiatement l’import historique'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Joueur'
  ),
  0,
  'la saison précédente apparaît même sans statistique de match'
);

select is(
  (
    select count(*)
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Import Historique'
  ),
  0::bigint,
  'l’import n’est jamais additionné à l’effectif applicatif'
);

update public.seasons
set status = 'archived'
where id = '71000000-0000-0000-0000-000000000002';

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position
)
values (
  '72000000-0000-0000-0000-000000000002',
  '71000000-0000-0000-0000-000000000002',
  'Nouvelle',
  'Précédente',
  false,
  true,
  1
);

insert into public.seasons(id, name, status, created_at)
values (
  '71000000-0000-0000-0000-000000000003',
  '2027-2028',
  'open',
  '2027-07-01T00:00:00Z'
);

select is(
  (
    select distinct period_label
    from public.v_statistics_players
    where period_key = 'previous'
  ),
  '2026-2027',
  'l’ouverture d’une nouvelle saison fait automatiquement basculer l’ancienne dans Saison précédente'
);

select is(
  (
    select count(*)
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Nouvelle'
  ),
  1::bigint,
  'la nouvelle saison précédente est utilisée même avec zéro match'
);

select * from finish();
rollback;
