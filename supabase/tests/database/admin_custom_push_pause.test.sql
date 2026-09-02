begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
  '8f200000-0000-0000-0000-000000000001',
  'custom-push-pause-admin@example.invalid',
  '{"first_name":"Admin","last_name":"CustomPush"}'::jsonb
);

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id = '8f200000-0000-0000-0000-000000000001';

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '8f200000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"8f200000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_send_custom_push(
    null,
    null,
    null
  )$$,
  '55000',
  'un envoi libre admin est refusé tant que les notifications sont en pause'
);

reset role;

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '8f200000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"8f200000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_send_custom_push(
    null,
    null,
    null
  )$$,
  '22023',
  'après réactivation, l’envoi libre repasse aux validations normales de contenu'
);

reset role;

select * from finish();
rollback;
