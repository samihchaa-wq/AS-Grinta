-- Batterie de bout en bout : chaque notification de l'application.
--
-- Pour chaque notification, le test vérifie :
--   1. le moment ou l'événement qui la déclenche ;
--   2. qui la reçoit, et qui ne la reçoit pas ;
--   3. l'effet des réglages du joueur (réglage coupé, appareil non activé,
--      indisponibilité déclarée, compte inactif) ;
--   4. le coupe-circuit administrateur.
--
-- Rien ne part réellement : les envois sont lus dans la file de pg_net, à
-- l'intérieur de la transaction du test, puis tout est annulé.
--
-- Distribution des rôles :
--   Admin   administrateur, joueur de l'effectif, tout activé ;
--   Activ   joueur, tout activé ;
--   Coupe   joueur, tous les réglages facultatifs coupés ;
--   Absent  joueur, indisponibilité déclarée sur la date du match ;
--   Muet    joueur, n'a jamais activé les notifications sur son téléphone ;
--   Supp    compte actif hors effectif (supporter / pronostiqueur) ;
--   Attente joueur de l'effectif dont le compte n'est pas encore validé.

begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

update private.app_feature_flags
set enabled = true, updated_at = now()
where key = 'sports_management';

update private.app_feature_flags
set enabled = false, updated_at = now()
where key = 'notifications_paused';

-- ---------------------------------------------------------------------------
-- Comptes
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values
  ('e1000000-0000-0000-0000-000000000001', 'nfc-admin@example.invalid',
   '{"first_name":"Admin","last_name":"Club"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000002', 'nfc-activ@example.invalid',
   '{"first_name":"Activ","last_name":"Joueur"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000003', 'nfc-coupe@example.invalid',
   '{"first_name":"Coupe","last_name":"Joueur"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000004', 'nfc-absent@example.invalid',
   '{"first_name":"Absent","last_name":"Joueur"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000005', 'nfc-muet@example.invalid',
   '{"first_name":"Muet","last_name":"Joueur"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000006', 'nfc-supp@example.invalid',
   '{"first_name":"Supp","last_name":"Orter"}'::jsonb),
  ('e1000000-0000-0000-0000-000000000007', 'nfc-attente@example.invalid',
   '{"first_name":"Attente","last_name":"Joueur"}'::jsonb);

update public.profiles
set role = case when id = 'e1000000-0000-0000-0000-000000000001'
                then 'admin' else 'pronostiqueur' end,
    status = case when id = 'e1000000-0000-0000-0000-000000000007'
                  then 'pending' else 'active' end,
    surnom = case when id = 'e1000000-0000-0000-0000-000000000003'
                  then 'Le Surnom' else surnom end,
    notify_prediction_reminders = id <> 'e1000000-0000-0000-0000-000000000003',
    notify_motm_vote = id <> 'e1000000-0000-0000-0000-000000000003',
    notify_convocation = id <> 'e1000000-0000-0000-0000-000000000003',
    notify_composition = id <> 'e1000000-0000-0000-0000-000000000003',
    notify_badges = id <> 'e1000000-0000-0000-0000-000000000003',
    updated_at = now()
where id between 'e1000000-0000-0000-0000-000000000001'
             and 'e1000000-0000-0000-0000-000000000007';

-- Toutes les autres données de la base de test (comptes de démonstration)
-- sont mises hors jeu pour que les listes de destinataires ne portent que sur
-- ce scénario.
update public.profiles
set status = 'disabled'
where id not between 'e1000000-0000-0000-0000-000000000001'
                 and 'e1000000-0000-0000-0000-000000000007'
  and status = 'active';

-- Muet n'a pas d'appareil enregistré ; tous les autres en ont un.
insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth, user_agent)
select profile_id, 'https://push.example.invalid/nfc-' || right(profile_id::text, 1),
       'k', 'a', 'pgTAP'
from unnest(array[
  'e1000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000002',
  'e1000000-0000-0000-0000-000000000003',
  'e1000000-0000-0000-0000-000000000004',
  'e1000000-0000-0000-0000-000000000006',
  'e1000000-0000-0000-0000-000000000007'
]::uuid[]) as profile_id;

