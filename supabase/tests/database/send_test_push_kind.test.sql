-- Vérifie les variantes de test sans jamais déclencher de Web Push réel.
-- Tous les appels valides sont effectués avec un profil sans abonnement :
-- ils doivent donc s'arrêter sur no_subscription avant net.http_post.

begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.send_test_push_kind(text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.send_test_push_kind(text)',
    'execute'
  ),
  'la RPC typée est exécutable uniquement par authenticated'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '43000000-0000-0000-0000-000000000001',
    'typed-push-active@example.invalid',
    '{"first_name":"Push","last_name":"Active"}'::jsonb
  ),
  (
    '43000000-0000-0000-0000-000000000002',
    'typed-push-archived@example.invalid',
    '{"first_name":"Push","last_name":"Archived"}'::jsonb
  );

update public.profiles
set role = 'pronostiqueur',
    status = case
      when id = '43000000-0000-0000-0000-000000000001' then 'active'
      else 'archived'
    end,
    updated_at = now()
where id in (
  '43000000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000002'
);

set local role authenticated;
set local request.jwt.claim.sub = '43000000-0000-0000-0000-000000000002';

select throws_ok(
  $$select public.send_test_push_kind('test')$$,
  '42501',
  'un profil archivé ne peut pas déclencher un test typé'
);

reset role;
set local request.jwt.claim.sub = '';
set local role authenticated;
set local request.jwt.claim.sub = '43000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.send_test_push_kind('unknown_kind')$$,
  '22023',
  'un type hors liste blanche est refusé'
);

select is(
  public.send_test_push_kind('test')->>'reason',
  'no_subscription',
  'test technique reconnu'
);
select is(
  public.send_test_push_kind('availability_open')->>'reason',
  'no_subscription',
  'ouverture des disponibilités reconnue'
);
select is(
  public.send_test_push_kind('availability_manual')->>'reason',
  'no_subscription',
  'relance disponibilité reconnue'
);
select is(
  public.send_test_push_kind('convocation_promoted')->>'reason',
  'no_subscription',
  'passage en convoqué reconnu'
);
select is(
  public.send_test_push_kind('prediction_j5')->>'reason',
  'no_subscription',
  'rappel pronostic reconnu'
);
select is(
  public.send_test_push_kind('match_cancelled')->>'reason',
  'no_subscription',
  'match annulé reconnu'
);
select is(
  public.send_test_push_kind('match_rescheduled_date')->>'reason',
  'no_subscription',
  'match reporté reconnu'
);
select is(
  public.send_test_push_kind('match_rescheduled_time')->>'reason',
  'no_subscription',
  'horaire modifié reconnu'
);
select is(
  public.send_test_push_kind('motm_open')->>'reason',
  'no_subscription',
  'ouverture du vote Homme du match reconnue'
);
select is(
  public.send_test_push_kind('motm_result_general')->>'reason',
  'no_subscription',
  'résultat Homme du match collectif reconnu'
);
select is(
  public.send_test_push_kind('motm_result_winner')->>'reason',
  'no_subscription',
  'résultat Homme du match gagnant reconnu'
);
select is(
  public.send_test_push_kind('admin_pending_signup')->>'reason',
  'no_subscription',
  'alerte de compte en attente reconnue'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)::bigint
    from private.test_push_attempts
    where profile_id = '43000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'un test sans abonnement ne consomme pas le quota et ne part pas'
);

select * from finish();
rollback;
