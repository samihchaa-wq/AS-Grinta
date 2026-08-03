begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.sport_availability_notification_events') is not null,
  'le journal des notifications de disponibilité existe'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.sport_availability_notification_events'::regclass
  ),
  'RLS est activée sur le journal de notifications'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.sport_availability_notification_events',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.sport_availability_notification_events',
    'INSERT'
  ),
  'les clients ne lisent ni ne modifient directement le journal'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.admin_send_match_availability_reminder(uuid,uuid,text)',
      'public.admin_get_match_availability_reminders(uuid)'
    ]::text[]) expected(signature)
    join pg_proc procedure on procedure.oid = to_regprocedure(expected.signature)
    where procedure.prosecdef
  ),
  0::bigint,
  'les RPC publiques de rappel restent SECURITY INVOKER'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_send_match_availability_reminder(uuid,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_get_match_availability_reminders(uuid)',
    'EXECUTE'
  ),
  'les RPC de rappel ne sont jamais exposées au rôle anonyme'
);

select is(
  (
    select schedule
    from cron.job
    where jobname = 'sports-availability-reminders'
  ),
  '* * * * *',
  'le moteur gratuit vérifie les échéances chaque minute'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '81000000-0000-0000-0000-000000000001',
    'notification-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Notification"}'::jsonb
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    'notification-alice@example.invalid',
    '{"first_name":"Alice","last_name":"Notification"}'::jsonb
  ),
  (
    '81000000-0000-0000-0000-000000000003',
    'notification-bruno@example.invalid',
    '{"first_name":"Bruno","last_name":"Notification"}'::jsonb
  );

update public.profiles
set role = case
      when id = '81000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    notify_match_reminders = true,
    updated_at = now()
where id between
  '81000000-0000-0000-0000-000000000001'
  and '81000000-0000-0000-0000-000000000003';

insert into public.seasons (id, name, status)
values ('82000000-0000-0000-0000-000000000001', '2097-2098', 'open');