insert into public.seasons (id, name, status)
values ('e2000000-0000-0000-0000-000000000001', '2301-2302', 'open');
insert into public.opponents (id, name)
values ('e3000000-0000-0000-0000-000000000001', 'Notif FC');

insert into public.season_players (
  id, season_id, first_name, last_name,
  is_goalkeeper, is_active, is_coach, position, profile_id
)
values
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
   'Admin', 'Club', false, true, false, 1, 'e1000000-0000-0000-0000-000000000001'),
  ('e4000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001',
   'Activ', 'Joueur', false, true, false, 2, 'e1000000-0000-0000-0000-000000000002'),
  ('e4000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000001',
   'Coupe', 'Joueur', false, true, false, 3, 'e1000000-0000-0000-0000-000000000003'),
  ('e4000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-000000000001',
   'Absent', 'Joueur', false, true, false, 4, 'e1000000-0000-0000-0000-000000000004'),
  ('e4000000-0000-0000-0000-000000000005', 'e2000000-0000-0000-0000-000000000001',
   'Muet', 'Joueur', false, true, false, 5, 'e1000000-0000-0000-0000-000000000005'),
  ('e4000000-0000-0000-0000-000000000007', 'e2000000-0000-0000-0000-000000000001',
   'Attente', 'Joueur', false, true, false, 7, 'e1000000-0000-0000-0000-000000000007');

-- ---------------------------------------------------------------------------
-- Outils de lecture de la file d'envoi
-- ---------------------------------------------------------------------------

create or replace function pg_temp.mark()
returns void
language sql
as $function$
  select set_config(
    'test.mark',
    coalesce((select max(id) from net.http_request_queue), 0)::text,
    true
  );
$function$;

-- Envois mis en file depuis le dernier repère.
create or replace function pg_temp.sent()
returns setof jsonb
language sql
stable
as $function$
  select convert_from(queue.body, 'UTF8')::jsonb
  from net.http_request_queue queue
  where queue.id > current_setting('test.mark')::bigint
  order by queue.id;
$function$;

-- Destinataires d'un envoi « préparé » (convocation, liste d'attente,
-- composition, résultat HDM, badges, alertes admin) dont le titre est donné.
create or replace function pg_temp.recipients_of(p_title text)
returns uuid[]
language sql
stable
as $function$
  select coalesce(array_agg(distinct recipient::uuid order by recipient::uuid), '{}')
  from pg_temp.sent() body,
       jsonb_array_elements_text(body -> 'profile_ids') recipient
  where body ->> 'title' = p_title;
$function$;

-- Destinataires d'un envoi « générique », tels que send-push les calcule.
create or replace function pg_temp.dispatch_targets(p_kind text, p_match uuid)
returns uuid[]
language sql
stable
as $function$
  select coalesce(
    array_agg(distinct (sub ->> 'profile_id')::uuid
              order by (sub ->> 'profile_id')::uuid),
    '{}'
  )
  from jsonb_array_elements(
    public.internal_push_dispatch(p_kind, p_match) -> 'subscriptions'
  ) sub;
$function$;

create or replace function pg_temp.sport_targets(
  p_kind text, p_match uuid, p_profiles uuid[]
)
returns uuid[]
language sql
stable
as $function$
  select coalesce(
    array_agg(distinct (sub ->> 'profile_id')::uuid
              order by (sub ->> 'profile_id')::uuid),
    '{}'
  )
  from jsonb_array_elements(
    public.internal_sport_push_dispatch(p_kind, p_match, p_profiles)
      -> 'subscriptions'
  ) sub;
$function$;

create or replace function pg_temp.as_user(p_profile uuid)
returns void
language sql
as $function$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_profile, 'role', 'authenticated',
                      'aud', 'authenticated')::text,
    true
  );
$function$;

-- Retour à une session « serveur », sans utilisateur connecté.
create or replace function pg_temp.as_server()
returns void
language sql
as $function$
  select set_config('request.jwt.claims', '', true);
