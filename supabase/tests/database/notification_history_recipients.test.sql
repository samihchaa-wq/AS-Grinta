-- Historique des notifications : les destinataires ne dépendent plus du
-- téléphone.
--
-- Trois joueurs du même effectif : l'un a un téléphone abonné, l'autre n'en a
-- aucun, le troisième est archivé. Le joueur sans téléphone doit figurer dans
-- recipient_profile_ids (et dans les envois mis en file), le profil archivé
-- jamais ; la liste des téléphones, elle, ne change pas.
--
-- Les envois sont lus dans la file de pg_net, à l'intérieur de la
-- transaction du test : rien ne part réellement, tout est annulé à la fin.

begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '7c1a0000-0000-0000-0000-000000000001',
    'history-recipients-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Historique"}'::jsonb
  ),
  (
    '7c1a0000-0000-0000-0000-000000000002',
    'history-recipients-device@example.invalid',
    '{"first_name":"Avec","last_name":"Telephone"}'::jsonb
  ),
  (
    '7c1a0000-0000-0000-0000-000000000003',
    'history-recipients-no-device@example.invalid',
    '{"first_name":"Sans","last_name":"Telephone"}'::jsonb
  ),
  (
    '7c1a0000-0000-0000-0000-000000000004',
    'history-recipients-archived@example.invalid',
    '{"first_name":"Ancien","last_name":"Joueur"}'::jsonb
  ),
  (
    '7c1a0000-0000-0000-0000-000000000005',
    'history-recipients-done@example.invalid',
    '{"first_name":"Alerte","last_name":"Terminee"}'::jsonb
  );

update public.profiles
set role = case
      when id = '7c1a0000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    notify_prediction_reminders = true,
    notify_motm_vote = true,
    updated_at = now()
where id between
  '7c1a0000-0000-0000-0000-000000000001'
  and '7c1a0000-0000-0000-0000-000000000005';

insert into public.seasons (id, name, status)
values ('7c1b0000-0000-0000-0000-000000000001', '2231-2232', 'open');

insert into public.opponents (id, name)
values ('7c1c0000-0000-0000-0000-000000000001', 'Historique FC');

insert into public.season_players (
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position,
  profile_id
) values
  (
    '7c1d0000-0000-0000-0000-000000000001',
    '7c1b0000-0000-0000-0000-000000000001',
    'Avec', 'Telephone', false, true, 1,
    '7c1a0000-0000-0000-0000-000000000002'
  ),
  (
    '7c1d0000-0000-0000-0000-000000000002',
    '7c1b0000-0000-0000-0000-000000000001',
    'Sans', 'Telephone', false, true, 2,
    '7c1a0000-0000-0000-0000-000000000003'
  ),
  (
    '7c1d0000-0000-0000-0000-000000000003',
    '7c1b0000-0000-0000-0000-000000000001',
    'Ancien', 'Joueur', false, true, 3,
    '7c1a0000-0000-0000-0000-000000000004'
  );

