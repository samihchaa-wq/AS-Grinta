begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Contrat de sécurité : le bilan est une donnée personnelle.
select ok(
  (select relrowsecurity from pg_class
    where oid = 'public.season_wrapped'::regclass),
  'season_wrapped est protegee par RLS'
);

select ok(
  not has_table_privilege('anon', 'public.season_wrapped', 'select'),
  'anon ne lit pas les bilans'
);

-- Socle commun a toutes les tables metier : hors compte authentifie et
-- actif, la table n existe pas.
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'season_wrapped'
      and policyname = 'active_authenticated_profile_only'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
      and roles = array['authenticated']::name[]
  ),
  'le bilan porte le socle de securite des tables metier'
);

select ok(
  has_table_privilege('authenticated', 'public.season_wrapped', 'select'),
  'authenticated peut lire ses propres bilans via RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.season_wrapped', 'insert'),
  'authenticated n ecrit jamais un bilan'
);

select ok(
  has_function_privilege(
    'authenticated', 'public.get_my_season_wrapped()', 'execute'
  ),
  'authenticated peut demander son bilan'
);

select ok(
  not has_function_privilege(
    'anon', 'public.get_my_season_wrapped()', 'execute'
  ),
  'anon ne demande pas de bilan'
);

select ok(
  not has_function_privilege(
    'authenticated', 'private.build_season_wrapped(uuid)', 'execute'
  ),
  'le calcul du bilan reste interne'
);

-- Les saisons anterieures viennent de l archive importee : pas de bilan.
insert into public.seasons (id, name, status)
values
  ('7f000000-0000-0000-0000-000000000001', '2013-2014', 'archived'),
  ('7f000000-0000-0000-0000-000000000002', '2098-2099', 'open');

select is(
  private.season_wrapped_is_supported(
    '7f000000-0000-0000-0000-000000000001'
  ),
  false,
  'une saison anterieure a 2026-2027 n a pas de bilan'
);

select is(
  private.season_wrapped_is_supported(
    '7f000000-0000-0000-0000-000000000002'
  ),
  true,
  'une saison jouee dans l application a un bilan'
);

-- La cloture depose une demande de calcul.
update public.seasons
set status = 'archived'
where id = '7f000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::integer from private.season_wrapped_jobs
    where season_id = '7f000000-0000-0000-0000-000000000002'),
  1,
  'la cloture d une saison demande le calcul du bilan'
);

-- Une saison sans match donne un bilan vide, sans erreur.
select is(
  private.build_season_wrapped('7f000000-0000-0000-0000-000000000002'),
  0,
  'une saison sans match ne produit aucun bilan'
);

-- Une reouverture efface un bilan devenu faux.
insert into public.season_players (
  id, season_id, first_name, last_name, is_active
)
values (
  '7f000000-0000-0000-0000-0000000000a1',
  '7f000000-0000-0000-0000-000000000002',
  'Bilan',
  'Tests',
  true
);

insert into public.season_wrapped (
  season_id, season_player_id, roster_size, matches_played,
  wins, draws, losses, goals, motm, clean_matches, versatility
)
values (
  '7f000000-0000-0000-0000-000000000002',
  '7f000000-0000-0000-0000-0000000000a1',
  1, 1, 1, 0, 0, 0, 0, 0, 0
);

update public.seasons
set status = 'open'
where id = '7f000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::integer from public.season_wrapped
    where season_id = '7f000000-0000-0000-0000-000000000002'),
  0,
  'rouvrir une saison efface le bilan devenu faux'
);

-- Les parts par poste totalisent exactement cent.
--
-- Cas qui donnait 101 avant correction : huit titularisations reparties
-- 3 au milieu, 3 en attaque et 2 en defense centrale, soit les parts
-- exactes 37,5 + 37,5 + 25 que trois arrondis independants portaient a
-- 38 + 38 + 25.
insert into auth.users (id, email, raw_user_meta_data)
values (
  '7f000000-0000-0000-0000-0000000000f1',
  'bilan-parts@example.invalid',
  '{"first_name":"Parts","last_name":"Bilan"}'::jsonb
);