$function$;

create or replace function pg_temp.participant(p_match uuid, p_player text)
returns uuid
language sql
stable
as $function$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = p_match
    and participant.season_player_id
        = ('e4000000-0000-0000-0000-00000000000' || p_player)::uuid;
$function$;

-- ---------------------------------------------------------------------------
-- Match principal : amical dans 3 jours à 21 h, heure de Paris
-- ---------------------------------------------------------------------------

select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config(
  'test.match',
  public.create_match_with_odds_and_sport_limit(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    (now() at time zone 'Europe/Paris')::date + 3,
    time '21:00',
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);
reset role;

-- Absent déclare son indisponibilité sur la date du match.
select pg_temp.as_user('e1000000-0000-0000-0000-000000000004');
set local role authenticated;
select public.set_my_unavailability(
  null,
  (now() at time zone 'Europe/Paris')::date + 2,
  (now() at time zone 'Europe/Paris')::date + 4,
  'Vacances'
);
reset role;

select is(
  (
    select participant.availability_status::text
    from public.match_sport_participants participant
    where participant.id = pg_temp.participant(
      current_setting('test.match')::uuid, '4')
  ),
  'absent',
  'préalable : l''indisponibilité déclarée pose Absent comme absent'
);

-- ===========================================================================
-- 1. OUVERTURE DES DISPONIBILITÉS — J-6 à 12 h (essentielle)
-- ===========================================================================

select is(
  (
    select to_char(workflow.availability_opens_at at time zone 'Europe/Paris',
                   'HH24:MI')
           || ' / J-'
           || ((current_date + 3)
               - (workflow.availability_opens_at at time zone 'Europe/Paris')::date)
    from public.match_sport_workflows workflow
    where workflow.match_id = current_setting('test.match')::uuid
  ),
  '12:00 / J-6',
  'dispo : l''ouverture est planifiée à J-6, 12 h heure de Paris'
);

-- Avant l'heure : rien.
update public.match_sport_workflows
set availability_opens_at = now() + interval '1 minute',
    availability_state = 'pending',
    availability_opened_at = null
where match_id = current_setting('test.match')::uuid;

select is(
  (private.process_sport_availability_notifications(now())
     ->> 'notifications_created')::integer,
  0,
  'dispo : aucune notification avant l''heure d''ouverture'
);

-- À l'heure : envoi.
update public.match_sport_workflows
set availability_opens_at = now() - interval '1 minute'
where match_id = current_setting('test.match')::uuid;

select pg_temp.mark();
select is(
  (private.process_sport_availability_notifications(now())
     ->> 'notifications_created')::integer,
  4,
  'dispo : à l''heure, quatre joueurs sont visés (Admin, Activ, Coupe, Muet)'
);

select is(
  (
    select array_agg(event.profile_id order by event.profile_id)
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'availability_open'
  ),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000003',
    'e1000000-0000-0000-0000-000000000005'
  ]::uuid[],
  'dispo : ni l''indisponible, ni le supporter, ni le compte non validé'
);

select is(
  pg_temp.sport_targets(
    'availability_open', current_setting('test.match')::uuid,
    array[
      'e1000000-0000-0000-0000-000000000001',
      'e1000000-0000-0000-0000-000000000002',
      'e1000000-0000-0000-0000-000000000003',
      'e1000000-0000-0000-0000-000000000005'
    ]::uuid[]
  ),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'dispo : Coupe la reçoit malgré ses réglages (essentielle), Muet non (pas d''appareil)'
);

select is(
  (select count(*)::integer from pg_temp.sent() body
   where body ->> 'kind' = 'availability_open'),
  4,
  'dispo : une demande d''envoi par joueur visé'
);

select is(
  (private.process_sport_availability_notifications(now())
     ->> 'notifications_created')::integer,
  0,
  'dispo : le passage suivant (chaque minute) ne renvoie rien'
);

