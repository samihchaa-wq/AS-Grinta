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

select ok(
  (
    select relrowsecurity from pg_class
    where oid = 'public.historical_unscored_match_contributions'::regclass
  ),
  'les buts et HDM des matchs sans score sont protégés par RLS'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.historical_unscored_match_contributions',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'public.historical_unscored_match_contributions',
    'SELECT'
  ),
  'les matchs sans score ne se lisent pas directement'
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

-- Classement importé : le total de carrière de l'archive, dont la ligne
-- Carrière de la vue part. Il vaut la somme de l'archive et des matchs sans
-- score ci-dessous.
insert into public.historical_player_statistics(
  id, scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets, player_id
)
values (
  987654329002,
  'all_time', null, 998, 'Evolution Testeur', false,
  3, 1, 1, 1, 6, 3, 0, 'f1000000-0000-0000-0000-000000000001'
);

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

-- Matchs officiels sans score : buts et HDM comptés par le classement, sans
-- match joué. L'un tombe dans une saison déjà jouée, l'autre seul dans la
-- sienne.
insert into public.historical_unscored_match_contributions(
  match_date, opponent_name, match_type, player_id, goals, is_motm
)
values
  (date '2097-05-20', 'Adversaire test évolution', 'amical',
   'f1000000-0000-0000-0000-000000000001', 2, true),
  (date '2097-09-10', 'Adversaire test évolution', 'championnat',
   'f1000000-0000-0000-0000-000000000001', 0, true);

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
  array['2095-2096', '2096-2097', '2097-2098', '2098-2099'],
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
  '2/1/0/1/5/2',
  'archive et match sans score de la saison s’additionnent ; un absent ne compte pas'
);

select is(
  pg_temp.season_line(
    'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001',
    '2097-2098'
  ),
  '0/0/0/0/0/1',
  'un match sans score donne ses buts et son HDM, jamais un match joué'
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
  '2/1/0/1/5/2',
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

create or replace function pg_temp.season_totals(
  p_full_name text,
  p_is_goalkeeper boolean,
  p_profile_id uuid
)
returns text
language sql
stable
as $function$
  select concat_ws(
    '/', sum(s.matches_played), sum(s.wins), sum(s.draws), sum(s.losses),
    sum(s.goals), sum(s.hdm)
  )
  from public.get_player_season_statistics(
    p_full_name, p_is_goalkeeper, p_profile_id
  ) s;
$function$;

create or replace function pg_temp.career_line(p_is_goalkeeper boolean)
returns text
language sql
stable
as $function$
  select concat_ws(
    '/', v.matches_played, v.wins, v.draws, v.losses, v.goals, v.hdm
  )
  from public.v_statistics_players v
  where v.period_key = 'all_time'
    and v.player_name = 'Evolution Testeur'
    and v.is_goalkeeper = p_is_goalkeeper;
$function$;

select is(
  pg_temp.season_totals(
    'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001'
  ),
  pg_temp.career_line(false),
  'la somme des saisons retombe exactement sur la ligne Carrière'
);

reset role;

-- Un admin passe le joueur « Gardien » dans l'effectif de la saison : la vue
-- en fait une seconde ligne Carrière, à part de l'archive. Chaque fiche doit
-- retomber sur sa propre ligne, sans additionner l'autre.
update public.season_players
set is_goalkeeper = true
where id = 'f4000000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- Les deux lignes portent le même compte : la fiche ouverte par le compte
-- affiche la plus fournie en matchs, ici celle de l'archive.
select is(
  pg_temp.season_totals(
    'Evolution Testeur', false, 'f2000000-0000-0000-0000-000000000001'
  ),
  pg_temp.career_line(false),
  'par le compte, la fiche suit la ligne la plus fournie, sans l’autre poste'
);

select is(
  pg_temp.season_totals('Evolution Testeur', false, null),
  pg_temp.career_line(false),
  'par le nom et le poste de champ, la fiche suit l’archive seule'
);

select is(
  pg_temp.season_totals('Evolution Testeur', true, null),
  pg_temp.career_line(true),
  'par le nom et le poste de gardien, la fiche suit l’effectif seul'
);

select is(
  (
    select array_agg(s.season_name order by s.season_name)
    from public.get_player_season_statistics('Evolution Testeur', false, null) s
  ),
  array['2095-2096', '2096-2097', '2097-2098'],
  'la saison jouée à l’autre poste n’apparaît pas sur la ligne de champ'
);

reset role;

update public.season_players
set is_goalkeeper = false
where id = 'f4000000-0000-0000-0000-000000000001';

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

-- Un admin retape le nom avec d'autres majuscules dans un effectif : la vue
-- regroupe les effectifs sur le nom exact et en fait une autre ligne
-- Carrière. La fiche suit la sienne, sans additionner l'autre.
insert into public.season_players(
  id, season_id, player_id, first_name, last_name,
  is_goalkeeper, is_active, position
)
values (
  'f4000000-0000-0000-0000-000000000002',
  'f3000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'evolution',
  'testeur',
  false,
  true,
  2
);

insert into public.match_attendance(match_id, season_player_id)
values (
  'f7000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000002'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select count(*)::integer
    from public.v_statistics_players
    where period_key = 'all_time'
      and lower(player_name) = 'evolution testeur'
      and not is_goalkeeper
  ),
  2,
  'la vue fait deux lignes Carrière pour deux saisies du nom'
);