-- Seul le premier joueur a un téléphone abonné. Le profil archivé en a un
-- aussi : il ne doit pas pour autant redevenir destinataire.
insert into public.push_subscriptions (
  profile_id, endpoint, p256dh, auth, user_agent
) values
  (
    '7c1a0000-0000-0000-0000-000000000002',
    'https://push.example.invalid/history-recipients-device',
    'history-p256dh', 'history-auth', 'pgTAP'
  ),
  (
    '7c1a0000-0000-0000-0000-000000000004',
    'https://push.example.invalid/history-recipients-archived',
    'history-p256dh-archived', 'history-auth-archived', 'pgTAP'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '7c1a0000-0000-0000-0000-000000000001'
where key = 'sports_management';

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = '7c1a0000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

-- Profils attendus, dans l'ordre où les fonctions les renvoient.
select set_config(
  'test.device_and_no_device',
  '["7c1a0000-0000-0000-0000-000000000002","7c1a0000-0000-0000-0000-000000000003"]',
  true
);

-- Profils des téléphones renvoyés par une préparation d'envoi.
create or replace function pg_temp.subscription_profiles(p_dispatch jsonb)
returns jsonb
language sql
immutable
as $function$
  select coalesce(
    jsonb_agg(distinct subscription ->> 'profile_id'),
    '[]'::jsonb
  )
  from jsonb_array_elements(p_dispatch -> 'subscriptions') subscription;
$function$;

create or replace function pg_temp.mark()
returns text
language sql
as $function$
  select set_config(
    'test.marker',
    (select coalesce(max(id), 0) from net.http_request_queue)::text,
    true
  );
$function$;

-- Envois mis en file depuis le dernier repère.
create or replace function pg_temp.bodies_since_mark()
returns setof jsonb
language sql
stable
as $function$
  select convert_from(queue.body, 'UTF8')::jsonb
  from net.http_request_queue queue
  where queue.id > current_setting('test.marker')::bigint
  order by queue.id;
$function$;

-- ---------------------------------------------------------------------------
-- Deux matchs du même effectif : l'un à venir (disponibilités, relance,
-- annulation, pronostic, direct), l'autre déjà joué (vote Homme du match).
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.match',
  public.create_match_with_odds_and_sport_limit(
    '7c1b0000-0000-0000-0000-000000000001',
    '7c1c0000-0000-0000-0000-000000000001',
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

select set_config(
  'test.played_match',
  public.create_match_with_odds_and_sport_limit(
    '7c1b0000-0000-0000-0000-000000000001',
    '7c1c0000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
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
    where match_id = current_setting('test.match')::uuid
  )
);

update public.matches
set kickoff_at = now() - interval '2 hours',
    match_date = ((now() - interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '2 hours') at time zone 'Europe/Paris')::time
where id = current_setting('test.played_match')::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.played_match')::uuid,
    2,
    1,
    (
      select jsonb_agg(
        jsonb_build_object(
          'participant_id', participant.id,
          'present', true,
          'final_selection_status', 'starter',
          'goals', 0,
          'clean_sheet', false
        ) order by participant.id
      )
      from public.match_sport_participants participant
      where participant.match_id = current_setting('test.played_match')::uuid
    ),
    'Validation ouvrant le vote pour le test de l’historique'
  ) #>> '{vote_state}',
  'open',
  'le match joué ouvre le vote Homme du match'
);

reset role;

-- Le troisième joueur quitte le club après la création des matchs : il reste
-- dans l'effectif, mais n'est plus un destinataire.
update public.profiles
set status = 'archived',
    updated_at = now()
where id = '7c1a0000-0000-0000-0000-000000000004';

-- ---------------------------------------------------------------------------
-- Disponibilités (internal_sport_push_dispatch)
-- ---------------------------------------------------------------------------

select set_config(
  'test.dispatch',
  public.internal_sport_push_dispatch(
    'availability_open',
    current_setting('test.match')::uuid,
    array[
      '7c1a0000-0000-0000-0000-000000000002',
      '7c1a0000-0000-0000-0000-000000000003',
      '7c1a0000-0000-0000-0000-000000000004'
    ]::uuid[]
  )::text,
  true
);

select is(
  current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids',
  current_setting('test.device_and_no_device')::jsonb,
  'ouverture des disponibilités : le joueur sans téléphone est destinataire, pas le profil archivé'
);

select is(
  pg_temp.subscription_profiles(current_setting('test.dispatch')::jsonb),
  '["7c1a0000-0000-0000-0000-000000000002"]'::jsonb,
  'ouverture des disponibilités : la liste des téléphones ne change pas'
);

select is(
  public.internal_sport_push_dispatch(
    'availability_manual',
    current_setting('test.match')::uuid,
    array[
      '7c1a0000-0000-0000-0000-000000000003',
      '7c1a0000-0000-0000-0000-000000000004'
    ]::uuid[]
  ) -> 'recipient_profile_ids',
  '["7c1a0000-0000-0000-0000-000000000003"]'::jsonb,
  'relance : seuls les profils demandés, actifs et sans réponse sont destinataires'
);

