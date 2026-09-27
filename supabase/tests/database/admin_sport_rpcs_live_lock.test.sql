begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Les huit actions sportives d'administration se verrouillent à l'ouverture
-- du Live (T-15), comme en production. Pour chacune : un joueur est refusé,
-- un administrateur est refusé une fois le Live ouvert, et le même
-- administrateur est accepté avant.

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_add_or_reuse_match_guest(uuid,uuid,text,text,boolean,text)',
      'public.admin_configure_match_sport_workflow(uuid,integer)',
      'public.admin_override_match_availability(uuid,uuid,text,text,text)',
      'public.admin_publish_match_convocations(uuid,text)',
      'public.admin_recompute_match_convocations(uuid,boolean)',
      'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
      'public.admin_set_match_convocation(uuid,uuid,text,boolean,text)',
      'public.admin_sync_match_sport_workflow(uuid)'
    ]::text[]) expected(signature)
    join pg_proc p on p.oid = to_regprocedure(expected.signature)
    join pg_language l on l.oid = p.prolang
    where p.prosecdef
      and l.lanname = 'plpgsql'
      and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  8::bigint,
  'les huit RPC sont plpgsql, SECURITY DEFINER, à search_path vide et fermées au rôle anonyme'
);

select ok(
  has_function_privilege(
    'service_role',
    'private.assert_match_admin_edit_open(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.assert_match_admin_edit_open(uuid)',
    'EXECUTE'
  ),
  'le contrôle du verrou garde les droits de la production : service_role oui, anonyme non'
);

insert into auth.users(id, email, raw_user_meta_data) values
('7a000000-0000-0000-0000-000000000001','live-lock-admin@example.invalid','{"first_name":"Verrou","last_name":"Admin"}'::jsonb),
('7a000000-0000-0000-0000-000000000002','live-lock-player@example.invalid','{"first_name":"Verrou","last_name":"Joueur"}'::jsonb);

update public.profiles
set role = case when id = '7a000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status = 'active',
    updated_at = now()
where id in ('7a000000-0000-0000-0000-000000000001','7a000000-0000-0000-0000-000000000002');

insert into public.seasons(id, name, status)
values ('7a000000-0000-0000-0000-000000000010', '2098-2099', 'open');