-- CONSTAT (défaut) : un admin qui modifie l'heure d'ouverture alors que les
-- dispos sont déjà ouvertes renvoie « Es-tu disponible ? » à tout le monde,
-- y compris à ceux qui ont déjà répondu.
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_update_match_complete_v3(
  m.id, m.season_id, m.opponent_id, m.match_date, m.match_time, m.location,
  'a_venir', 2, 3, 2, m.updated_at, 14, null, false, m.match_type, null, null,
  'custom', now() - interval '2 hours'
)
from public.matches m
where m.id = current_setting('test.match')::uuid;
reset role;
select pg_temp.as_server();

select todo_start('défaut connu : modifier l''ouverture après coup renvoie la demande');
select is(
  (
    select count(*)::integer
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'availability_open'
  ),
  4,
  'dispo : modifier l''heure d''ouverture après coup ne renvoie pas la demande'
);
select todo_end();

-- ===========================================================================
-- 2. CHANGEMENT DE DISPONIBILITÉ — alerte aux administrateurs
-- ===========================================================================

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null);
reset role;

select is(
  pg_temp.recipients_of('Changement de disponibilité'),
  '{}'::uuid[],
  'alerte admin : la première réponse (sans réponse -> présent) n''alerte pas'
);

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'absent', null);
reset role;

select is(
  pg_temp.recipients_of('Changement de disponibilité'),
  array['e1000000-0000-0000-0000-000000000001']::uuid[],
  'alerte admin : présent -> absent alerte immédiatement les administrateurs'
);

select pg_temp.mark();
select pg_temp.as_server();
update public.profiles
set notify_admin_availability_change = false
where id = 'e1000000-0000-0000-0000-000000000001';
select pg_temp.as_user('e1000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null);
reset role;
select pg_temp.as_server();
update public.profiles
set notify_admin_availability_change = true
where id = 'e1000000-0000-0000-0000-000000000001';

select is(
  pg_temp.recipients_of('Changement de disponibilité'),
  '{}'::uuid[],
  'alerte admin : un admin qui a coupé ce réglage ne la reçoit plus'
);

-- ===========================================================================
-- 3. RELANCE MANUELLE DU STAFF (essentielle, déclenchée à la main)
-- ===========================================================================

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config(
  'test.reminder',
  public.admin_send_match_availability_reminder(
    current_setting('test.match')::uuid, null, null)::text,
  true
);
reset role;

select is(
  current_setting('test.reminder')::jsonb - 'skipped_recent_count',
  '{"target_count": 3, "created_count": 2, "skipped_no_subscription_count": 1}'::jsonb,
  'relance : vise les trois sans réponse, saute Muet faute d''appareil'
);

select is(
  (
    select array_agg(event.profile_id order by event.profile_id)
    from public.sport_availability_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'availability_manual'
  ),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'relance : ni Activ (a répondu) ni Absent (indisponibilité = réponse posée)'
);

select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select is(
  (public.admin_send_match_availability_reminder(
     current_setting('test.match')::uuid, null, null) ->> 'skipped_recent_count')::integer,
  2,
  'relance : une deuxième relance dans les 10 minutes est bloquée (anti-spam)'
);
reset role;


-- ===========================================================================
-- 4. CONVOCATION / LISTE D'ATTENTE (essentielle)
-- ===========================================================================

select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null);
reset role;
select pg_temp.as_user('e1000000-0000-0000-0000-000000000003');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match')::uuid, 'available', null);
reset role;

-- Publication de la liste des convoqués par l'administrateur.
select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_publish_match_convocations(
  current_setting('test.match')::uuid, null);
reset role;

select is(
  (
    select array_agg(player.profile_id order by player.profile_id)
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    where participant.match_id = current_setting('test.match')::uuid
      and participant.convocation_status = 'convoked'
  ),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'convocation : préalable, Admin, Activ et Coupe sont convoqués'
);

-- CONSTAT : la publication initiale ne prévient personne.
select is(
  (select count(*)::integer from pg_temp.sent()),
  0,
  'convocation : la publication de la liste n''envoie AUCUNE notification aux convoqués'
);

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_set_match_convocation(
  current_setting('test.match')::uuid,
  'e4000000-0000-0000-0000-000000000003', 'not_convoked', false, null);