select is(
  public.internal_sport_push_dispatch(
    'availability_open',
    current_setting('test.match')::uuid,
    array[]::uuid[]
  ),
  jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb),
  'sans profil demandé, la sortie anticipée reste identique'
);

-- ---------------------------------------------------------------------------
-- Match annulé, rappel de pronostic, vote (internal_push_dispatch)
-- ---------------------------------------------------------------------------

select set_config(
  'test.dispatch',
  public.internal_push_dispatch(
    'match_cancelled',
    current_setting('test.match')::uuid
  )::text,
  true
);

select is(
  current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids',
  current_setting('test.device_and_no_device')::jsonb,
  'match annulé : le joueur sans téléphone est destinataire, pas le profil archivé ni l’admin hors effectif'
);

select is(
  pg_temp.subscription_profiles(current_setting('test.dispatch')::jsonb),
  '["7c1a0000-0000-0000-0000-000000000002"]'::jsonb,
  'match annulé : la liste des téléphones ne change pas'
);

select set_config(
  'test.dispatch',
  public.internal_push_dispatch(
    'prediction_j5',
    current_setting('test.match')::uuid
  )::text,
  true
);

select ok(
  (current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids')
    ? '7c1a0000-0000-0000-0000-000000000003'
  and (current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids')
    ? '7c1a0000-0000-0000-0000-000000000002'
  and not (current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids')
    ? '7c1a0000-0000-0000-0000-000000000004',
  'rappel de pronostic : le joueur sans téléphone est destinataire, pas le profil archivé'
);

select ok(
  not (pg_temp.subscription_profiles(current_setting('test.dispatch')::jsonb)
    ? '7c1a0000-0000-0000-0000-000000000003'),
  'rappel de pronostic : aucun téléphone n’est inventé pour le joueur sans appareil'
);

update public.profiles
set notify_prediction_reminders = false,
    updated_at = now()
where id = '7c1a0000-0000-0000-0000-000000000003';

select ok(
  not (
    public.internal_push_dispatch(
      'prediction_j5',
      current_setting('test.match')::uuid
    ) -> 'recipient_profile_ids'
  ) ? '7c1a0000-0000-0000-0000-000000000003',
  'rappel de pronostic : le réglage du compte retire aussi le joueur de l’historique'
);

select set_config(
  'test.dispatch',
  public.internal_push_dispatch(
    'motm_open',
    current_setting('test.played_match')::uuid
  )::text,
  true
);

select is(
  current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids',
  current_setting('test.device_and_no_device')::jsonb,
  'ouverture du vote : le joueur sans téléphone est destinataire, pas le profil archivé'
);

select is(
  pg_temp.subscription_profiles(current_setting('test.dispatch')::jsonb),
  '["7c1a0000-0000-0000-0000-000000000002"]'::jsonb,
  'ouverture du vote : la liste des téléphones ne change pas'
);

-- ---------------------------------------------------------------------------
-- Alertes du direct (internal_claim_match_live_notification)
-- ---------------------------------------------------------------------------

insert into public.match_live_notification_subscriptions (
  match_id, profile_id, completed_at
) values
  (current_setting('test.match')::uuid, '7c1a0000-0000-0000-0000-000000000002', null),
  (current_setting('test.match')::uuid, '7c1a0000-0000-0000-0000-000000000003', null),
  (current_setting('test.match')::uuid, '7c1a0000-0000-0000-0000-000000000004', null),
  (current_setting('test.match')::uuid, '7c1a0000-0000-0000-0000-000000000005', now());

insert into private.match_live_notification_events (
  id, match_id, kind, due_at, score_as_grinta, score_adverse
) values (
  '7c1e0000-0000-0000-0000-000000000001',
  current_setting('test.match')::uuid,
  'kickoff',
  now() - interval '1 second',
  0,
  0
);

insert into private.match_live_notification_event_targets (
  notification_id, profile_id
)
select '7c1e0000-0000-0000-0000-000000000001'::uuid, profile.id
from public.profiles profile
where profile.id in (
  '7c1a0000-0000-0000-0000-000000000002',
  '7c1a0000-0000-0000-0000-000000000003',
  '7c1a0000-0000-0000-0000-000000000004',
  '7c1a0000-0000-0000-0000-000000000005'
);

select set_config(
  'test.dispatch',
  public.internal_claim_match_live_notification(
    '7c1e0000-0000-0000-0000-000000000001'
  )::text,
  true
);

select is(
  current_setting('test.dispatch')::jsonb ->> 'claimed',
  'true',
  'l’alerte du direct est réservée'
);

select is(
  current_setting('test.dispatch')::jsonb -> 'recipient_profile_ids',
  current_setting('test.device_and_no_device')::jsonb,
  'direct : le joueur sans téléphone est destinataire, pas le profil archivé ni l’alerte terminée'
);

select is(
  pg_temp.subscription_profiles(current_setting('test.dispatch')::jsonb),
  '["7c1a0000-0000-0000-0000-000000000002"]'::jsonb,
  'direct : la liste des téléphones ne change pas'
);

select is(
  public.internal_claim_match_live_notification(
    '7c1e0000-0000-0000-0000-000000000001'
  ),
  jsonb_build_object('claimed', false),
  'une alerte déjà réservée ne renvoie toujours rien'
);

-- ---------------------------------------------------------------------------
-- Message écrit par un admin (admin_send_custom_push)
-- ---------------------------------------------------------------------------

select pg_temp.mark();

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_send_custom_push(
    'Entraînement',
    'Rendez-vous à 19 h au stade.',
    array[
      '7c1a0000-0000-0000-0000-000000000002',
      '7c1a0000-0000-0000-0000-000000000003',
      '7c1a0000-0000-0000-0000-000000000004'
    ]::uuid[]
  ),
  1,
  'le message renvoie toujours le nombre de destinataires qui ont un téléphone'
);

reset role;

select is(
  (
    select jsonb_agg(profile_id order by profile_id)
    from pg_temp.bodies_since_mark() body,
      jsonb_array_elements_text(body -> 'profile_ids') profile_id
  ),
  current_setting('test.device_and_no_device')::jsonb,
  'le message part vers tous les profils actifs choisis, téléphone ou non'
);

select pg_temp.mark();

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_send_custom_push(
    'Entraînement',
    'Rendez-vous à 19 h au stade.',
    array['7c1a0000-0000-0000-0000-000000000003']::uuid[]
  ),
  0,
  'un destinataire sans téléphone n’est plus une erreur : zéro téléphone'
);

select throws_ok(
  $$select public.admin_send_custom_push(
    'Entraînement',
    'Rendez-vous à 19 h au stade.',
    array['7c1a0000-0000-0000-0000-000000000004']::uuid[]
  )$$,
  '22023',
  'Aucun destinataire actif.',
  'une sélection sans aucun profil actif reste refusée'
);

reset role;

select is(
  (
    select jsonb_agg(body -> 'profile_ids')
    from pg_temp.bodies_since_mark() body
  ),
  '[["7c1a0000-0000-0000-0000-000000000003"]]'::jsonb,
  'le message vers le seul joueur sans téléphone part quand même, pour son historique'
);

-- ---------------------------------------------------------------------------
-- Relance manuelle des disponibilités
-- ---------------------------------------------------------------------------

update public.profiles
set notify_prediction_reminders = true,
    updated_at = now()
where id = '7c1a0000-0000-0000-0000-000000000003';

select pg_temp.mark();

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.reminder',
  public.admin_send_match_availability_reminder(
    current_setting('test.match')::uuid,
    null,
    'Relance pour l’historique'
  )::text,
  true
);

