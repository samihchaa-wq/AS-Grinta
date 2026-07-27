begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'e4000000-0000-0000-0000-000000000001',
    'security-admin@example.invalid',
    '{"first_name":"Security","last_name":"Admin"}'::jsonb
  ),
  (
    'e4000000-0000-0000-0000-000000000002',
    'security-player@example.invalid',
    '{"first_name":"Security","last_name":"Player"}'::jsonb
  ),
  (
    'e4000000-0000-0000-0000-000000000003',
    'security-pending@example.invalid',
    '{"first_name":"Security","last_name":"Pending"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'e4000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = case
      when id = 'e4000000-0000-0000-0000-000000000003' then 'pending'
      else 'active'
    end,
    username = case
      when id = 'e4000000-0000-0000-0000-000000000001' then 'securityadmin'
      when id = 'e4000000-0000-0000-0000-000000000002' then 'securityplayer'
      else 'securitypending'
    end,
    updated_at = now()
where id in (
  'e4000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000002',
  'e4000000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('e4100000-0000-0000-0000-000000000001', '2120-2121', 'open');

insert into public.opponents(id, name)
values ('e4200000-0000-0000-0000-000000000001', 'Sécurité FC');

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by
)
values (
  'e4300000-0000-0000-0000-000000000001',
  'e4100000-0000-0000-0000-000000000001',
  'e4200000-0000-0000-0000-000000000001',
  date '2120-09-01', time '20:00', 'domicile', 90, 'a_venir',
  'e4000000-0000-0000-0000-000000000001'
);

select ok(
  not has_table_privilege('anon', 'public.matches', 'SELECT')
  and not has_table_privilege('anon', 'public.profiles', 'SELECT')
  and not has_function_privilege(
    'anon', 'public.close_match_predictions(uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'le visiteur ne reçoit ni droit de données ni RPC métier'
);

set local role anon;
select throws_ok(
  $$select count(*) from public.matches$$,
  '42501',
  'le visiteur ne peut pas lire les matchs'
);
select throws_ok(
  $$select public.close_match_predictions('e4300000-0000-0000-0000-000000000001')$$,
  '42501',
  'le visiteur ne peut pas appeler une RPC administrateur'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  private.is_active_profile(),
  false,
  'un compte en attente n’est jamais considéré actif'
);
select is(
  (select count(*) from public.matches),
  0::bigint,
  'un compte en attente ne lit aucun match malgré son JWT valide'
);
select is(
  (select count(*) from public.profiles),
  0::bigint,
  'un compte en attente ne lit aucun profil'
);
select throws_ok(
  $$select public.get_my_profile()$$,
  '42501',
  'le chargement de profil refuse explicitement un compte en attente'
);
select throws_ok(
  $$insert into public.push_subscriptions(
      profile_id, endpoint, p256dh, auth, user_agent
    ) values (
      'e4000000-0000-0000-0000-000000000003',
      'https://push.invalid/pending', 'key', 'secret', 'test'
    )$$,
  '42501',
  'un compte en attente ne peut pas enregistrer un appareil'
);
select throws_ok(
  $$select public.close_match_predictions('e4300000-0000-0000-0000-000000000001')$$,
  '42501',
  'un compte en attente ne peut pas lancer une action administrateur'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(private.is_active_profile(), true, 'un joueur validé est actif');
select is(private.is_admin(), false, 'un joueur validé ne devient pas administrateur');
select is(
  (select count(*) from public.matches),
  1::bigint,
  'un joueur actif lit les matchs'
);
select is(
  public.get_my_profile() #>> '{id}',
  'e4000000-0000-0000-0000-000000000002',
  'un joueur charge uniquement son profil actif'
);
select throws_ok(
  $$select public.close_match_predictions('e4300000-0000-0000-0000-000000000001')$$,
  '42501',
  'un joueur ne ferme pas les pronostics'
);
select throws_ok(
  $$select public.set_sports_management_enabled(true, 'attaque')$$,
  '42501',
  'un joueur ne modifie pas le feature flag sportif'
);
select throws_ok(
  $$update public.profiles
    set role = 'admin'
    where id = 'e4000000-0000-0000-0000-000000000002'$$,
  '42501',
  'un joueur ne peut pas s’accorder le rôle administrateur'
);
select is(
  (
    select role::text
    from public.profiles
    where id = 'e4000000-0000-0000-0000-000000000002'
  ),
  'pronostiqueur',
  'le rôle reste inchangé après la tentative d’élévation'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(private.is_active_profile(), true, 'l’administrateur validé est actif');
select is(private.is_admin(), true, 'le rôle administrateur est reconnu');
select is(
  (select count(*) from public.matches),
  1::bigint,
  'l’administrateur lit les matchs'
);
select ok(
  public.close_match_predictions('e4300000-0000-0000-0000-000000000001'),
  'l’administrateur exécute l’action protégée'
);
select is(
  (
    select predictions_closed_at is not null
    from public.matches
    where id = 'e4300000-0000-0000-0000-000000000001'
  ),
  true,
  'la fermeture administrateur est effectivement persistée'
);

reset role;
select * from finish();
rollback;