reset role;

select is(
  pg_temp.recipients_of('Tu passes en liste d''attente'),
  array['e1000000-0000-0000-0000-000000000003']::uuid[],
  'liste d''attente : convoqué -> liste d''attente prévient le joueur, tout de suite'
);

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.admin_set_match_convocation(
  current_setting('test.match')::uuid,
  'e4000000-0000-0000-0000-000000000003', 'convoked', false, null);
reset role;

select is(
  pg_temp.recipients_of('Tu es convoqué'),
  array['e1000000-0000-0000-0000-000000000003']::uuid[],
  'convocation : liste d''attente -> convoqué prévient le joueur, même réglage « convocation » coupé'
);

-- ===========================================================================
-- 5. COMPOSITION EN LIGNE (facultative)
-- ===========================================================================

select pg_temp.mark();
select ok(
  private.notify_composition_published(current_setting('test.match')::uuid),
  'composition : la première mise en ligne déclenche l''envoi'
);

select is(
  pg_temp.recipients_of('La composition est en ligne'),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002'
  ]::uuid[],
  'composition : seuls les convoqués réglage activé (pas Coupe, pas les non-convoqués)'
);

select ok(
  not private.notify_composition_published(current_setting('test.match')::uuid),
  'composition : une mise à jour ultérieure ne renotifie personne'
);

-- ===========================================================================
-- 6. RAPPEL PRONOSTIC — jour du match à 16 h (facultatif)
-- ===========================================================================

select is(
  to_char(
    private.match_prediction_notification_at(
      (select kickoff_at from public.matches
       where id = current_setting('test.match')::uuid)
    ) at time zone 'Europe/Paris',
    'HH24:MI'
  ) || ' le jour J',
  '16:00 le jour J',
  'prono : rappel planifié le jour du match à 16 h, heure de Paris'
);

select pg_temp.as_server();
insert into public.match_predictions (
  match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse,
  is_filled
) values (
  current_setting('test.match')::uuid,
  'e1000000-0000-0000-0000-000000000002', 2, 1, true
)
on conflict (match_id, profile_id) do update
set is_filled = true, predicted_score_as_grinta = 2, predicted_score_adverse = 1;

select is(
  pg_temp.dispatch_targets('prediction_j5', current_setting('test.match')::uuid),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000004',
    'e1000000-0000-0000-0000-000000000006'
  ]::uuid[],
  'prono : tous les comptes actifs sans prono (supporter compris), sauf réglage coupé, sauf déjà pronostiqué'
);

-- CONSTAT : un match qui commence avant 16 h 15 n'a jamais de rappel,
-- puisque le rappel (16 h) tombe après la fermeture des pronostics (T-15).
select ok(
  private.match_prediction_notification_at('2030-05-12 14:00:00+00'::timestamptz)
    >= private.match_prediction_closes_at('2030-05-12 14:00:00+00'::timestamptz),
  'prono : un match à 16 h (Paris) ne reçoit jamais de rappel'
);

-- ===========================================================================
-- 7. LIVE — coup d'envoi, buts, fin de match (sur abonnement, match par match)
-- ===========================================================================

select pg_temp.as_user('e1000000-0000-0000-0000-000000000002');
set local role authenticated;
select is(
  public.set_match_live_notifications(current_setting('test.match')::uuid, true)
    ->> 'subscribed',
  'true',
  'live : un joueur peut s''abonner à un match dès l''ouverture des dispos'
);
reset role;
select pg_temp.as_server();

insert into public.match_live_sessions (
  match_id, state, planned_duration_minutes, updated_by
) values (
  current_setting('test.match')::uuid, 'not_started', 90,
  'e1000000-0000-0000-0000-000000000001'
);

update public.match_live_sessions
set state = 'running', started_at = now(), running_since = now()
where match_id = current_setting('test.match')::uuid;

