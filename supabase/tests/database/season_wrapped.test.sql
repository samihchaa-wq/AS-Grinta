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

select finish();
rollback;
