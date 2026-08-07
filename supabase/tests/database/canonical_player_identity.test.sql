begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(to_regclass('public.players') is not null, 'players est le registre canonique');
select ok(to_regclass('public.player_aliases') is not null, 'les alias de joueur sont conservés');
select ok(to_regclass('public.historical_match_players') is not null, 'les joueurs des archives sont normalisés');
select ok(to_regclass('public.historical_player_name_links') is not null, 'les noms des archives ont une résolution durable');

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'player_id'
  ),
  'profiles pointe vers players'
);
select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'season_players' and column_name = 'player_id' and is_nullable = 'NO'
  ),
  'season_players possède un player_id obligatoire'
);
select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'guest_players' and column_name = 'player_id' and is_nullable = 'NO'
  ),
  'guest_players possède un player_id obligatoire'
);
select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'historical_player_statistics' and column_name = 'player_id' and is_nullable = 'NO'
  ),
  'les statistiques historiques possèdent un player_id obligatoire'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'ca100000-0000-0000-0000-000000000001',
    'canonical-admin@example.invalid',
    '{"first_name":"Compte","last_name":"Cible"}'::jsonb
  ),
  (
    'ca100000-0000-0000-0000-000000000002',
    'canonical-twin-one@example.invalid',
    '{"first_name":"Même","last_name":"Nom"}'::jsonb
  ),
  (
    'ca100000-0000-0000-0000-000000000003',
    'canonical-twin-two@example.invalid',
    '{"first_name":"Même","last_name":"Nom"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'ca100000-0000-0000-0000-000000000001'::uuid then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'ca100000-0000-0000-0000-000000000001'::uuid,
  'ca100000-0000-0000-0000-000000000002'::uuid,
  'ca100000-0000-0000-0000-000000000003'::uuid
);

select ok(
  not exists (
    select 1 from public.profiles
    where id in (
      'ca100000-0000-0000-0000-000000000001'::uuid,
      'ca100000-0000-0000-0000-000000000002'::uuid,
      'ca100000-0000-0000-0000-000000000003'::uuid
    ) and player_id is null
  ),
  'tout nouveau profil réel reçoit automatiquement une identité canonique'
);

select isnt(
  (select player_id from public.profiles where id = 'ca100000-0000-0000-0000-000000000002'::uuid),
  (select player_id from public.profiles where id = 'ca100000-0000-0000-0000-000000000003'::uuid),
  'deux comptes homonymes restent deux personnes distinctes'
);

insert into public.seasons(id, name, status)
values ('ca200000-0000-0000-0000-000000000001', '2095-2096', 'open');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position
)
values (
  'ca300000-0000-0000-0000-000000000001',
  'ca200000-0000-0000-0000-000000000001',
  'Alias', 'Terrain', false, true, 1
);

select ok(
  (select player_id is not null from public.season_players where id = 'ca300000-0000-0000-0000-000000000001'::uuid),
  'un joueur sans compte reçoit sa propre identité canonique'
);

insert into public.historical_player_statistics(
  id, scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets
)
values (
  987654321001,
  'all_time', null, 999, 'Alias Terrain', false,
  1, 1, 0, 0, 0, 0, 0
);

select is(
  (select player_id from public.historical_player_statistics where id = 987654321001),
  (select player_id from public.season_players where id = 'ca300000-0000-0000-0000-000000000001'::uuid),
  'une correspondance exacte non ambiguë réutilise la même identité'
);

insert into public.historical_player_statistics(
  id, scope, season_name, display_rank, player_name, is_goalkeeper,
  matches_played, wins, draws, losses, goals, hdm, clean_sheets
)
values (
  987654321002,
  'all_time', null, 999, 'Même Nom', false,
  1, 0, 1, 0, 0, 0, 0
);

select ok(
  (select h.player_id from public.historical_player_statistics h where h.id = 987654321002)
    <> all (
      select p.player_id
      from public.profiles p
      where p.id in (
        'ca100000-0000-0000-0000-000000000002'::uuid,
        'ca100000-0000-0000-0000-000000000003'::uuid
      )
    ),
  'un nom homonyme ambigu ne fusionne avec aucun compte existant'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ca100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.staff_set_season_player_profile(
    'ca300000-0000-0000-0000-000000000001'::uuid,
    'ca100000-0000-0000-0000-000000000001'::uuid
  ),
  'un lien explicite compte/effectif fusionne les identités'
);

reset role;

select is(
  (select player_id from public.season_players where id = 'ca300000-0000-0000-0000-000000000001'::uuid),
  (select player_id from public.profiles where id = 'ca100000-0000-0000-0000-000000000001'::uuid),
  'le joueur de saison pointe ensuite vers l’identité du compte'
);

select is(
  (select player_id from public.historical_player_statistics where id = 987654321001),
  (select player_id from public.profiles where id = 'ca100000-0000-0000-0000-000000000001'::uuid),
  'la fusion explicite suit aussi les statistiques historiques déjà rattachées au joueur'
);

select is(
  (
    select count(distinct player_id)
    from public.player_aliases
    where private.normalize_player_name(alias) in (
      private.normalize_player_name('Compte Cible'),
      private.normalize_player_name('Alias Terrain')
    )
  ),
  1::bigint,
  'les deux noms restent des alias d’une seule personne'
);

-- Un nouvel archive utilise le registre durable et ignore le faux emplacement
-- « Poste laissé vide ».
insert into public.opponents(id, name)
values ('ca400000-0000-0000-0000-000000000001', 'Adversaire archive canonique');

insert into public.historical_match_scores(
  id, opponent_id, match_date, score_as_grinta, score_adverse, is_home
)
values (
  'ca500000-0000-0000-0000-000000000001',
  'ca400000-0000-0000-0000-000000000001',
  date '2095-09-01', 2, 0, true
);

insert into public.historical_match_details(
  match_id, formation, field_players, bench_players, present_names, scorers, motm_names
)
values (
  'ca500000-0000-0000-0000-000000000001',
  'test',
  '[{"name":"Alias Terrain","is_gk":false,"x_pct":50,"y_pct":50},{"name":"Poste laissé vide","is_gk":false,"x_pct":10,"y_pct":10}]'::jsonb,
  '[]'::jsonb,
  '["Alias Terrain"]'::jsonb,
  '[{"name":"Alias Terrain","goals":2}]'::jsonb,
  '["Alias Terrain"]'::jsonb
);

select is(
  (
    select count(*)
    from public.historical_match_players
    where match_id = 'ca500000-0000-0000-0000-000000000001'::uuid
  ),
  1::bigint,
  'un match archivé contient une seule personne canonique et aucun faux emplacement'
);

select is(
  (
    select player_id
    from public.historical_match_players
    where match_id = 'ca500000-0000-0000-0000-000000000001'::uuid
  ),
  (select player_id from public.profiles where id = 'ca100000-0000-0000-0000-000000000001'::uuid),
  'le joueur du match archivé réutilise exactement la même identité'
);

select is(
  (
    select goals
    from public.historical_match_players
    where match_id = 'ca500000-0000-0000-0000-000000000001'::uuid
  ),
  2,
  'les données sportives de l’archive restent attachées à cette identité'
);

select * from finish();
rollback;