insert into public.opponents (id, name)
values ('83000000-0000-0000-0000-000000000001', 'Notification FC');

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
values
  (
    '84000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    'Alice',
    'Notification',
    false,
    true,
    1,
    '81000000-0000-0000-0000-000000000002'
  ),
  (
    '84000000-0000-0000-0000-000000000002',
    '82000000-0000-0000-0000-000000000001',
    'Bruno',
    'Notification',
    false,
    true,
    2,
    '81000000-0000-0000-0000-000000000003'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '81000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.notification_match',
  public.create_match_with_odds_and_sport_limit(
    '82000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000001',
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

insert into public.push_subscriptions (
  profile_id,
  endpoint,
  p256dh,
  auth,
  user_agent
)
values
  (
    '81000000-0000-0000-0000-000000000002',
    'https://push.example.invalid/alice-notification',
    'alice-key',
    'alice-auth',
    'pgTAP'
  ),
  (
    '81000000-0000-0000-0000-000000000003',
    'https://push.example.invalid/bruno-notification',
    'bruno-key',
    'bruno-auth',
    'pgTAP'
  );

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '81000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select is(
  private.process_sport_availability_notifications(
    (
      select availability_opens_at
      from public.match_sport_workflows
      where match_id = current_setting('test.notification_match')::uuid
    )
  ) #>> '{notifications_created}',
  '0',
  'le moteur reste totalement inerte lorsque le feature flag est désactivé'
);

select is(
  (
    select availability_state::text
    from public.match_sport_workflows
    where match_id = current_setting('test.notification_match')::uuid
  ),
  'pending',
  'le flag désactivé ne modifie même pas l’état du workflow'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '81000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select is(
  private.process_sport_availability_notifications(
    (
      select availability_opens_at
      from public.match_sport_workflows
      where match_id = current_setting('test.notification_match')::uuid
    )
  ) #>> '{notifications_created}',
  '2',
  'à l’ouverture exacte, chaque joueur éligible reçoit une seule notification'
);

select is(
  (
    select availability_state::text
    from public.match_sport_workflows
    where match_id = current_setting('test.notification_match')::uuid
  ),
  'open',
  'le moteur ouvre atomiquement les disponibilités arrivées à échéance'
);

select is(
  (
    select count(*)
    from public.sport_availability_notification_events
    where match_id = current_setting('test.notification_match')::uuid
      and kind = 'availability_open'
      and source = 'automatic'
  ),
  2::bigint,
  'deux événements d’ouverture sont historisés'
);

select is(
  private.process_sport_availability_notifications(
    (
      select availability_opens_at + interval '1 minute'
      from public.match_sport_workflows
      where match_id = current_setting('test.notification_match')::uuid
    )
  ) #>> '{notifications_created}',
  '0',
  'un second passage ne crée aucun doublon d’ouverture'
);

select is(
  jsonb_array_length(
    public.internal_sport_push_dispatch(
      'availability_open',
      current_setting('test.notification_match')::uuid,
      array[
        '81000000-0000-0000-0000-000000000002'::uuid,
        '81000000-0000-0000-0000-000000000003'::uuid
      ]
    ) -> 'subscriptions'
  ),
  2,
  'la notification d’ouverture cible les deux abonnements actifs'
);

update public.match_sport_participants
set availability_status = 'available',
    availability_updated_at = now(),
    availability_updated_by = '81000000-0000-0000-0000-000000000001',
    updated_at = now()
where match_id = current_setting('test.notification_match')::uuid
  and season_player_id = '84000000-0000-0000-0000-000000000001';

select is(
  private.process_sport_availability_notifications(
    (
      select kickoff_at - interval '72 hours'
      from public.matches
      where id = current_setting('test.notification_match')::uuid
    )
  ) #>> '{notifications_created}',
  '0',
  'aucun rappel automatique n’est envoyé à J−3'
);

select is(
  (
    select count(*)
    from public.sport_availability_notification_events
    where match_id = current_setting('test.notification_match')::uuid
      and kind in ('availability_j3', 'availability_j1')
      and source = 'automatic'
  ),
  0::bigint,
  'aucun événement automatique J−3/J−1 n’est historisé'
);

select throws_ok(
  $$select public.internal_sport_push_dispatch(
    'availability_j3',
    current_setting('test.notification_match')::uuid,
    array[
      '81000000-0000-0000-0000-000000000002'::uuid,
      '81000000-0000-0000-0000-000000000003'::uuid
    ]
  )$$,
  '22023',
  'les anciens types de rappel automatique ne sont plus dispatchables'
);

select is(
  private.process_sport_availability_notifications(
    (
      select kickoff_at - interval '24 hours'
      from public.matches
      where id = current_setting('test.notification_match')::uuid
    )
  ) #>> '{notifications_created}',
  '0',
  'aucun rappel automatique n’est envoyé à J−1'
);

select is(
  private.process_sport_availability_notifications(
    (
      select kickoff_at - interval '23 hours'
      from public.matches
      where id = current_setting('test.notification_match')::uuid
    )
  ) #>> '{notifications_created}',
  '0',
  'les passages suivants restent sans rappel automatique'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_send_match_availability_reminder(
    current_setting('test.notification_match')::uuid,
    null,
    'Relance collective du staff'
  ) #>> '{created_count}',
  '1',
  'l’admin peut relancer tous les joueurs encore sans réponse'
);

select is(
  public.admin_send_match_availability_reminder(
    current_setting('test.notification_match')::uuid,
    null,
    'Double clic involontaire'
  ) #>> '{skipped_recent_count}',
  '1',
  'le verrou de dix minutes bloque une relance manuelle en double'
);

select throws_ok(
  $$select public.admin_send_match_availability_reminder(
    current_setting('test.notification_match')::uuid,
    '84000000-0000-0000-0000-000000000001',
    'Alice a déjà répondu'
  )$$,
  '22023',
  'un joueur ayant répondu ne peut pas être relancé manuellement'
);

select is(
  public.admin_get_match_availability_reminders(
    current_setting('test.notification_match')::uuid
  ) #>> '{no_response_count}',
  '1',
  'le résumé administrateur expose le bon nombre de sans-réponse'
);

select is(
  public.admin_get_match_availability_reminders(
    current_setting('test.notification_match')::uuid
  ) #>> '{j3_sent_count}',
  '0',
  'le résumé confirme l’absence de relance automatique J−3'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_get_match_availability_reminders(
    current_setting('test.notification_match')::uuid
  )$$,
  '42501',
  'un joueur ne peut pas consulter le journal administratif des relances'
);

select throws_ok(
  $$select public.admin_send_match_availability_reminder(
    current_setting('test.notification_match')::uuid,
    null,
    null
  )$$,
  '42501',
  'un joueur ne peut pas déclencher une relance'
);

reset role;

select is(
  (
    select count(*)
    from private.sport_admin_audit_log
    where match_id = current_setting('test.notification_match')::uuid
      and action = 'send_availability_reminder'
  ),
  2::bigint,
  'chaque tentative administrative de relance est auditée'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '81000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.admin_get_match_availability_reminders(
    current_setting('test.notification_match')::uuid
  )$$,
  '42501',
  'la désactivation masque immédiatement le résumé des relances'
);

reset role;

select is(
  (
    select count(*)
    from public.sport_availability_notification_events
    where match_id = current_setting('test.notification_match')::uuid
  ),
  3::bigint,
  'la désactivation conserve l’ouverture et la relance manuelle sans rappels automatiques'
);

select * from finish();
rollback;