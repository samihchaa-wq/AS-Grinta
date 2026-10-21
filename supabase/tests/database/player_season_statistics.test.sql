begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Fiche joueur : le graphique d'évolution lit les statistiques d'un joueur
-- saison par saison, archive match par match et matchs de l'application
-- confondus, avec les mêmes règles que la vue des statistiques.

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_player_season_statistics(text, boolean, uuid)',
    'execute'
  ),
  'un membre connecté lit l’évolution d’un joueur'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_player_season_statistics(text, boolean, uuid)',
    'execute'
  ),
  'un visiteur anonyme ne lit pas l’évolution'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.get_player_season_statistics(text, boolean, uuid)',
    'execute'
  ),
  'un visiteur anonyme n’atteint pas le calcul privé'
);

insert into public.players(id, display_name)
values ('f1000000-0000-0000-0000-000000000001', 'Evolution Testeur');

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'f2000000-0000-0000-0000-000000000001',
    'evolution-actif@example.invalid',
    '{"first_name":"Evolution","last_name":"Testeur"}'::jsonb
  ),
  (
    'f2000000-0000-0000-0000-000000000002',
    'evolution-inactif@example.invalid',
    '{"first_name":"Evolution","last_name":"Inactif"}'::jsonb
  );

update public.profiles
set role = 'admin',
    status = 'active',
    player_id = 'f1000000-0000-0000-0000-000000000001',
    updated_at = now()
where id = 'f2000000-0000-0000-0000-000000000001';

update public.profiles
set status = 'pending',
    updated_at = now()
where id = 'f2000000-0000-0000-0000-000000000002';

-- Archive : trois matchs sur deux saisons, la saison commençant le 1er juillet.
insert into public.opponents(id, name)
values ('f5000000-0000-0000-0000-000000000001', 'Adversaire test évolution');

insert into public.historical_match_scores(
  id, opponent_id, match_date, score_as_grinta, score_adverse, is_home
)
values
  ('f6000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', date '2095-11-01', 1, 1, true),
  ('f6000000-0000-0000-0000-000000000002',
   'f5000000-0000-0000-0000-000000000001', date '2096-07-01', 2, 0, true),
  ('f6000000-0000-0000-0000-000000000003',
   'f5000000-0000-0000-0000-000000000001', date '2097-03-01', 0, 1, false),
  ('f6000000-0000-0000-0000-000000000004',
   'f5000000-0000-0000-0000-000000000001', date '2097-04-01', 5, 0, true);

insert into public.historical_match_players(
  match_id, player_id, source_name, is_present, goals, is_motm
)
values
  ('f6000000-0000-0000-0000-000000000001',
   'f1000000-0000-0000-0000-000000000001', 'Evolution Testeur', true, 1, false),
  ('f6000000-0000-0000-0000-000000000002',
   'f1000000-0000-0000-0000-000000000001', 'Evolution Testeur', true, 3, true),
  ('f6000000-0000-0000-0000-000000000003',
   'f1000000-0000-0000-0000-000000000001', 'Evolution Testeur', true, 0, false),
  -- Sur la feuille mais absent : ni match joué ni résultat.
  ('f6000000-0000-0000-0000-000000000004',
   'f1000000-0000-0000-0000-000000000001', 'Evolution Testeur', false, 0, false);

-- Application : une saison avec un match terminé et un match pas encore
-- validé.
insert into public.seasons(id, name, status, created_at)
values (
  'f3000000-0000-0000-0000-000000000001',
  '2098-2099',
  'open',
  '2098-07-01T00:00:00Z'
);

insert into public.season_players(
  id, season_id, player_id, profile_id, first_name, last_name,
  is_goalkeeper, is_active, position
)
values (
  'f4000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  'Evolution',
  'Testeur',
  false,
  true,
  1
);

insert into public.matches(
  id, season_id, match_date, match_time, location, planned_duration_minutes,
  status, score_as_grinta, score_adverse, created_by, result_validated_at
)
values (
  'f7000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001',
  current_date - 1,
  time '20:00',
  'domicile',
  90,
  'termine',
  3,
  1,
  'f2000000-0000-0000-0000-000000000001',
  now()
);

insert into public.match_attendance(match_id, season_player_id)
values (
  'f7000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001'
);

insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
values (
  'f7000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001',
  2,
  false
);

insert into public.match_man_of_match(match_id, season_player_id)
values (
  'f7000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

create or replace function pg_temp.season_line(
  p_full_name text,
  p_is_goalkeeper boolean,
  p_profile_id uuid,
  p_season text
)
returns text
language sql
stable
as $function$
  select concat_ws(
    '/', s.matches_played, s.wins, s.draws, s.losses, s.goals, s.hdm
  )
  from public.get_player_season_statistics(
    p_full_name, p_is_goalkeeper, p_profile_id
  ) s
  where s.season_name = p_season;
$function$;

select is(
  (
    select array_agg(s.season_name order by s.season_name)
    from public.get_player_season_statistics(
      'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001'
    ) s
  ),
  array['2095-2096', '2096-2097', '2098-2099'],
  'une ligne par saison jouée, dans l’ordre, archive et application réunies'
);

select is(
  pg_temp.season_line(
    'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001',
    '2095-2096'
  ),
  '1/0/1/0/1/0',
  'un match d’archive de novembre compte dans la saison commencée en juillet'
);

select is(
  pg_temp.season_line(
    'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001',
    '2096-2097'
  ),
  '2/1/0/1/3/1',
  'matchs, résultats, buts et homme du match de l’archive ; un absent ne compte pas'
);

select is(
  pg_temp.season_line(
    'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001',
    '2098-2099'
  ),
  '1/1/0/0/2/1',
  'les matchs terminés de l’application forment leur propre saison'
);

select is(
  (
    select array_agg(s.season_name order by s.season_name)
    from public.get_player_season_statistics(
      'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001'
    ) s
    where s.is_current
  ),
  array['2098-2099'],
  'seule la saison ouverte est signalée en cours'
);

select is(
  pg_temp.season_line('  evolution   TESTEUR ', false, null, '2096-2097'),
  '2/1/0/1/3/1',
  'sans compte, le nom complet et le poste suffisent, casse et espaces ignorés'
);

select is(
  (
    select count(*)::integer
    from public.get_player_season_statistics('Evolution Testeur', true, null)
  ),
  0,
  'le même nom au poste de gardien désigne un autre joueur'
);

reset role;

-- Un joueur connu seulement de l'archive est retrouvé par son classement
-- importé.
insert into public.players(id, display_name)
values ('f1000000-0000-0000-0000-000000000002', 'Archive Seule');

insert into public.historical_player_statistics(
  id, scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets, player_id
)
values (
  987654329001,
  'all_time', null, 999, 'Archive Seule', false,
  1, 1, 0, 0, 0, 0, 0, 'f1000000-0000-0000-0000-000000000002'
);

insert into public.historical_match_players(
  match_id, player_id, source_name, is_present, goals, is_motm
)
values (
  'f6000000-0000-0000-0000-000000000002',
  (select player_id from public.historical_player_statistics where id = 987654329001),
  'Archive Seule', true, 0, false
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  pg_temp.season_line('Archive Seule', false, null, '2096-2097'),
  '1/1/0/0/0/0',
  'un joueur absent des effectifs de l’application garde ses saisons d’archive'
);

reset role;

-- Un compte non validé n'accède pas à l'archive.
select set_config(
  'request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select * from public.get_player_season_statistics('Evolution Testeur', false, null)$$,
  '42501',
  'un compte non actif ne lit pas l’évolution'
);

reset role;

select * from finish();
rollback;