reset role;

select is(
  current_setting('test.reminder')::jsonb,
  jsonb_build_object(
    'target_count', 2,
    'created_count', 1,
    'skipped_recent_count', 0,
    'skipped_no_subscription_count', 1
  ),
  'le retour à l’admin garde son sens : le joueur sans téléphone reste à part'
);

select is(
  (
    select jsonb_agg(event.profile_id::text order by event.profile_id)
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'availability_manual'
  ),
  current_setting('test.device_and_no_device')::jsonb,
  'la relance est aussi créée pour le joueur sans téléphone'
);

select is(
  (
    select jsonb_agg(body #>> '{profile_ids,0}' order by body #>> '{profile_ids,0}')
    from pg_temp.bodies_since_mark() body
    where body ->> 'kind' = 'availability_manual'
  ),
  current_setting('test.device_and_no_device')::jsonb,
  'la relance du joueur sans téléphone part aussi, pour son historique'
);

select pg_temp.mark();

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_send_match_availability_reminder(
    current_setting('test.match')::uuid,
    null,
    'Seconde relance trop proche'
  ),
  jsonb_build_object(
    'target_count', 2,
    'created_count', 0,
    'skipped_recent_count', 1,
    'skipped_no_subscription_count', 1
  ),
  'une seconde relance dans les dix minutes ne crée rien'
);

