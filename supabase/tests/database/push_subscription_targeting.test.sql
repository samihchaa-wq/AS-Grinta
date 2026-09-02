begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '8f300000-0000-0000-0000-000000000001',
    'push-targeting-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Targeting"}'::jsonb
  ),
  (
    '8f300000-0000-0000-0000-000000000002',
    'push-targeting-player@example.invalid',
    '{"first_name":"Player","last_name":"Targeting"}'::jsonb
  ),
  (
    '8f300000-0000-0000-0000-000000000003',
    'push-targeting-no-device@example.invalid',
    '{"first_name":"NoPush","last_name":"Targeting"}'::jsonb
  );

update public.profiles
set role = case
      when id = '8f300000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    notify_match_reminders = true,
    updated_at = now()
where id between
  '8f300000-0000-0000-0000-000000000001'
  and '8f300000-0000-0000-0000-000000000003';

insert into public.seasons (id, name, status)
values ('8f310000-0000-0000-0000-000000000001', '2098-2099', 'open');

insert into public.opponents (id, name)
values ('8f320000-0000-0000-0000-000000000001', 'Push Target FC');

insert into public.season_players (
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
)
values (
  '8f330000-0000-0000-0000-000000000001',
  '8f310000-0000-0000-0000-000000000001',
  'Player',
  'Targeting',
  false,
  true,
  1,
  '8f300000-0000-0000-0000-000000000002'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '8f300000-0000-0000-0000-000000000001'
where key = 'sports_management';

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '8f300000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"8f300000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.push_targeting_match',
  public.create_match_with_odds_and_sport_limit(
    '8f310000-0000-0000-0000-000000000001',
    '8f320000-0000-0000-0000-000000000001',
    ((now() + interval '10 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '10 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    14
  )::text,
  true
);

reset role;

select private.process_sport_availability_notifications(
  (
    select availability_opens_at
    from public.match_sport_workflows
    where match_id = current_setting('test.push_targeting_match')::uuid
  )
);

select set_config(
  'request.jwt.claims',
  '{"sub":"8f300000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_send_match_availability_reminder(
    current_setting('test.push_targeting_match')::uuid,
    null,
    'Relance sans abonnement push'
  ) #>> '{created_count}',
  '0',
  'une relance sans abonnement push ne crée aucun envoi'
);

select is(
  public.admin_send_match_availability_reminder(
    current_setting('test.push_targeting_match')::uuid,
    null,
    'Deuxième lecture du résultat sans abonnement'
  ) #>> '{skipped_no_subscription_count}',
  '1',
  'le serveur expose explicitement le joueur sans abonnement push'
);

reset role;

select is(
  (
    select count(*)
    from public.sport_availability_notification_events
    where match_id = current_setting('test.push_targeting_match')::uuid
      and kind = 'availability_manual'
  ),
  0::bigint,
  'aucun événement manuel fantôme ni cooldown ne sont créés sans abonnement'
);

insert into public.push_subscriptions (
  profile_id,
  endpoint,
  p256dh,
  auth,
  user_agent
)
values (
  '8f300000-0000-0000-0000-000000000002',
  'https://push.example.invalid/targeting-player',
  'targeting-key',
  'targeting-auth',
  'pgTAP'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"8f300000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_send_match_availability_reminder(
    current_setting('test.push_targeting_match')::uuid,
    null,
    'Relance après activation push'
  ) #>> '{created_count}',
  '1',
  'le même joueur devient immédiatement relançable après activation push'
);

select throws_ok(
  $$select public.admin_send_custom_push(
    'Test ciblage',
    'Ce profil n’a aucun appareil abonné.',
    array['8f300000-0000-0000-0000-000000000003'::uuid]
  )$$,
  '22023',
  'un profil sans abonnement push n’est pas compté comme destinataire custom'
);

reset role;

select is(
  (
    select count(*)
    from public.sport_availability_notification_events
    where match_id = current_setting('test.push_targeting_match')::uuid
      and kind = 'availability_manual'
  ),
  1::bigint,
  'une seule relance manuelle réelle est historisée après activation push'
);

select * from finish();
rollback;
