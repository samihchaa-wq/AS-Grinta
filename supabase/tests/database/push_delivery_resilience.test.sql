begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'push_delivery_log'
      and column_name = 'attempts'
      and data_type = 'smallint'
      and is_nullable = 'NO'
  ),
  'le journal conserve le nombre d’essais de chaque livraison'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.push_delivery_log'::regclass
      and conname = 'push_delivery_log_attempts_check'
  ),
  'le nombre d’essais est borné par une contrainte'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.internal_push_delivery_health(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.internal_push_delivery_health(timestamptz)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.internal_push_delivery_health(timestamptz)',
    'EXECUTE'
  ),
  'la santé des livraisons reste réservée au service interne'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'e3000000-0000-0000-0000-000000000001',
    'push-device-a@example.invalid',
    '{"first_name":"Device","last_name":"Alpha"}'::jsonb
  ),
  (
    'e3000000-0000-0000-0000-000000000002',
    'push-device-b@example.invalid',
    '{"first_name":"Device","last_name":"Beta"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'e3000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  'e3000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000002'
);

insert into public.seasons (id, name, status)
values ('e3100000-0000-0000-0000-000000000001', '2098-2099', 'open');

insert into public.opponents (id, name)
values ('e3200000-0000-0000-0000-000000000001', 'Push Resilience FC');

select set_config(
  'request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.push_resilience_match',
  public.create_match_with_odds_and_sport_limit(
    'e3100000-0000-0000-0000-000000000001',
    'e3200000-0000-0000-0000-000000000001',
    ((now() + interval '20 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '20 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    14
  )::text,
  true
);

reset role;

insert into public.push_subscriptions (
  profile_id,
  endpoint,
  p256dh,
  auth,
  user_agent
)
values
  (
    'e3000000-0000-0000-0000-000000000001',
    'https://push.invalid/device-alpha-phone',
    'alpha-phone-key',
    'alpha-phone-auth',
    'phone'
  ),
  (
    'e3000000-0000-0000-0000-000000000001',
    'https://push.invalid/device-alpha-laptop',
    'alpha-laptop-key',
    'alpha-laptop-auth',
    'laptop'
  ),
  (
    'e3000000-0000-0000-0000-000000000002',
    'https://push.invalid/device-beta-phone',
    'beta-phone-key',
    'beta-phone-auth',
    'phone'
  );

select is(
  (
    select count(*)
    from public.push_subscriptions
    where profile_id = 'e3000000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'un même profil peut recevoir la notification sur plusieurs appareils'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select public.register_push_subscription(
  'https://push.invalid/device-alpha-phone',
  'beta-shared-key',
  'beta-shared-auth',
  'shared-phone'
);

reset role;

select is(
  (
    select count(*)
    from public.push_subscriptions
    where endpoint = 'https://push.invalid/device-alpha-phone'
  ),
  1::bigint,
  'un endpoint partagé ne peut jamais être dupliqué'
);

select is(
  (
    select profile_id
    from public.push_subscriptions
    where endpoint = 'https://push.invalid/device-alpha-phone'
  ),
  'e3000000-0000-0000-0000-000000000002'::uuid,
  'un appareil partagé est réattribué atomiquement au compte courant'
);

set local role service_role;

select is(
  public.internal_push_prune(array[
    'https://push.invalid/device-alpha-phone',
    'https://push.invalid/device-absent'
  ]),
  1,
  'le nettoyage retire uniquement l’abonnement réellement expiré'
);

reset role;

select is(
  (
    select count(*)
    from public.push_subscriptions
    where profile_id in (
      'e3000000-0000-0000-0000-000000000001',
      'e3000000-0000-0000-0000-000000000002'
    )
  ),
  2::bigint,
  'les autres appareils restent abonnés après le nettoyage'
);

insert into public.push_delivery_log (
  match_id,
  kind,
  profile_id,
  endpoint_host,
  success,
  status_code,
  error_message,
  attempts,
  created_at
)
values
  (
    current_setting('test.push_resilience_match')::uuid,
    'result_validated',
    'e3000000-0000-0000-0000-000000000001',
    'push.invalid',
    true,
    201,
    null,
    1,
    now()
  ),
  (
    current_setting('test.push_resilience_match')::uuid,
    'result_validated',
    'e3000000-0000-0000-0000-000000000001',
    'push.invalid',
    true,
    201,
    null,
    2,
    now()
  ),
  (
    current_setting('test.push_resilience_match')::uuid,
    'result_validated',
    'e3000000-0000-0000-0000-000000000002',
    'push.invalid',
    false,
    410,
    'expired',
    1,
    now()
  ),
  (
    current_setting('test.push_resilience_match')::uuid,
    'result_validated',
    'e3000000-0000-0000-0000-000000000002',
    'push.invalid',
    false,
    503,
    'temporary failure',
    2,
    now()
  );

set local role service_role;

select is(
  (public.internal_push_delivery_health(now() - interval '1 hour') ->> 'attempted')::integer,
  4,
  'la surveillance agrège toutes les tentatives de la fenêtre'
);

select is(
  (public.internal_push_delivery_health(now() - interval '1 hour') ->> 'retry_recoveries')::integer,
  1,
  'une réussite après relance est distinguée'
);

select is(
  (public.internal_push_delivery_health(now() - interval '1 hour') ->> 'expired')::integer,
  1,
  'les endpoints expirés sont comptés séparément'
);

select is(
  (public.internal_push_delivery_health(now() - interval '1 hour') ->> 'retry_exhausted')::integer,
  1,
  'un échec temporaire après relance est signalé'
);

select is(
  (public.internal_push_delivery_health(now() - interval '1 hour') ->> 'requires_attention')::boolean,
  true,
  'un échec non expiré déclenche l’attention opérationnelle'
);

reset role;

select * from finish();
rollback;
