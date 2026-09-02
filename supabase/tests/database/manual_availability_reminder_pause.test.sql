begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
  '8f100000-0000-0000-0000-000000000001',
  'notification-pause-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Pause"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '8f100000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '8f100000-0000-0000-0000-000000000001'
where key = 'sports_management';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '8f100000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"8f100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_send_match_availability_reminder(
    null,
    null,
    'Cette relance doit être bloquée par le coupe-circuit'
  )$$,
  '55000',
  'une relance manuelle est refusée tant que les notifications sont en pause'
);

reset role;

select is(
  (
    select count(*)
    from public.sport_availability_notification_events
    where requested_by = '8f100000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'le refus ne crée aucun événement de notification fantôme'
);

select is(
  (
    select count(*)
    from private.sport_admin_audit_log
    where actor_profile_id = '8f100000-0000-0000-0000-000000000001'
      and action = 'send_availability_reminder'
  ),
  0::bigint,
  'le refus ne journalise pas une relance comme si elle avait été envoyée'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '8f100000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"8f100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_send_match_availability_reminder(
    null,
    null,
    'Après réactivation, la validation normale reprend'
  )$$,
  '22023',
  'après réactivation, la RPC repasse bien aux validations métier normales'
);

reset role;

select * from finish();
rollback;