select is(
  (
    select array_agg(target.profile_id)
    from private.match_live_notification_events event
    join private.match_live_notification_event_targets target
      on target.notification_id = event.id
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'kickoff'
  ),
  array['e1000000-0000-0000-0000-000000000002']::uuid[],
  'live : coup d''envoi -> uniquement les abonnés à ce match (personne d''autre)'
);

update public.match_live_sessions
set score_adverse = 1
where match_id = current_setting('test.match')::uuid;
insert into public.match_live_events (
  match_id, event_type, minute, half, created_by,
  score_as_grinta_after, score_adverse_after
) values (
  current_setting('test.match')::uuid, 'goal_them', 10, 1,
  'e1000000-0000-0000-0000-000000000001', null, 1
);

select is(
  (
    select event.due_at <= now()
    from private.match_live_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'goal_them'
  ),
  true,
  'live : but adverse -> envoi immédiat'
);

update public.match_live_sessions
set score_as_grinta = 1
where match_id = current_setting('test.match')::uuid;
insert into public.match_live_events (
  match_id, event_type, minute, half, created_by,
  score_as_grinta_after, score_adverse_after
) values (
  current_setting('test.match')::uuid, 'goal_us', 20, 1,
  'e1000000-0000-0000-0000-000000000001', 1, null
);

select is(
  (
    select round(extract(epoch from event.due_at - now()))::integer
    from private.match_live_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'goal_us'
  ),
  60,
  'live : but du club sans buteur -> attend 60 s qu''on renseigne le buteur'
);

update public.match_live_sessions
set state = 'finished', finished_at = now(), running_since = null
where match_id = current_setting('test.match')::uuid;

select ok(
  exists (
    select 1 from private.match_live_notification_events event
    where event.match_id = current_setting('test.match')::uuid
      and event.kind = 'full_time'
  ),
  'live : fin du Live -> notification de fin de match'
);

select is(
  (
    select count(*)::integer
    from private.match_live_notification_event_targets target
    join private.match_live_notification_events event
      on event.id = target.notification_id
    where event.match_id = current_setting('test.match')::uuid
      and target.profile_id <> 'e1000000-0000-0000-0000-000000000002'
  ),
  0,
  'live : les non-abonnés ne reçoivent aucune notification de Live'
);

-- ===========================================================================
-- 8. HOMME DU MATCH — ouverture du vote puis résultat (facultatif, 1 réglage)
-- ===========================================================================

update public.match_sport_participants
set final_presence_status = 'present'
where match_id = current_setting('test.match')::uuid
  and season_player_id in (
    'e4000000-0000-0000-0000-000000000001',
    'e4000000-0000-0000-0000-000000000002',
    'e4000000-0000-0000-0000-000000000003'
  );

select pg_temp.mark();
insert into public.match_sport_motm_elections (
  match_id, finalization_version, state, opens_at, closes_at
) values (
  current_setting('test.match')::uuid, 1, 'open',
  now() - interval '1 minute', now() + interval '24 hours'
)
on conflict (match_id) do update
set state = 'open', opens_at = excluded.opens_at,
    closes_at = excluded.closes_at, finalization_version = 1;

select is(
  (select count(*)::integer from pg_temp.sent() body
   where body ->> 'kind' = 'motm_open'),
  1,
  'HDM : l''ouverture du vote déclenche l''envoi immédiatement'
);

select is(
  pg_temp.dispatch_targets('motm_open', current_setting('test.match')::uuid),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002'
  ]::uuid[],
  'HDM ouverture : seuls les joueurs présents au match, réglage HDM activé'
);

insert into public.match_sport_motm_results (
  match_id, participant_id, finalization_version, votes_count, is_winner
) values (
  current_setting('test.match')::uuid,
  pg_temp.participant(current_setting('test.match')::uuid, '3'),
  1, 2, true
);

select pg_temp.mark();
update public.match_sport_motm_elections
set state = 'closed', closed_at = now()
where match_id = current_setting('test.match')::uuid;

select is(
  pg_temp.recipients_of('Homme du match'),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002'
  ]::uuid[],
  'HDM résultat : envoyé aux mêmes joueurs que l''ouverture, dès la clôture'
);