select is(
  pg_temp.season_totals('Evolution Testeur', false, null),
  (
    select concat_ws(
      '/', v.matches_played, v.wins, v.draws, v.losses, v.goals, v.hdm
    )
    from public.v_statistics_players v
    where v.period_key = 'all_time'
      and lower(v.player_name) = 'evolution testeur'
      and not v.is_goalkeeper
    order by v.matches_played desc, v.goals desc
    limit 1
  ),
  'la fiche suit sa ligne, sans l’effectif saisi avec d’autres majuscules'
);

reset role;

delete from public.match_attendance
where season_player_id = 'f4000000-0000-0000-0000-000000000002';
delete from public.season_players
where id = 'f4000000-0000-0000-0000-000000000002';

-- Rattacher un compte à sa fiche d'archive fusionne deux identités : les
-- matchs sans score suivent l'identité gardée.
insert into public.players(id, display_name)
values
  ('f1000000-0000-0000-0000-000000000004', 'Fusion Source'),
  ('f1000000-0000-0000-0000-000000000005', 'Fusion Cible'),
  ('f1000000-0000-0000-0000-000000000006', 'Fusion Double Source'),
  ('f1000000-0000-0000-0000-000000000007', 'Fusion Double Cible');

insert into public.historical_unscored_match_contributions(
  match_date, opponent_name, match_type, player_id, goals, is_motm
)
values
  (date '2097-05-20', 'Adversaire test évolution', 'amical',
   'f1000000-0000-0000-0000-000000000004', 1, false),
  (date '2097-05-20', 'Adversaire test évolution', 'amical',
   'f1000000-0000-0000-0000-000000000006', 1, false),
  (date '2097-05-20', 'Adversaire test évolution', 'amical',
   'f1000000-0000-0000-0000-000000000007', 0, true);

select private.merge_player_identities(
  'f1000000-0000-0000-0000-000000000004',
  'f1000000-0000-0000-0000-000000000005'
);

select is(
  (
    select player_id
    from public.historical_unscored_match_contributions
    where match_date = date '2097-05-20' and goals = 1 and not is_motm
      and player_id in (
        'f1000000-0000-0000-0000-000000000004',
        'f1000000-0000-0000-0000-000000000005'
      )
  ),
  'f1000000-0000-0000-0000-000000000005'::uuid,
  'la fusion déplace les matchs sans score vers l’identité gardée'
);

select ok(
  not exists (
    select 1 from public.players
    where id = 'f1000000-0000-0000-0000-000000000004'
  ),
  'l’identité fusionnée disparaît'
);

select throws_ok(
  $$select private.merge_player_identities(
    'f1000000-0000-0000-0000-000000000006',
    'f1000000-0000-0000-0000-000000000007'
  )$$,
  '23514',
  'deux identités élues le même jour sans score demandent une résolution manuelle'
);

-- Un compte déjà rattaché à une fiche d'archive ne peut pas en recevoir une
-- seconde : leurs archives match par match se mêleraient sans retour.
insert into public.players(id, display_name)
values
  ('f1000000-0000-0000-0000-000000000008', 'Fusion Ligne Une'),
  ('f1000000-0000-0000-0000-000000000009', 'Fusion Ligne Deux');

insert into public.historical_player_statistics(
  id, scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets, player_id
)
values
  (987654329003, 'all_time', null, 997, 'Fusion Ligne Une', false,
   0, 0, 0, 0, 0, 0, 0, 'f1000000-0000-0000-0000-000000000008'),
  (987654329004, 'all_time', null, 996, 'Fusion Ligne Deux', false,
   0, 0, 0, 0, 0, 0, 0, 'f1000000-0000-0000-0000-000000000009');

select throws_ok(
  $$select private.merge_player_identities(
    'f1000000-0000-0000-0000-000000000009',
    'f1000000-0000-0000-0000-000000000008'
  )$$,
  '23514',
  'deux identités portant chacune une carrière importée ne fusionnent pas'
);

select * from finish();
rollback;