-- La base n autorise qu une seule saison ouverte : celle du test de
-- reouverture ci-dessus. Cette saison de calcul naît donc archivee.
insert into public.seasons (id, name, status)
values ('7f000000-0000-0000-0000-000000000003', '2099-2100', 'archived');

insert into public.season_players (
  id, season_id, first_name, last_name, is_active
)
values (
  '7f000000-0000-0000-0000-0000000000b1',
  '7f000000-0000-0000-0000-000000000003',
  'Parts',
  'Postes',
  true
);

-- Les matchs naissent a venir : la composition d un match termine est
-- immuable, elle doit donc etre posee avant la cloture.
insert into public.matches (
  id, season_id, match_type, status, kickoff_at,
  match_date, match_time, location, planned_duration_minutes, created_by
)
select
  ('7f000000-0000-0000-0000-0000000000c' || n)::uuid,
  '7f000000-0000-0000-0000-000000000003',
  'entre_nous', 'a_venir', now() - (n || ' days')::interval,
  ((now() - (n || ' days')::interval) at time zone 'Europe/Paris')::date,
  ((now() - (n || ' days')::interval) at time zone 'Europe/Paris')::time,
  'domicile', 90, '7f000000-0000-0000-0000-0000000000f1'
from generate_series(1, 8) n;

-- Les participants s accrochent au suivi sportif du match, pas au match.
insert into public.match_sport_workflows (
  match_id, availability_opens_at, created_by, updated_by
)
select
  ('7f000000-0000-0000-0000-0000000000c' || n)::uuid,
  now() - ((n + 6) || ' days')::interval,
  '7f000000-0000-0000-0000-0000000000f1',
  '7f000000-0000-0000-0000-0000000000f1'
from generate_series(1, 8) n;

insert into public.match_sport_participants (id, match_id, season_player_id)
select
  ('7f000000-0000-0000-0000-0000000000d' || n)::uuid,
  ('7f000000-0000-0000-0000-0000000000c' || n)::uuid,
  '7f000000-0000-0000-0000-0000000000b1'
from generate_series(1, 8) n;

-- Les entrees de composition s accrochent a la composition du match.
insert into public.match_compositions (match_id, last_modified_by)
select
  ('7f000000-0000-0000-0000-0000000000c' || n)::uuid,
  '7f000000-0000-0000-0000-0000000000f1'
from generate_series(1, 8) n;

-- Trois fois milieu, trois fois attaquant, deux fois defenseur central,
-- poses sur les coordonnees exactes de ces emplacements.
insert into public.match_composition_entries (
  match_id, participant_id, zone, x, y
)
select
  ('7f000000-0000-0000-0000-0000000000c' || n)::uuid,
  ('7f000000-0000-0000-0000-0000000000d' || n)::uuid,
  'field'::public.sport_composition_zone,
  0.50,
  case when n <= 3 then 0.40 when n <= 6 then 0.08 else 0.72 end
from generate_series(1, 8) n;

-- Present a chacun des huit matchs, puis cloture.
insert into public.match_attendance (match_id, season_player_id)
select
  ('7f000000-0000-0000-0000-0000000000c' || n)::uuid,
  '7f000000-0000-0000-0000-0000000000b1'
from generate_series(1, 8) n;

update public.matches
set status = 'termine', score_as_grinta = 1, score_adverse = 0
where season_id = '7f000000-0000-0000-0000-000000000003';

select is(
  private.build_season_wrapped('7f000000-0000-0000-0000-000000000003'),
  1,
  'la saison fabriquee produit un bilan'
);

select is(
  (
    select sum((part->>'share')::integer)::integer
    from public.season_wrapped wrapped,
      lateral jsonb_array_elements(wrapped.position_shares) part
    where wrapped.season_id = '7f000000-0000-0000-0000-000000000003'
  ),
  100,
  'les parts par poste totalisent exactement cent'
);

select is(
  (
    select wrapped.position_shares
    from public.season_wrapped wrapped
    where wrapped.season_id = '7f000000-0000-0000-0000-000000000003'
  ),
  '[{"share": 38, "position": "Attaquant"},
    {"share": 37, "position": "Milieu"},
    {"share": 25, "position": "D\u00e9fenseur central"}]'::jsonb,
  'l unite en trop va au poste le mieux classe, les autres parts sont intactes'
);

select finish();
rollback;