select is(
  (
    select count(*)::integer from pg_temp.sent() body
    where body ->> 'message' like 'Bravo%'
  ),
  0,
  'HDM résultat : l''élu qui a coupé le réglage HDM ne reçoit pas son « Bravo »'
);

-- CONSTAT (défaut) : quand l'élu a coupé son réglage HDM, son surnom n'est
-- plus utilisé dans l'annonce faite aux autres.
select todo_start('défaut connu : le nom de l''élu dépend de SON réglage HDM');
select is(
  (select body ->> 'message' from pg_temp.sent() body
   where body ->> 'title' = 'Homme du match' limit 1),
  'Le Surnom a été élu Homme du match !',
  'HDM résultat : l''élu est annoncé sous son surnom, quels que soient ses réglages'
);
select todo_end();

-- ===========================================================================
-- 9. BADGE DÉBLOQUÉ (facultatif) — regroupé, 45 s après le dernier badge
-- ===========================================================================

insert into public.badges (
  id, code, name, description, emoji, family, auto, sort_order, kind,
  category, color
) values (
  'e5000000-0000-0000-0000-000000000001', 'nfc_test_badge', 'Badge Test',
  'Badge de test', '🧪', 'joueur', false, 999941, 'custom', 'faits_de_jeu', '#F97316'
);

insert into public.profile_badges (profile_id, badge_id, source)
values
  ('e1000000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001', 'manual'),
  ('e1000000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000001', 'manual');

select pg_temp.mark();
select is(
  private.process_badge_unlock_notifications(now() + interval '30 seconds'),
  0,
  'badge : rien avant 45 s (on attend d''éventuels autres badges)'
);
select is(
  private.process_badge_unlock_notifications(now() + interval '1 minute'),
  1,
  'badge : envoyé une fois les 45 s écoulées'
);
select is(
  (select array_agg(distinct recipient::uuid)
   from pg_temp.sent() body,
        jsonb_array_elements_text(body -> 'profile_ids') recipient
   where body ->> 'url' = 'armoire'),
  array['e1000000-0000-0000-0000-000000000002']::uuid[],
  'badge : seul le joueur réglage activé le reçoit (pas Coupe)'
);

-- ===========================================================================
-- 10. ALERTES ET MESSAGES ADMINISTRATEUR
-- ===========================================================================

select pg_temp.mark();
insert into auth.users (id, email, raw_user_meta_data)
values ('e1000000-0000-0000-0000-000000000008', 'nfc-nouveau@example.invalid',
        '{"first_name":"Nouveau","last_name":"Venu"}'::jsonb);

select is(
  (
    select body -> 'profile_ids'
    from pg_temp.sent() body
    where body ->> 'kind' = 'admin_pending_signup'
  ),
  '["e1000000-0000-0000-0000-000000000001"]'::jsonb,
  'nouveau compte : tous les admins actifs sont prévenus immédiatement'
);

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select is(
  public.admin_send_custom_push(
    'Info', 'Message du club',
    array['e1000000-0000-0000-0000-000000000002',
          'e1000000-0000-0000-0000-000000000005']::uuid[]
  ),
  1,
  'message libre : seuls les destinataires ayant activé un appareil sont comptés'
);
reset role;

select is(
  pg_temp.recipients_of('Info'),
  array['e1000000-0000-0000-0000-000000000002']::uuid[],
  'message libre : Muet (pas d''appareil) n''est pas visé'
);

-- ===========================================================================
-- 11. MATCH : HORAIRE MODIFIÉ, REPORTÉ, ANNULÉ (essentielles)
-- ===========================================================================

-- Second match, vierge (le premier a été joué en Live plus haut et est donc
-- verrouillé) : dispos ouvertes, Activ a répondu présent.
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config(
  'test.match2',
  public.create_match_with_odds_and_sport_limit(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    (now() at time zone 'Europe/Paris')::date + 4,
    time '21:00',
    'exterieur', 2.10, 3.20, 2.90, 14
  )::text,
  true
);
reset role;
select pg_temp.as_server();
select private.process_sport_availability_notifications(now());
select pg_temp.as_user('e1000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.set_my_match_availability(
  current_setting('test.match2')::uuid, 'available', null);
