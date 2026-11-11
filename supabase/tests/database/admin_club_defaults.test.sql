begin;
set local search_path = public, extensions, pg_catalog;
select plan(13);

-- Réglages du club : taille habituelle du groupe et adresse à domicile.
insert into auth.users(id,email,raw_user_meta_data) values
('c7100000-0000-0000-0000-000000000001','clubdef-admin@example.invalid','{"first_name":"Admin"}'::jsonb),
('c7100000-0000-0000-0000-000000000002','clubdef-player@example.invalid','{"first_name":"Joueur"}'::jsonb);

update public.profiles
set role = case when id = 'c7100000-0000-0000-0000-000000000001'
  then 'admin' else 'pronostiqueur' end,
  status = 'active', updated_at = now()
where id in (
'c7100000-0000-0000-0000-000000000001',
'c7100000-0000-0000-0000-000000000002');

select ok(
  not has_function_privilege(
    'anon', 'public.admin_get_club_defaults()', 'EXECUTE'
  ),
  'un visiteur anonyme ne lit pas les réglages du club'
);
select ok(
  not has_function_privilege(
    'anon', 'public.admin_set_club_defaults(integer,text)', 'EXECUTE'
  ),
  'un visiteur anonyme ne modifie pas les réglages du club'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.admin_set_club_defaults(integer,text)', 'EXECUTE'
  ),
  'le client authentifié garde la RPC, protégée par le contrôle admin interne'
);

-- Un joueur est refusé.
select set_config(
  'request.jwt.claims',
  '{"sub":"c7100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_club_defaults(12, 'Stade refusé')$$,
  '42501',
  null,
  'un joueur ne modifie pas les réglages du club'
);
select throws_ok(
  $$select public.admin_get_club_defaults()$$,
  '42501',
  null,
  'un joueur ne lit pas les réglages du club'
);
reset role;

-- Un admin les modifie.
select set_config(
  'request.jwt.claims',
  '{"sub":"c7100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_club_defaults(0, 'Stade')$$,
  '22023',
  null,
  'une taille de groupe nulle est refusée'
);
select throws_ok(
  $$select public.admin_set_club_defaults(31, 'Stade')$$,
  '22023',
  null,
  'une taille de groupe au-delà de 30 est refusée'
);
select throws_ok(
  $$select public.admin_set_club_defaults(null, 'Stade')$$,
  '22023',
  null,
  'la taille de groupe est obligatoire'
);
select is(
  public.admin_set_club_defaults(16, '  1 rue du Stade - 31000 Toulouse  '),
  jsonb_build_object(
    'usual_squad_size', 16,
    'home_address', '1 rue du Stade - 31000 Toulouse'
  ),
  'un admin enregistre la taille du groupe et l''adresse'
);
select is(
  public.admin_get_club_defaults(),
  jsonb_build_object(
    'usual_squad_size', 16,
    'home_address', '1 rue du Stade - 31000 Toulouse'
  ),
  'les réglages enregistrés sont relus'
);
reset role;

select is(
  private.resolve_match_squad_size_limit(null),
  16,
  'la taille par défaut des prochains matchs suit le réglage'
);
select is(
  (select home_address from public.club_settings where id),
  '1 rue du Stade - 31000 Toulouse',
  'l''adresse à domicile est mémorisée'
);

-- Une adresse vide efface l'adresse par défaut.
set local role authenticated;
select is(
  public.admin_set_club_defaults(16, '   ') ->> 'home_address',
  null,
  'une adresse vide efface l''adresse par défaut'
);
reset role;

select * from finish();
rollback;
