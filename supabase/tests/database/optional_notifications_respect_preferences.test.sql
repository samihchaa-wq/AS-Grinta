begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Une cloche grise dans l'écran Notifications arrête la notification
-- correspondante, et elle seule :
--
-- * « Rappel pronostic »                       → notify_prediction_reminders ;
-- * « Composition en ligne »                   → notify_composition ;
-- * « Changement de disponibilité d'un joueur » → notify_admin_availability_change.
--
-- Vote et résultat Homme du match, badges : couverts par leurs propres tests.
--
-- Les envois sont lus dans la file de pg_net, à l'intérieur de la
-- transaction du test : rien ne part réellement, tout est annulé à la fin.
-- Le journal de livraison accepte aussi les envois ciblés, avec ou sans
-- match.

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

insert into auth.users(id, email, raw_user_meta_data)
values
  ('e9100000-0000-0000-0000-000000000001', 'prefs-admin-on@example.invalid',
   '{"first_name":"Adminoui"}'::jsonb),
  ('e9100000-0000-0000-0000-000000000002', 'prefs-admin-off@example.invalid',
   '{"first_name":"Adminnon"}'::jsonb),
  ('e9100000-0000-0000-0000-000000000003', 'prefs-player-on@example.invalid',
   '{"first_name":"Joueuroui"}'::jsonb),
  ('e9100000-0000-0000-0000-000000000004', 'prefs-player-off@example.invalid',
   '{"first_name":"Joueurnon"}'::jsonb);

update public.profiles
set role = case
      when id in (
        'e9100000-0000-0000-0000-000000000001',
        'e9100000-0000-0000-0000-000000000002'
      ) then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    notify_prediction_reminders =
      id <> 'e9100000-0000-0000-0000-000000000004',
    notify_composition =
      id <> 'e9100000-0000-0000-0000-000000000004',
    notify_admin_availability_change =
      id <> 'e9100000-0000-0000-0000-000000000002',
    updated_at = now()
where id between
  'e9100000-0000-0000-0000-000000000001'
  and 'e9100000-0000-0000-0000-000000000004';

insert into public.seasons(id, name, status)
values ('e9200000-0000-0000-0000-000000000001', '2111-2112', 'open');

insert into public.opponents(id, name)
values ('e9300000-0000-0000-0000-000000000001', 'Cloche FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
) values
  ('e9400000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'Joueuroui', 'Cloche', false, true, 1,
   'e9100000-0000-0000-0000-000000000003'),
  ('e9400000-0000-0000-0000-000000000002',
   'e9200000-0000-0000-0000-000000000001', 'Joueurnon', 'Cloche', false, true, 2,
   'e9100000-0000-0000-0000-000000000004');

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at,
  location, planned_duration_minutes, status, created_by, match_type
) values (
  'e9500000-0000-0000-0000-000000000001',
  'e9200000-0000-0000-0000-000000000001',
  'e9300000-0000-0000-0000-000000000001',
  ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
  ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
  now() + interval '3 days',
  'domicile', 90, 'a_venir',
  'e9100000-0000-0000-0000-000000000001',
  'amical'
);

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'e9100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"e9100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
select private.sync_match_sport_workflow('e9500000-0000-0000-0000-000000000001');

update public.match_sport_workflows
set availability_state = 'open',
    availability_opens_at = now() - interval '1 hour',
    availability_opened_at = now() - interval '1 hour'
where match_id = 'e9500000-0000-0000-0000-000000000001';

insert into public.push_subscriptions(profile_id, endpoint, p256dh, auth)
select profile.id,
       'https://push.example.invalid/prefs-' || profile.id,
       'p256dh-test',
       'auth-test'
from public.profiles profile
where profile.id between
  'e9100000-0000-0000-0000-000000000001'
  and 'e9100000-0000-0000-0000-000000000004';

-- Profils visés par le dernier envoi ciblé portant ce titre.
create or replace function pg_temp.last_targets(p_title text)
returns jsonb
language sql
stable
as $function$
  select convert_from(queue.body, 'UTF8')::jsonb -> 'profile_ids'
  from net.http_request_queue queue
  where convert_from(queue.body, 'UTF8')::jsonb ->> 'title' = p_title
  order by queue.id desc
  limit 1;
$function$;

-- ---------------------------------------------------------------------------
-- Rappel pronostic
-- ---------------------------------------------------------------------------

select set_config(
  'test.prediction_targets',
  (
    select coalesce(jsonb_agg(subscription ->> 'profile_id'), '[]'::jsonb)::text
    from jsonb_array_elements(
      public.internal_push_dispatch(
        'prediction_j5', 'e9500000-0000-0000-0000-000000000001'
      ) -> 'subscriptions'
    ) subscription
  ),
  true
);

