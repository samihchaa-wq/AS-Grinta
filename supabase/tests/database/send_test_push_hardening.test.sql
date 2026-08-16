-- Non-régression du durcissement de public.send_test_push().
-- Aucun test ne déclenche de requête Push réelle : les parcours exercés
-- s'arrêtent avant net.http_post (profil archivé ou quota déjà atteint).

begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('private.test_push_attempts') is not null,
  'le registre privé de limitation existe'
);

select ok(
  (select relrowsecurity
   from pg_class
   where oid = 'private.test_push_attempts'::regclass),
  'RLS est activée sur le registre de limitation'
);

select ok(
  not has_table_privilege('authenticated', 'private.test_push_attempts', 'select')
  and not has_table_privilege('authenticated', 'private.test_push_attempts', 'insert'),
  'authenticated ne peut ni lire ni alimenter directement le registre'
);

select ok(
  has_function_privilege('authenticated', 'public.send_test_push()', 'execute')
  and not has_function_privilege('anon', 'public.send_test_push()', 'execute'),
  'la RPC reste réservée aux sessions authentifiées'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('41000000-0000-0000-0000-000000000001', 'push-active@example.invalid',
   '{"first_name":"Push","last_name":"Active"}'::jsonb),
  ('41000000-0000-0000-0000-000000000002', 'push-archived@example.invalid',
   '{"first_name":"Push","last_name":"Archived"}'::jsonb);

update public.profiles
set role = 'pronostiqueur',
    status = case
      when id = '41000000-0000-0000-0000-000000000001' then 'active'
      else 'archived'
    end,
    updated_at = now()
where id in (
  '41000000-0000-0000-0000-000000000001',
  '41000000-0000-0000-0000-000000000002'
);

set local role authenticated;
set local request.jwt.claim.sub = '41000000-0000-0000-0000-000000000002';

select throws_ok(
  $$select public.send_test_push()$$,
  '42501',
  'un profil archivé est refusé avant tout envoi'
);

reset role;
set local request.jwt.claim.sub = '';

insert into private.test_push_attempts (profile_id, attempted_at)
values
  ('41000000-0000-0000-0000-000000000001', now() - interval '1 minute'),
  ('41000000-0000-0000-0000-000000000001', now() - interval '2 minutes'),
  ('41000000-0000-0000-0000-000000000001', now() - interval '3 minutes');

set local role authenticated;
set local request.jwt.claim.sub = '41000000-0000-0000-0000-000000000001';

select is(
  public.send_test_push()->>'reason',
  'rate_limited',
  'le quatrième test dans une fenêtre de 10 minutes est bloqué côté serveur'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (select count(*)::bigint
   from private.test_push_attempts
   where profile_id = '41000000-0000-0000-0000-000000000001'),
  3::bigint,
  'un appel limité ne consomme pas une tentative supplémentaire'
);

select * from finish();
rollback;
