begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Un téléphone déclare son autorisation d'affichage et les notifications
-- qu'il a réellement montrées. Sans ce retour, un envoi accepté par Apple ou
-- Google passait pour reçu même quand rien ne s'était affiché.

select ok(
  not has_function_privilege(
    'anon',
    'public.report_my_push_device(text,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.report_my_push_device(text,text,jsonb)',
    'EXECUTE'
  ),
  'seul un compte connecté peut déclarer l’état de son téléphone'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'e4000000-0000-0000-0000-000000000001',
    'push-report-a@example.invalid',
    '{"first_name":"Report","last_name":"Alpha"}'::jsonb
  ),
  (
    'e4000000-0000-0000-0000-000000000002',
    'push-report-b@example.invalid',
    '{"first_name":"Report","last_name":"Beta"}'::jsonb
  );

update public.profiles
set status = 'active', updated_at = now()
where id in (
  'e4000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000002'
);

insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth)
values
  (
    'e4000000-0000-0000-0000-000000000001',
    'https://push.invalid/report-alpha',
    'alpha-key',
    'alpha-auth'
  ),
  (
    'e4000000-0000-0000-0000-000000000002',
    'https://push.invalid/report-beta',
    'beta-key',
    'beta-auth'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$
    select public.report_my_push_device(
      'https://push.invalid/report-alpha',
      'denied',
      jsonb_build_array(
        jsonb_build_object('tag', 'sport-x-availability-open', 'at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
        jsonb_build_object('tag', 'sport-x-availability-open', 'at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
        jsonb_build_object('tag', 'date-impossible', 'at', '2026-13-45T99:00:00Z'),
        jsonb_build_object('tag', 'trop-vieux', 'at', '2020-01-01T00:00:00Z'),
        jsonb_build_object('at', '2026-10-14T10:00:00Z'),
        'pas un objet'
      )
    )
  $$,
  'un accusé mal formé est ignoré sans faire échouer la déclaration'
);

-- Un compte ne peut pas toucher l'abonnement d'un autre.
select public.report_my_push_device(
  'https://push.invalid/report-beta',
  'denied',
  '[]'::jsonb
);

reset role;

select is(
  (
    select notification_permission
    from public.push_subscriptions
    where endpoint = 'https://push.invalid/report-alpha'
  ),
  'denied',
  'l’autorisation coupée dans les réglages du téléphone est enregistrée'
);

select ok(
  (
    select device_reported_at is not null
    from public.push_subscriptions
    where endpoint = 'https://push.invalid/report-alpha'
  ),
  'l’heure de la déclaration est enregistrée'
);

select is(
  (
    select notification_permission
    from public.push_subscriptions
    where endpoint = 'https://push.invalid/report-beta'
  ),
  null,
  'l’abonnement d’un autre compte reste intact'
);

select is(
  (
    select count(*)
    from private.push_display_receipts
    where profile_id = 'e4000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'seul l’accusé valide est gardé, une seule fois'
);

select is(
  (
    select endpoint_host
    from private.push_display_receipts
    where profile_id = 'e4000000-0000-0000-0000-000000000001'
  ),
  'push.invalid',
  'l’accusé garde le service du téléphone, pas son adresse complète'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.report_my_push_device(
  'https://push.invalid/report-alpha',
  'n-importe-quoi',
  null
);

reset role;

select is(
  (
    select notification_permission
    from public.push_subscriptions
    where endpoint = 'https://push.invalid/report-alpha'
  ),
  null,
  'une autorisation inconnue est enregistrée comme non déclarée'
);

-- Aucune identité : l'archivage est une opération d'administration.
select set_config('request.jwt.claims', '', true);

update public.profiles
set status = 'archived', updated_at = now()
where id = 'e4000000-0000-0000-0000-000000000002';

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.report_my_push_device(
      'https://push.invalid/report-beta',
      'granted',
      '[]'::jsonb
    )
  $$,
  '42501',
  'un profil archivé ne déclare rien'
);

reset role;

select * from finish();

rollback;
