begin;

set local search_path = public, extensions, pg_catalog;
select plan(8);

insert into public.players(id, display_name)
values (
  'e1000000-0000-0000-0000-000000000001',
  'QA Archive'
);

-- Le profil est créé par le trigger Auth ; on l'attache ensuite à l'identité
-- joueur canonique pour respecter le même contrat que la production.
insert into auth.users(id, email, raw_user_meta_data)
values (
  'e2000000-0000-0000-0000-000000000001',
  'qa-archive@example.invalid',
  '{"first_name":"QA","last_name":"Archive"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    player_id = 'e1000000-0000-0000-0000-000000000001',
    updated_at = now()
where id = 'e2000000-0000-0000-0000-000000000001';

-- Ces dates futures rendent la saison de test déterministe même si le socle
-- canonique contient déjà une saison ouverte.
insert into public.seasons(id, name, status, created_at)
values
  (
    'e3000000-0000-0000-0000-000000000001',
    '2098-2099',
    'archived',
    '2098-07-01T00:00:00Z'
  ),
  (
    'e3000000-0000-0000-0000-000000000002',
    '2099-2100',
    'open',
    '2099-07-01T00:00:00Z'
  );

insert into public.season_players(
  id,
  season_id,
  player_id,
  profile_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position
)
values
  (
    'e4000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    'QA',
    'Archive',
    false,
    true,
    1
  ),
  (
    'e4000000-0000-0000-0000-000000000002',
    'e3000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    'QA',
    'Archive',
    false,
    true,
    1
  );

insert into public.matches(
  id,
  season_id,
  match_date,
  match_time,
  location,
  planned_duration_minutes,
  status,
  score_as_grinta,
  score_adverse,
  created_by,
  result_validated_at
)
values (
  'e5000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000001',
  date '2099-04-01',
  time '20:00',
  'domicile',
  90,
  'termine',
  2,
  0,
  'e2000000-0000-0000-0000-000000000001',
  now()
);

insert into public.match_attendance(match_id, season_player_id)
values (
  'e5000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001'
);

insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
values (
  'e5000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001',
  2,
  false
);

-- Reproduit le vrai cycle de vie : le joueur participe d'abord à la saison,
-- puis sa fiche historique est désactivée après que ses statistiques existent.
update public.season_players
set is_active = false
where id = 'e4000000-0000-0000-0000-000000000001';

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'QA Archive'
  ),
  1,
  'un effectif désactivé reste compté dans la saison précédente'
);

select is(
  (
    select goals
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'QA Archive'
  ),
  2,
  'les buts liés à l’ancienne adhésion restent dans la saison précédente'
);

select is(
  (
    select team_clean_sheets
    from public.v_statistics_players
    where period_key = 'previous'
      and player_name = 'QA Archive'
  ),
  1,
  'le contrat team_clean_sheets courant est conservé pour l’historique'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'current'
      and player_name = 'QA Archive'
  ),
  0,
  'l’adhésion active de la saison courante n’absorbe pas les anciens matchs'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'all_time'
      and player_name = 'QA Archive'
  ),
  1,
  'Toutes saisons additionne l’ancienne adhésion sans double compter la nouvelle'
);

select is(
  (
    select goals
    from public.v_statistics_players
    where period_key = 'all_time'
      and player_name = 'QA Archive'
  ),
  2,
  'Toutes saisons conserve les statistiques de l’adhésion désactivée'
);

update public.season_players
set is_active = false
where id = 'e4000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from public.v_statistics_players
    where period_key = 'current'
      and player_name = 'QA Archive'
  ),
  0::bigint,
  'un joueur désactivé dans la saison ouverte disparaît du classement courant'
);

select is(
  (
    select matches_played
    from public.v_statistics_players
    where period_key = 'all_time'
      and player_name = 'QA Archive'
  ),
  1,
  'désactiver la fiche courante ne détruit pas l’historique Toutes saisons'
);

select * from finish();
rollback;