insert into public.opponents(id, name) values
('7a000000-0000-0000-0000-000000000011','Verrou Ouvert FC'),
('7a000000-0000-0000-0000-000000000012','Verrou Live FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values (
  '7a000000-0000-0000-0000-000000000021',
  '7a000000-0000-0000-0000-000000000010',
  'Verrou', 'Joueur', false, true, 1,
  '7a000000-0000-0000-0000-000000000002'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '7a000000-0000-0000-0000-000000000001'
where key = 'sports_management';

-- Match dont le Live est ouvert : coup d'envoi dans dix minutes, donc après
-- T-15. Le verrou tombe avant toute autre vérification : la ligne du match
-- suffit.
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, match_type, created_by
) values (
  '7a000000-0000-0000-0000-000000000031',
  '7a000000-0000-0000-0000-000000000010',
  '7a000000-0000-0000-0000-000000000012',
  ((now() + interval '10 minutes') at time zone 'Europe/Paris')::date,
  ((now() + interval '10 minutes') at time zone 'Europe/Paris')::time,
  'domicile', 90, 'a_venir', 'championnat',
  '7a000000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"7a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- Match ouvert : coup d'envoi dans trois jours, disponibilités déjà ouvertes.
select set_config(
  'test.lock_open_match',
  public.create_match_with_odds_and_sport_limit(
    '7a000000-0000-0000-0000-000000000010',
    '7a000000-0000-0000-0000-000000000011',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;

-- ---------------------------------------------------------------------------
-- 1. Un joueur est refusé
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"7a000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_sync_match_sport_workflow(current_setting('test.lock_open_match')::uuid)$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas synchroniser le suivi sportif'
);
select throws_ok(
  $$select public.admin_configure_match_sport_workflow(current_setting('test.lock_open_match')::uuid, 14)$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas configurer le suivi sportif'
);
select throws_ok(
  $$select public.admin_override_match_availability(
    current_setting('test.lock_open_match')::uuid,
    '7a000000-0000-0000-0000-000000000021', 'available', null, 'Tentative joueur')$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas corriger une disponibilité'
);
select throws_ok(
  $$select public.admin_recompute_match_convocations(current_setting('test.lock_open_match')::uuid, false)$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas recalculer les convocations'
);
select throws_ok(
  $$select public.admin_set_match_convocation(
    current_setting('test.lock_open_match')::uuid,
    '7a000000-0000-0000-0000-000000000021', 'convoked', true, 'Tentative joueur')$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas modifier une convocation'
);
select throws_ok(
  $$select public.admin_publish_match_convocations(current_setting('test.lock_open_match')::uuid, 'Tentative joueur')$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas publier les convocations'
);
select throws_ok(
  $$select public.admin_add_or_reuse_match_guest(
    current_setting('test.lock_open_match')::uuid, null, 'Invité', 'Refusé', false, 'Tentative joueur')$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas ajouter un invité'
);
select throws_ok(
  $$select public.admin_save_match_effectif(
    current_setting('test.lock_open_match')::uuid, 14,
    '[{"season_player_id":"7a000000-0000-0000-0000-000000000021","status":"convoked"}]'::jsonb,
    'Tentative joueur')$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas enregistrer l’effectif'
);

reset role;

-- ---------------------------------------------------------------------------
-- 2. Un administrateur est refusé une fois le Live ouvert
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"7a000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_sync_match_sport_workflow('7a000000-0000-0000-0000-000000000031')$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'le suivi sportif ne se synchronise plus après T-15'
);
select throws_ok(
  $$select public.admin_configure_match_sport_workflow('7a000000-0000-0000-0000-000000000031', 14)$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'le suivi sportif ne se configure plus après T-15'
);
select throws_ok(
  $$select public.admin_override_match_availability(
    '7a000000-0000-0000-0000-000000000031',
    '7a000000-0000-0000-0000-000000000021', 'available', null, 'Après T-15')$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'une disponibilité ne se corrige plus après T-15'
);
select throws_ok(
  $$select public.admin_recompute_match_convocations('7a000000-0000-0000-0000-000000000031', false)$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'les convocations ne se recalculent plus après T-15'
);
select throws_ok(
  $$select public.admin_set_match_convocation(
    '7a000000-0000-0000-0000-000000000031',
    '7a000000-0000-0000-0000-000000000021', 'convoked', true, 'Après T-15')$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'une convocation ne se modifie plus après T-15'
);
select throws_ok(
  $$select public.admin_publish_match_convocations('7a000000-0000-0000-0000-000000000031', 'Après T-15')$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'les convocations ne se publient plus après T-15'
);
select throws_ok(
  $$select public.admin_add_or_reuse_match_guest(
    '7a000000-0000-0000-0000-000000000031', null, 'Invité', 'Tardif', false, 'Après T-15')$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'un invité ne s’ajoute plus par cette action après T-15'
);
select throws_ok(
  $$select public.admin_save_match_effectif(
    '7a000000-0000-0000-0000-000000000031', 14,
    '[{"season_player_id":"7a000000-0000-0000-0000-000000000021","status":"convoked"}]'::jsonb,
    'Après T-15')$$,
  '22023', 'Le match est verrouillé depuis l’ouverture du Live.',
  'l’effectif ne s’enregistre plus après T-15'
);

-- ---------------------------------------------------------------------------
-- 3. Le même administrateur est accepté avant T-15
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.admin_sync_match_sport_workflow(current_setting('test.lock_open_match')::uuid)$$,
  'l’administrateur synchronise le suivi sportif avant T-15'
);
select lives_ok(
  $$select public.admin_configure_match_sport_workflow(current_setting('test.lock_open_match')::uuid, 14)$$,
  'l’administrateur configure le suivi sportif avant T-15'
);
select lives_ok(
  $$select public.admin_override_match_availability(
    current_setting('test.lock_open_match')::uuid,
    '7a000000-0000-0000-0000-000000000021', 'available', null, 'Présence confirmée')$$,
  'l’administrateur corrige une disponibilité avant T-15'
);
select lives_ok(
  $$select public.admin_recompute_match_convocations(current_setting('test.lock_open_match')::uuid, false)$$,
  'l’administrateur recalcule les convocations avant T-15'
);
select lives_ok(
  $$select public.admin_set_match_convocation(
    current_setting('test.lock_open_match')::uuid,
    '7a000000-0000-0000-0000-000000000021', 'convoked', true, 'Convocation confirmée')$$,
  'l’administrateur modifie une convocation avant T-15'
);
select lives_ok(
  $$select public.admin_publish_match_convocations(current_setting('test.lock_open_match')::uuid, 'Publication')$$,
  'l’administrateur publie les convocations avant T-15'
);
select lives_ok(
  $$select public.admin_add_or_reuse_match_guest(
    current_setting('test.lock_open_match')::uuid, null, 'Invité', 'Accepté', false, 'Renfort')$$,
  'l’administrateur ajoute un invité avant T-15'
);
select lives_ok(
  $$select public.admin_save_match_effectif(
    current_setting('test.lock_open_match')::uuid, 14,
    '[{"season_player_id":"7a000000-0000-0000-0000-000000000021","status":"convoked"}]'::jsonb,
    'Effectif avant le Live')$$,
  'l’administrateur enregistre l’effectif avant T-15'
);

reset role;
select * from finish();
rollback;
