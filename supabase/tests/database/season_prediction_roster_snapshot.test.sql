begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.season_prediction_roster_captures') is not null
  and to_regclass('public.season_prediction_roster_members') is not null,
  'les tables du snapshot existent'
);

select ok(
  (
    select bool_and(relrowsecurity)
    from pg_class
    where oid in (
      'public.season_prediction_roster_captures'::regclass,
      'public.season_prediction_roster_members'::regclass
    )
  ),
  'RLS est activee sur les snapshots'
);

select ok(
  has_table_privilege(
    'authenticated',
    'public.season_prediction_roster_members',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.season_prediction_roster_members',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.season_prediction_roster_members',
    'UPDATE'
  ),
  'un joueur peut lire mais pas reecrire le snapshot'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'c9100000-0000-0000-0000-000000000001',
    'season-snapshot-admin@example.invalid',
    '{"first_name":"Admin Snapshot"}'::jsonb
  ),
  (
    'c9100000-0000-0000-0000-000000000002',
    'season-snapshot-player@example.invalid',
    '{"first_name":"Prono Snapshot"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'c9100000-0000-0000-0000-000000000001'
        then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'c9100000-0000-0000-0000-000000000001',
  'c9100000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status, season_predictions_locked_at)
values (
  'c9200000-0000-0000-0000-000000000001',
  '2098-2099',
  'open',
  null
);

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'c9300000-0000-0000-0000-000000000001',
    'c9200000-0000-0000-0000-000000000001',
    'Buteur', 'Snapshot', false, true, 1,
    'c9100000-0000-0000-0000-000000000002'
  ),
  (
    'c9300000-0000-0000-0000-000000000002',
    'c9200000-0000-0000-0000-000000000001',
    'Gardien', 'Snapshot', true, true, 2,
    null
  ),
  (
    'c9300000-0000-0000-0000-000000000003',
    'c9200000-0000-0000-0000-000000000001',
    'Archive', 'AvantLock', false, true, 3,
    null
  );

-- Le seed cree deja les lignes. Le pronostiqueur remplit toute la grille tant
-- que les trois joueurs sont actifs. Zero permet de tester le calcul archive
-- sans introduire de fixture Match sans rapport avec le contrat vise ici.
update public.season_predictions
set predicted_value_30 = 0,
    is_filled = true,
    updated_at = now()
where season_id = 'c9200000-0000-0000-0000-000000000001'
  and predictor_profile_id = 'c9100000-0000-0000-0000-000000000002'
  and season_player_id in (
    'c9300000-0000-0000-0000-000000000001',
    'c9300000-0000-0000-0000-000000000002',
    'c9300000-0000-0000-0000-000000000003'
  );

-- Le troisieme joueur est archive avant le verrou : son ancien prono rempli
-- ne doit pas le faire entrer dans le futur contrat fige.
update public.season_players
set is_active = false
where id = 'c9300000-0000-0000-0000-000000000003';

select set_config(
  'request.jwt.claims',
  '{"sub":"c9100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.set_season_predictions_lock(
    'c9200000-0000-0000-0000-000000000001'::uuid,
    true
  ),
  'le lock reussit'
);

reset role;

select is(
  (
    select count(*)
    from public.season_prediction_roster_members
    where season_id = 'c9200000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'le lock fige seulement les deux joueurs encore actifs'
);

select ok(
  exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000001'
      and category = 'buts'
  )
  and exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000002'
      and category = 'clean_sheets'
  )
  and not exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000003'
  ),
  'le snapshot fige le perimetre et les categories'
);

-- Apres le lock, reactivation et archivage restent des choix d'effectif mais
-- ne doivent plus modifier le contrat des pronostics.
update public.season_players
set is_active = true
where id = 'c9300000-0000-0000-0000-000000000003';

update public.season_players
set is_active = false
where id = 'c9300000-0000-0000-0000-000000000002';

select ok(
  exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000002'
  )
  and not exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000003'
  ),
  'les changements is_active apres lock ne reecrivent pas le snapshot'
);

update public.seasons
set status = 'archived'
where id = 'c9200000-0000-0000-0000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"c9100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select count(*)
    from public.v_season_prediction_points
    where season_id = 'c9200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'c9100000-0000-0000-0000-000000000002'
  ),
  2::bigint,
  'seuls les deux membres figes produisent des points'
);

select is(
  (
    select coalesce(sum(points), 0)
    from public.v_season_prediction_points
    where season_id = 'c9200000-0000-0000-0000-000000000001'
      and predictor_profile_id = 'c9100000-0000-0000-0000-000000000002'
  ),
  12::bigint,
  'deux pronostics exacts a zero valent 12 points au total'
);

select ok(
  not exists (
    select 1
    from public.v_season_prediction_points
    where season_id = 'c9200000-0000-0000-0000-000000000001'
      and season_player_id = 'c9300000-0000-0000-0000-000000000003'
  ),
  'le joueur reactive apres lock reste exclu malgre son ancien prono rempli'
);

reset role;

select throws_ok(
  $$
    update public.season_players
    set is_goalkeeper = false
    where id = 'c9300000-0000-0000-0000-000000000002'
  $$,
  '23514',
  'Season prediction roster is frozen; season/category cannot be changed',
  'la categorie d un membre fige ne peut pas etre modifiee'
);

select throws_ok(
  $$
    delete from public.season_players
    where id = 'c9300000-0000-0000-0000-000000000002'
  $$,
  '23514',
  'Season prediction roster is frozen; archived prediction members cannot be deleted',
  'un membre fige ne peut pas etre supprime directement'
);

-- Une reouverture explicite efface le contrat precedent. Le prochain lock
-- capture alors le nouvel effectif actif : Buteur + Archive.
update public.seasons
set status = 'open',
    season_predictions_locked_at = null
where id = 'c9200000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.season_prediction_roster_captures
    where season_id = 'c9200000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'deverrouiller efface le snapshot precedent'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c9100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.set_season_predictions_lock(
    'c9200000-0000-0000-0000-000000000001'::uuid,
    true
  ),
  'le second lock reussit'
);

reset role;

select ok(
  exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000001'
  )
  and exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000003'
  )
  and not exists (
    select 1
    from public.season_prediction_roster_members
    where season_player_id = 'c9300000-0000-0000-0000-000000000002'
  ),
  'un nouveau lock recapture le nouvel effectif actif'
);

select * from finish();
rollback;