select ok(
  current_setting('test.prediction_targets')::jsonb
    ? 'e9100000-0000-0000-0000-000000000003',
  'cloche verte : le rappel pronostic est envoyé'
);
select ok(
  not current_setting('test.prediction_targets')::jsonb
    ? 'e9100000-0000-0000-0000-000000000004',
  'cloche grise : le rappel pronostic n''est pas envoyé'
);

-- ---------------------------------------------------------------------------
-- Composition en ligne
-- ---------------------------------------------------------------------------

update public.match_sport_participants
set availability_status = 'available',
    convocation_status = 'convoked',
    updated_at = now()
where match_id = 'e9500000-0000-0000-0000-000000000001'
  and season_player_id in (
    'e9400000-0000-0000-0000-000000000001',
    'e9400000-0000-0000-0000-000000000002'
  );

select ok(
  private.notify_composition_published('e9500000-0000-0000-0000-000000000001'),
  'la mise en ligne de la composition est annoncée'
);

select ok(
  pg_temp.last_targets('La composition est en ligne')
    ? 'e9100000-0000-0000-0000-000000000003',
  'cloche verte : la composition en ligne est envoyée au convoqué'
);
select ok(
  not pg_temp.last_targets('La composition est en ligne')
    ? 'e9100000-0000-0000-0000-000000000004',
  'cloche grise : la composition en ligne n''est pas envoyée'
);

select is(
  (
    select (convert_from(queue.body, 'UTF8')::jsonb ->> 'log_kind')
      || ' / ' || (convert_from(queue.body, 'UTF8')::jsonb ->> 'match_id')
    from net.http_request_queue queue
    where convert_from(queue.body, 'UTF8')::jsonb ->> 'title'
      = 'La composition est en ligne'
    order by queue.id desc
    limit 1
  ),
  'composition_published / e9500000-0000-0000-0000-000000000001',
  'l''envoi de la composition indique son type et son match pour le journal'
);

-- ---------------------------------------------------------------------------
-- Changement de disponibilité d'un joueur (administrateurs)
-- ---------------------------------------------------------------------------

-- Le joueur se ravise : présent puis absent.
update public.match_sport_participants
set availability_status = 'absent',
    availability_updated_at = now(),
    availability_updated_by = 'e9100000-0000-0000-0000-000000000003',
    updated_at = now()
where match_id = 'e9500000-0000-0000-0000-000000000001'
  and season_player_id = 'e9400000-0000-0000-0000-000000000001';

select ok(
  pg_temp.last_targets('Changement de disponibilité')
    ? 'e9100000-0000-0000-0000-000000000001',
  'cloche verte : l''administrateur est prévenu du changement'
);
select ok(
  not pg_temp.last_targets('Changement de disponibilité')
    ? 'e9100000-0000-0000-0000-000000000002',
  'cloche grise : l''administrateur n''est pas prévenu'
);

-- ---------------------------------------------------------------------------
-- Journal de livraison des envois ciblés
-- ---------------------------------------------------------------------------

select lives_ok(
  $sql$
    insert into public.push_delivery_log(
      match_id, kind, profile_id, endpoint_host, success, status_code, attempts
    ) values (
      null, 'badge_unlocked', 'e9100000-0000-0000-0000-000000000003',
      'push.example.invalid', true, 201, 1
    )
  $sql$,
  'un envoi sans match (badge) est journalisé'
);

select lives_ok(
  $sql$
    insert into public.push_delivery_log(
      match_id, kind, profile_id, endpoint_host, success, status_code,
      error_message, attempts
    ) values (
      'e9500000-0000-0000-0000-000000000001', 'convocation_demoted',
      'e9100000-0000-0000-0000-000000000004', 'push.example.invalid',
      false, 403, 'refus du service', 1
    )
  $sql$,
  'un échec de livraison ciblée est journalisé avec son match'
);

select throws_ok(
  $sql$
    insert into public.push_delivery_log(
      match_id, kind, profile_id, endpoint_host, success, status_code, attempts
    ) values (
      null, 'type_inconnu', null, null, true, 201, 1
    )
  $sql$,
  '23514',
  'un type inconnu reste refusé par le journal'
);

select ok(
  pg_get_functiondef(
    'private.process_badge_unlock_notifications(timestamptz)'::regprocedure
  ) like '%''log_kind'', ''badge_unlocked''%',
  'les badges débloqués indiquent leur type pour le journal'
);
select ok(
  pg_get_functiondef(
    'private.dispatch_motm_result_notification(text,uuid)'::regprocedure
  ) like '%''log_kind'', p_kind%',
  'le résultat Homme du match indique son type pour le journal'
);
select ok(
  pg_get_functiondef(
    'private.dispatch_convocation_push(uuid,uuid)'::regprocedure
  ) like '%''log_kind'', ''convocation_promoted''%',
  'la convocation indique son type pour le journal'
);

select * from finish();
rollback;
