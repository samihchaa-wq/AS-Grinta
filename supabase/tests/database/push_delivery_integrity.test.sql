begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  not has_function_privilege(
    'anon',
    'public.internal_push_prune(text[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.internal_push_prune(text[])',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.internal_push_prune(text[])',
    'EXECUTE'
  ),
  'le nettoyage des abonnements expirés est réservé au service interne'
);

insert into auth.users(id, email, raw_user_meta_data)
values (
  'e2000000-0000-0000-0000-000000000001',
  'push-integrity@example.invalid',
  '{"first_name":"Push","last_name":"Integrity"}'::jsonb
);

insert into public.push_subscriptions(
  id,
  profile_id,
  endpoint,
  p256dh,
  auth,
  user_agent
)
values
  (
    'e2100000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    'https://push.invalid/expired',
    'key-expired',
    'auth-expired',
    'test'
  ),
  (
    'e2100000-0000-0000-0000-000000000002',
    'e2000000-0000-0000-0000-000000000001',
    'https://push.invalid/active',
    'key-active',
    'auth-active',
    'test'
  );

set local role service_role;

select is(
  public.internal_push_prune(array['https://push.invalid/expired']),
  1,
  'le service supprime exactement l’abonnement déclaré expiré'
);

reset role;

select is(
  (
    select count(*)
    from public.push_subscriptions
    where profile_id = 'e2000000-0000-0000-0000-000000000001'
      and endpoint = 'https://push.invalid/active'
  ),
  1::bigint,
  'un abonnement actif n’est pas supprimé par erreur'
);

select throws_ok(
  $$insert into public.push_subscriptions(
    id, profile_id, endpoint, p256dh, auth, user_agent
  ) values (
    'e2100000-0000-0000-0000-000000000003',
    'e2000000-0000-0000-0000-000000000001',
    'https://push.invalid/active',
    'other-key',
    'other-auth',
    'test'
  )$$,
  '23505',
  null,
  'un même endpoint de navigateur ne peut pas être enregistré deux fois'
);

select * from finish();
rollback;
