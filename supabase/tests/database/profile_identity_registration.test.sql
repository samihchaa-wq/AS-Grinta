begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Une identité historique unique et encore sans compte doit être réutilisée.
insert into public.players(id, display_name)
values ('cb100000-0000-0000-0000-000000000001', 'Ancien Joueur');

insert into public.player_aliases(alias, player_id)
values ('Ancien Joueur', 'cb100000-0000-0000-0000-000000000001');

insert into auth.users(id, email, raw_user_meta_data)
values (
  'cb200000-0000-0000-0000-000000000001',
  'identity-reuse@example.invalid',
  '{"first_name":"Ancien","last_name":"Joueur"}'::jsonb
);

select is(
  (select player_id from public.profiles where id = 'cb200000-0000-0000-0000-000000000001'::uuid),
  'cb100000-0000-0000-0000-000000000001'::uuid,
  'une inscription réutilise l’unique identité existante non rattachée à un profil'
);

-- Un deuxième compte portant le même nom est un homonyme potentiel : il doit
-- recevoir une identité distincte plutôt que fusionner avec le premier compte.
insert into auth.users(id, email, raw_user_meta_data)
values (
  'cb200000-0000-0000-0000-000000000002',
  'identity-homonym@example.invalid',
  '{"first_name":"Ancien","last_name":"Joueur"}'::jsonb
);

select isnt(
  (select player_id from public.profiles where id = 'cb200000-0000-0000-0000-000000000002'::uuid),
  'cb100000-0000-0000-0000-000000000001'::uuid,
  'un second compte homonyme conserve une identité distincte'
);

select is(
  (
    select count(distinct pa.player_id)
    from public.player_aliases pa
    where private.normalize_player_name(pa.alias) = private.normalize_player_name('Ancien Joueur')
  ),
  2::bigint,
  'le registre conserve bien deux identités pour deux comptes homonymes'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'ensure_profile_player_identity'
  ),
  'le trigger de profil reste SECURITY DEFINER'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'find_reusable_profile_player_identity'
  ),
  'le helper de réutilisation est SECURITY DEFINER'
);

select ok(
  position(
    'pg_advisory_xact_lock' in (
      select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and p.proname = 'find_reusable_profile_player_identity'
    )
  ) > 0,
  'la recherche de candidat sérialise les inscriptions de même nom'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.find_reusable_profile_player_identity(text)',
    'EXECUTE'
  ),
  'authenticated ne peut pas appeler directement le helper privé'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.find_reusable_profile_player_identity(text)',
    'EXECUTE'
  ),
  'anon ne peut pas appeler directement le helper privé'
);

select * from finish();
rollback;