reset role;

select is(
  (
    select count(*)
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'availability_manual'
  ),
  2::bigint,
  'le délai de dix minutes vaut aussi pour le joueur sans téléphone'
);

select is(
  (select count(*) from pg_temp.bodies_since_mark()),
  0::bigint,
  'aucun envoi n’est mis en file pendant le délai'
);

-- ---------------------------------------------------------------------------
-- Notification d'essai : jamais dans l'historique
-- ---------------------------------------------------------------------------

select pg_temp.mark();

select set_config(
  'request.jwt.claims',
  '{"sub":"7c1a0000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.send_test_push_kind('availability_open') ->> 'sent',
  'true',
  'l’essai part vers le téléphone du joueur'
);

reset role;

select is(
  (
    select jsonb_agg(
      jsonb_build_object(
        'kind', body -> 'kind',
        'record_history', body -> 'record_history'
      )
    )
    from pg_temp.bodies_since_mark() body
  ),
  '[{"kind":"custom","record_history":false}]'::jsonb,
  'l’essai demande explicitement à ne pas être gardé dans l’historique'
);

-- ---------------------------------------------------------------------------
-- Droits inchangés
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('authenticated', 'public.internal_push_dispatch(text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.internal_push_dispatch(text,uuid)', 'execute')
  and has_function_privilege('service_role', 'public.internal_push_dispatch(text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.internal_sport_push_dispatch(text,uuid,uuid[])', 'execute')
  and not has_function_privilege('anon', 'public.internal_sport_push_dispatch(text,uuid,uuid[])', 'execute')
  and has_function_privilege('service_role', 'public.internal_sport_push_dispatch(text,uuid,uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'public.internal_claim_match_live_notification(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.internal_claim_match_live_notification(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.internal_claim_match_live_notification(uuid)', 'execute'),
  'les préparations d’envoi restent réservées au service'
);

select ok(
  has_function_privilege('authenticated', 'public.admin_send_custom_push(text,text,uuid[])', 'execute')
  and not has_function_privilege('anon', 'public.admin_send_custom_push(text,text,uuid[])', 'execute')
  and has_function_privilege('authenticated', 'public.send_test_push_kind(text)', 'execute')
  and not has_function_privilege('anon', 'public.send_test_push_kind(text)', 'execute')
  and has_function_privilege('authenticated', 'private.send_sport_availability_reminder(uuid,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'private.send_sport_availability_reminder(uuid,uuid,text)', 'execute'),
  'les actions des joueurs et des admins gardent leurs droits'
);

select ok(
  (select provolatile = 's' from pg_proc where oid = 'public.internal_push_dispatch(text,uuid)'::regprocedure)
  and (select provolatile = 's' from pg_proc where oid = 'public.internal_sport_push_dispatch(text,uuid,uuid[])'::regprocedure),
  'les préparations d’envoi restent en lecture seule (STABLE)'
);

select * from finish();
rollback;