reset role;

-- Modification par l'écran « Modifier le match » de l'administrateur.
create or replace function pg_temp.admin_edit(p_match uuid, p_days integer, p_time time)
returns boolean
language sql
as $function$
  select public.admin_update_match_complete_v3(
    m.id, m.season_id, m.opponent_id, m.match_date + p_days, p_time,
    m.location, 'a_venir', 2, 3, 2, m.updated_at, 14, null, false,
    m.match_type, null, null, null, null
  )
  from public.matches m
  where m.id = p_match;
$function$;

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.admin_edit(current_setting('test.match2')::uuid, 0, time '21:30');
reset role;
select pg_temp.as_server();

select is(
  (select array_agg(body ->> 'kind') from pg_temp.sent() body
   where body ->> 'kind' like 'match_%'),
  array['match_rescheduled_time'],
  'horaire : changement d''heure le même jour -> « Horaire du match modifié »'
);

select is(
  pg_temp.dispatch_targets('match_rescheduled_time', current_setting('test.match2')::uuid),
  array[
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000003',
    'e1000000-0000-0000-0000-000000000004'
  ]::uuid[],
  'horaire/report/annulation : tout l''effectif équipé, indisponible compris, sans réglage possible'
);

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select pg_temp.admin_edit(current_setting('test.match2')::uuid, 1, time '21:30');
reset role;
select pg_temp.as_server();

select is(
  (select array_agg(body ->> 'kind') from pg_temp.sent() body
   where body ->> 'kind' like 'match_%'),
  array['match_rescheduled_date'],
  'report : changement de jour -> « Match reporté »'
);

select is(
  (
    select count(*)::integer
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.match2')::uuid
      and participant.is_eligible
      and participant.availability_status <> 'no_response'
      and not participant.availability_forced_by_unavailability
  ),
  0,
  'report : les disponibilités sont remises à zéro (redemandées)'
);

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.cancel_match(current_setting('test.match2')::uuid);
reset role;
select pg_temp.as_server();

select is(
  (select array_agg(body ->> 'kind') from pg_temp.sent() body
   where body ->> 'kind' like 'match_%'),
  array['match_cancelled'],
  'annulation : « Match annulé » immédiatement'
);

-- Match lointain, dispos pas encore ouvertes : l'annulation est silencieuse.
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select set_config(
  'test.far_match',
  public.create_match_with_odds_and_sport_limit(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    (now() at time zone 'Europe/Paris')::date + 20,
    time '21:00',
    'exterieur', 2.10, 3.20, 2.90, 14
  )::text,
  true
);
reset role;
select pg_temp.as_server();

select pg_temp.mark();
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select public.cancel_match(current_setting('test.far_match')::uuid);
reset role;
select pg_temp.as_server();

select is(
  (select count(*)::integer from pg_temp.sent() body
   where body ->> 'kind' like 'match_%'),
  0,
  'annulation : avant l''ouverture des dispos (J-6 12 h), personne n''est prévenu'
);

-- ===========================================================================
-- 12. COUPE-CIRCUIT ADMINISTRATEUR
-- ===========================================================================

update private.app_feature_flags
set enabled = true
where key = 'notifications_paused';

select pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
set local role authenticated;
select throws_ok(
  $$select public.admin_send_custom_push('Info', 'x',
      array['e1000000-0000-0000-0000-000000000002']::uuid[])$$,
  '55000',
  null,
  'coupe-circuit : le message libre est refusé'
);
reset role;
select pg_temp.as_server();

select pg_temp.mark();
select is(
  private.process_badge_unlock_notifications(now() + interval '1 minute')
  + (private.process_sport_availability_notifications(now())
       ->> 'notifications_created')::integer
  + public.push_prediction_j5_notifications(),
  0,
  'coupe-circuit : les tâches automatiques ne créent aucun envoi'
);

select * from finish();
rollback;
