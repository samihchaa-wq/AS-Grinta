begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'd1000000-0000-0000-0000-000000000001',
    'season-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Saisons"}'::jsonb
  ),
  (
    'd1000000-0000-0000-0000-000000000002',
    'season-player@example.invalid',
    '{"first_name":"Ancien","last_name":"Joueur"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'd1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status, created_at)
values
  (
    'd2000000-0000-0000-0000-000000000001',
    '2030-2031',
    'archived',
    '2030-07-01T00:00:00Z'
  ),
  (
    'd2000000-0000-0000-0000-000000000002',
    '2031-2032',
    'archived',
    '2031-07-01T00:00:00Z'
  ),
  (
    'd2000000-0000-0000-0000-000000000003',
    '2032-2033',
    'open',
    '2032-07-01T00:00:00Z'
  );

insert into public.opponents(id, name)
values ('d3000000-0000-0000-0000-000000000001', 'Cycle Saison FC');

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
values
  (
    'd4000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    'Ancien',
    'Joueur',
    false,
    false,
    1,
    'd1000000-0000-0000-0000-000000000002'
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000002',
    'Ancien',
    'Joueur',
    false,
    false,
    1,
    'd1000000-0000-0000-0000-000000000002'
  ),
  (
    'd4000000-0000-0000-0000-000000000003',
    'd2000000-0000-0000-0000-000000000003',
    'Ancien',
    'Joueur',
    false,
    true,
    1,
    'd1000000-0000-0000-0000-000000000002'
  );

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
  'all_time',
  null,
  1,
  'Ancien Joueur',
  false,
  10,
  6,
  2,
  2,
  4,
  2,
  0,
  'test_multi_season'
);

update public.historical_team_statistics
set through_season = '2030-2031',
    matches_played = 10,
    wins = 6,
    draws = 2,
    losses = 2,
    goals_for = 20,
    goals_against = 10,
    best_win_streak = 2,
    best_win_start = date '2030-08-01',
    best_win_end = date '2030-08-08',
    best_unbeaten_streak = 3,
    best_unbeaten_start = date '2030-08-01',
    best_unbeaten_end = date '2030-08-15',
    worst_loss_streak = 1,
    worst_loss_start = date '2030-09-01',
    worst_loss_end = date '2030-09-01',
    worst_winless_streak = 1,
    worst_winless_start = date '2030-09-01',
    worst_winless_end = date '2030-09-01',
    updated_at = now()
where scope = 'all_time';

insert into public.matches(
  id,
  season_id,
  opponent_id,
  match_date,
  location,
  status,
  score_as_grinta,
  score_adverse,
  created_by,
  result_validated_at
)
values
  (
    'd5000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    date '2031-04-01',
    'domicile',
    'archive',
    3,
    1,
    'd1000000-0000-0000-0000-000000000001',
    now()
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000001',
    date '2032-04-01',
    'exterieur',
    'termine',
    1,
    1,
    'd1000000-0000-0000-0000-000000000001',
    now()
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd2000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000001',
    date '2033-04-01',
    'domicile',
    'termine',
    0,
    2,
    'd1000000-0000-0000-0000-000000000001',
    now()
  );

insert into public.match_attendance(match_id, season_player_id)
values
  (
    'd5000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001'
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd4000000-0000-0000-0000-000000000002'
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd4000000-0000-0000-0000-000000000003'
  );

insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
values
  (
    'd5000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001',
    2,
    false
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd4000000-0000-0000-0000-000000000002',
    1,
    false
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd4000000-0000-0000-0000-000000000003',
    3,
    false
  );

insert into public.match_man_of_match(match_id, season_player_id)
values (
  'd5000000-0000-0000-0000-000000000002',
  'd4000000-0000-0000-0000-000000000002'
);

-- La suppression du compte ne doit pas supprimer les noms ni les statistiques
-- portés par les effectifs et feuilles de match historiques.
delete from auth.users
where id = 'd1000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from public.season_players
    where id in (
      'd4000000-0000-0000-0000-000000000001',
      'd4000000-0000-0000-0000-000000000002',
      'd4000000-0000-0000-0000-000000000003'
    )
      and profile_id is null
  ),
  3::bigint,
  'la suppression du compte détache les effectifs sans supprimer leur historique'
);

select is(
  (
    select period_label
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Ancien'
  ),
  '2031-2032',
  'Saison précédente pointe vers la saison immédiatement antérieure'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Ancien'
  ),
  1,
  'un joueur inactif et sans compte reste comptabilisé dans la saison précédente'
);

select is(
  (
    select goals
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Ancien'
  ),
  1,
  'les buts de la saison précédente restent disponibles après archivage du joueur'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'current'
      and player_name = 'Ancien'
  ),
  1,
  'la saison ouverte conserve uniquement son effectif actif'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'all_time'
      and player_name = 'Ancien Joueur'
  ),
  13,
  'Toutes saisons additionne l’historique importé et trois saisons applicatives'
);

select is(
  (
    select goals
    from public.v_statistics_players
    where period_key = 'all_time'
      and player_name = 'Ancien Joueur'
  ),
  10,
  'Toutes saisons conserve les buts des effectifs désactivés et du compte supprimé'
);

select is(
  (
    select hdm
    from public.v_statistics_players
    where period_key = 'all_time'
      and player_name = 'Ancien Joueur'
  ),
  3,
  'Toutes saisons additionne les distinctions historiques et applicatives'
);

select is(
  (
    select period_label
    from public.v_statistics_team
    where period_key = 'previous'
  ),
  '2031-2032',
  'les statistiques équipe suivent la même saison précédente que les joueurs'
);

select is(
  (
    select matches_played
    from public.v_statistics_team
    where period_key = 'previous'
  ),
  1,
  'la saison précédente équipe contient son match terminé'
);

select is(
  (
    select matches_played
    from public.v_statistics_team
    where period_key = 'all_time'
  ),
  12,
  'le cumul équipe ajoute uniquement les saisons postérieures au socle historique'
);

select is(
  (
    select goals_for
    from public.v_statistics_team
    where period_key = 'all_time'
  ),
  21,
  'le cumul équipe additionne les buts marqués après le socle historique'
);

select is(
  (
    select goals_against
    from public.v_statistics_team
    where period_key = 'all_time'
  ),
  13,
  'le cumul équipe additionne les buts encaissés après le socle historique'
);

update public.seasons
set status = 'archived'
where id = 'd2000000-0000-0000-0000-000000000003';

insert into public.seasons(id, name, status, created_at)
values (
  'd2000000-0000-0000-0000-000000000004',
  '2033-2034',
  'open',
  '2033-07-01T00:00:00Z'
);

select is(
  (
    select distinct period_label
    from public.v_statistics_players
    where period_key = 'previous'
  ),
  '2032-2033',
  'une nouvelle ouverture fait basculer l’ancienne saison courante côté joueurs'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'Ancien'
  ),
  1,
  'la nouvelle saison précédente conserve le match de l’ancienne saison ouverte'
);

select is(
  (
    select period_label
    from public.v_statistics_team
    where period_key = 'previous'
  ),
  '2032-2033',
  'une nouvelle ouverture fait basculer l’ancienne saison courante côté équipe'
);

select is(
  (
    select matches_played
    from public.v_statistics_team
    where period_key = 'current'
  ),
  0,
  'une nouvelle saison ouverte démarre avec des statistiques équipe à zéro'
);

select is(
  (
    select matches_played
    from public.v_statistics_team
    where period_key = 'all_time'
  ),
  12,
  'ouvrir une saison vide ne modifie pas le cumul Toutes saisons'
);

select * from finish();
rollback;
