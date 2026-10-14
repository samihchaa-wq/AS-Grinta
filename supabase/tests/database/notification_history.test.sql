begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- ---------------------------------------------------------------------------
-- Historique des notifications
--
-- Chaque envoi du club est rangé pour chacun de ses destinataires, même sans
-- téléphone abonné. Le joueur relit son historique, voit combien de
-- notifications il n'a pas lues, les marque comme lues en ouvrant l'écran et
-- peut en supprimer une. Faire ce qu'une notification demandait (répondre à
-- la disponibilité, remplir son pronostic, voter) la marque comme lue.
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values
  ('c7000000-0000-0000-0000-000000000001',
   'history-admin@example.invalid',
   '{"first_name":"Admin","last_name":"Historique"}'::jsonb),
  ('c7000000-0000-0000-0000-000000000002',
   'history-alice@example.invalid',
   '{"first_name":"Alice","last_name":"Sans Téléphone"}'::jsonb),
  ('c7000000-0000-0000-0000-000000000003',
   'history-bruno@example.invalid',
   '{"first_name":"Bruno","last_name":"Joueur"}'::jsonb),
  ('c7000000-0000-0000-0000-000000000004',
   'history-archie@example.invalid',
   '{"first_name":"Archie","last_name":"Archivé"}'::jsonb);

update public.profiles
set role = case
      when id = 'c7000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'c7000000-0000-0000-0000-000000000001'
  and 'c7000000-0000-0000-0000-000000000004';

insert into public.seasons (id, name, status)
values ('c7100000-0000-0000-0000-000000000001', '2095-2096', 'open');

insert into public.opponents (id, name)
values ('c7200000-0000-0000-0000-000000000001', 'Historique FC');

-- Alice n'a aucun téléphone abonné : son historique doit exister quand même.
insert into public.season_players (
  id, season_id, first_name, last_name,
  is_goalkeeper, is_active, is_coach, position, profile_id
)
values
  ('c7300000-0000-0000-0000-000000000001',
   'c7100000-0000-0000-0000-000000000001',
   'Alice', 'Sans Téléphone', false, true, false, 1,
   'c7000000-0000-0000-0000-000000000002'),
  ('c7300000-0000-0000-0000-000000000002',
   'c7100000-0000-0000-0000-000000000001',
   'Bruno', 'Joueur', false, true, false, 2,
   'c7000000-0000-0000-0000-000000000003');

insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth, user_agent)
values
  ('c7000000-0000-0000-0000-000000000003',
   'https://push.example.invalid/history-bruno', 'k1', 'a1', 'pgTAP');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'c7000000-0000-0000-0000-000000000001'
where key = 'sports_management';

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'c7000000-0000-0000-0000-000000000001'
where key = 'notifications_paused';

select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- Match dans trois jours : pronostics et disponibilités ouverts.
select set_config(
  'test.history_match',
  public.create_match_with_odds_and_sport_limit(
    'c7100000-0000-0000-0000-000000000001',
    'c7200000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile', 2.10, 3.20, 2.90, 14
  )::text,
  true
);

reset role;

-- Un second match, pour vérifier qu'une action sur l'un ne touche pas l'autre.
insert into public.matches (
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by
)
values (
  'c7400000-0000-0000-0000-000000000002',
  'c7100000-0000-0000-0000-000000000001',
  'c7200000-0000-0000-0000-000000000001',
  date '2095-12-01', time '20:00', 'exterieur', 90, 'a_venir',
  'c7000000-0000-0000-0000-000000000001'
);

update public.match_sport_workflows
set availability_opens_at = now() - interval '1 hour',
    availability_state = 'open',
    availability_opened_at = now() - interval '1 hour'
where match_id = current_setting('test.history_match')::uuid;

-- Le profil archivé l'est après la création du match, comme dans la vie.
update public.profiles
set status = 'archived', updated_at = now()
where id = 'c7000000-0000-0000-0000-000000000004';

-- ---------------------------------------------------------------------------
-- 1. Droits : la table est fermée, l'enregistrement est réservé au service
--    interne, la lecture aux comptes connectés.
-- ---------------------------------------------------------------------------

select ok(
  (
    select relation.relrowsecurity
    from pg_class relation
    where relation.oid = 'private.notification_history'::regclass
  ),
  'la table de l’historique garde la RLS active'
);

select ok(
  not has_table_privilege('anon', 'private.notification_history', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'private.notification_history', 'SELECT,INSERT,UPDATE,DELETE'),
  'aucun client ne lit ni n’écrit la table directement'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.internal_record_notification_history(text,uuid,uuid[],text,text,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.internal_record_notification_history(text,uuid,uuid[],text,text,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.internal_record_notification_history(text,uuid,uuid[],text,text,text,text,text)',
    'EXECUTE'
  ),
  'seul le service interne peut ranger une notification'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.get_my_notification_history(integer)',
      'public.get_my_unread_notification_count()',
      'public.mark_my_notifications_read()',
      'public.delete_my_notification(bigint)'
    ]) as signature
    where has_function_privilege('authenticated', signature, 'EXECUTE')
      and has_function_privilege('service_role', signature, 'EXECUTE')
      and not has_function_privilege('anon', signature, 'EXECUTE')
  ),
  4::bigint,
  'les quatre RPC du joueur sont réservées aux comptes connectés'
);

select is(
  (
    select count(*)
    from unnest(array[
      'private.mark_notifications_read_on_availability_answer()',
      'private.mark_notifications_read_on_prediction()',
      'private.mark_notifications_read_on_motm_vote()'
    ]) as signature
    where has_function_privilege('authenticated', signature, 'EXECUTE')
      or has_function_privilege('anon', signature, 'EXECUTE')
  ),
  0::bigint,
  'les fonctions des déclencheurs ne sont pas appelables par un client'
);

-- ---------------------------------------------------------------------------
-- 2. Enregistrement
-- ---------------------------------------------------------------------------

set local role service_role;

select set_config(
  'test.first_unread',
  public.internal_record_notification_history(
    'availability_open',
    'c7400000-0000-0000-0000-000000000002',
    array[
      'c7000000-0000-0000-0000-000000000002',
      'c7000000-0000-0000-0000-000000000002',
      'c7000000-0000-0000-0000-000000000003',
      'c7000000-0000-0000-0000-000000000004',
      'c7000000-0000-0000-0000-000000000099'
    ]::uuid[],
    '  Disponibilité  ',
    '  Es-tu disponible ?  ',
    'matches?match=c7400000-0000-0000-0000-000000000002',
    'sport-c7400000-availability-open',
    null
  )::text,
  true
);

reset role;

select is(
  current_setting('test.first_unread')::jsonb,
  jsonb_build_object(
    'c7000000-0000-0000-0000-000000000002', 1,
    'c7000000-0000-0000-0000-000000000003', 1
  ),
  'le nombre de non lues est rendu pour chaque destinataire actif, et pour eux seuls'
);

select is(
  (
    select count(*)
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
  ),
  1::bigint,
  'un destinataire répété ne reçoit qu’une ligne'
);

select is(
  (
    select count(*)
    from private.notification_history
    where profile_id in (
      'c7000000-0000-0000-0000-000000000004',
      'c7000000-0000-0000-0000-000000000099'
    )
  ),
  0::bigint,
  'un profil archivé ou inconnu ne reçoit rien'
);

select ok(
  exists (
    select 1
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
      and kind = 'availability_open'
      and match_id = 'c7400000-0000-0000-0000-000000000002'
      and title = 'Disponibilité'
      and body = 'Es-tu disponible ?'
      and url = 'matches?match=c7400000-0000-0000-0000-000000000002'
      and tag = 'sport-c7400000-availability-open'
      and dedupe_key is null
      and read_at is null
  ),
  'la ligne garde le type, le match, les textes nettoyés, l’adresse et l’étiquette'
);

set local role service_role;

select set_config(
  'test.dedupe_first',
  public.internal_record_notification_history(
    'live_goal_us', 'c7400000-0000-0000-0000-000000000002',
    array['c7000000-0000-0000-0000-000000000002']::uuid[],
    'But !', 'Ça fait 1-0.', 'matches/x/lineup?section=live',
    'live-x-goal-1', 'live:42'
  )::text,
  true
);

select set_config(
  'test.dedupe_second',
  public.internal_record_notification_history(
    'live_goal_us', 'c7400000-0000-0000-0000-000000000002',
    array['c7000000-0000-0000-0000-000000000002']::uuid[],
    'But !', 'Ça fait 1-0.', 'matches/x/lineup?section=live',
    'live-x-goal-1', 'live:42'
  )::text,
  true
);

reset role;

select is(
  (
    select count(*)
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
      and dedupe_key = 'live:42'
  ),
  1::bigint,
  'un même envoi rejoué n’est rangé qu’une fois'
);

select is(
  current_setting('test.dedupe_second')::jsonb,
  jsonb_build_object('c7000000-0000-0000-0000-000000000002', 2),
  'le rejeu rend toujours le bon nombre de non lues'
);

set local role service_role;

select lives_ok(
  $$
    select public.internal_record_notification_history(
      'composition_published',
      'c7900000-0000-0000-0000-000000000001',
      array['c7000000-0000-0000-0000-000000000003']::uuid[],
      'La composition est en ligne', '', null, null, null
    )
  $$,
  'un match supprimé ne fait pas échouer l’enregistrement'
);

reset role;

select ok(
  exists (
    select 1
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000003'
      and kind = 'composition_published'
      and match_id is null
      and url is null
      and tag is null
  ),
  'la notification d’un match supprimé est gardée sans match'
);

set local role service_role;

select set_config(
  'test.blank_title',
  public.internal_record_notification_history(
    'custom', null,
    array['c7000000-0000-0000-0000-000000000002']::uuid[],
    '   ', 'Sans titre', '.', null, null
  )::text,
  true
);

select lives_ok(
  $$
    select public.internal_record_notification_history(
      'Pas Un Type !', null,
      array['c7000000-0000-0000-0000-000000000003']::uuid[],
      repeat('é', 250),
      repeat('b', 1200),
      'https://exemple.invalid/' || repeat('a', 600),
      repeat('t', 300),
      null
    )
  $$,
  'des textes trop longs ne font pas échouer l’enregistrement'
);

reset role;

select is(
  current_setting('test.blank_title')::jsonb,
  jsonb_build_object('c7000000-0000-0000-0000-000000000002', 2),
  'une notification sans titre n’est pas rangée mais le compteur est rendu'
);

select is(
  (
    select count(*)
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
  ),
  2::bigint,
  'aucune ligne sans titre n’est créée'
);

select ok(
  exists (
    select 1
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000003'
      and kind = 'custom'
      and char_length(title) = 200
      and char_length(body) = 1000
      and url is null
      and char_length(tag) = 200
  ),
  'les textes sont coupés aux limites, une adresse trop longue est écartée, un type invalide devient custom'
);

-- Pause des notifications : rien n'est envoyé, donc rien n'est rangé.
update private.app_feature_flags
set enabled = true, updated_at = now()
where key = 'notifications_paused';

set local role service_role;

select set_config(
  'test.paused',
  public.internal_record_notification_history(
    'badge_unlocked', null,
    array['c7000000-0000-0000-0000-000000000002']::uuid[],
    'Nouveau badge', 'Bravo', 'armoire', null, null
  )::text,
  true
);

reset role;

update private.app_feature_flags
set enabled = false, updated_at = now()
where key = 'notifications_paused';

select is(
  (
    select count(*)
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
      and kind = 'badge_unlocked'
  ),
  0::bigint,
  'rien n’est rangé pendant la pause des notifications'
);

select is(
  current_setting('test.paused')::jsonb,
  jsonb_build_object('c7000000-0000-0000-0000-000000000002', 2),
  'pendant la pause, le compteur reste rendu'
);

-- Purge : une ligne de plus de 90 jours disparaît au prochain enregistrement.
insert into private.notification_history (
  id, profile_id, kind, title, created_at
)
values (
  900000001, 'c7000000-0000-0000-0000-000000000003', 'custom',
  'Très ancienne', now() - interval '91 days'
);

set local role service_role;

select public.internal_record_notification_history(
  'custom', null,
  array['c7000000-0000-0000-0000-000000000002']::uuid[],
  'Message du club', 'Bonjour', '.', null, null
);

reset role;

select ok(
  not exists (
    select 1 from private.notification_history where id = 900000001
  ),
  'une notification de plus de 90 jours est purgée'
);

-- ---------------------------------------------------------------------------
-- 3. Lecture, compteur, lu et suppression par le joueur
-- ---------------------------------------------------------------------------

delete from private.notification_history
where profile_id between
  'c7000000-0000-0000-0000-000000000001'
  and 'c7000000-0000-0000-0000-000000000004';

insert into private.notification_history (
  id, profile_id, kind, title, body, created_at, read_at
)
values
  (900000011, 'c7000000-0000-0000-0000-000000000002', 'custom', 'Ancienne', '', now() - interval '3 hours', null),
  (900000012, 'c7000000-0000-0000-0000-000000000002', 'custom', 'Récente', '', now() - interval '1 hour', null),
  (900000013, 'c7000000-0000-0000-0000-000000000002', 'custom', 'Récente bis', '', now() - interval '1 hour', null),
  (900000014, 'c7000000-0000-0000-0000-000000000002', 'custom', 'Trop vieille', '', now() - interval '91 days', null),
  (900000015, 'c7000000-0000-0000-0000-000000000002', 'custom', 'Déjà lue', '', now() - interval '2 hours', now() - interval '90 minutes'),
  (900000021, 'c7000000-0000-0000-0000-000000000003', 'custom', 'Pour Bruno', '', now(), null),
  (900000031, 'c7000000-0000-0000-0000-000000000004', 'custom', 'Pour Archie', '', now(), null);

select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (
    select array_agg(history.id order by history.position)
    from public.get_my_notification_history()
      with ordinality as history(
        id, kind, match_id, title, body, url, created_at, read_at, position
      )
  ),
  array[900000013, 900000012, 900000015, 900000011]::bigint[],
  'le joueur lit ses notifications des 90 derniers jours, la plus récente en premier'
);

select is(
  public.get_my_unread_notification_count(),
  3,
  'le compteur ne compte que ses notifications non lues des 90 derniers jours'
);

select is(
  (select count(*) from public.get_my_notification_history(0)),
  1::bigint,
  'une limite trop basse est ramenée à une ligne'
);

select is(
  (select count(*) from public.get_my_notification_history(null)),
  4::bigint,
  'une limite vide reprend la valeur par défaut'
);

select is(
  public.delete_my_notification(900000021),
  false,
  'le joueur ne supprime pas la notification d’un autre compte'
);

select is(
  public.delete_my_notification(900000011),
  true,
  'le joueur supprime une de ses notifications'
);

select is(
  public.delete_my_notification(900000011),
  false,
  'une notification déjà supprimée ne l’est pas deux fois'
);

select is(
  public.get_my_unread_notification_count(),
  2,
  'la notification supprimée ne compte plus'
);

select throws_ok(
  $$
    select public.internal_record_notification_history(
      'custom', null,
      array['c7000000-0000-0000-0000-000000000002']::uuid[],
      'Usurpation', '', null, null, null
    )
  $$,
  '42501',
  null,
  'un compte connecté ne peut pas ranger une notification lui-même'
);

select is(
  public.mark_my_notifications_read(),
  2,
  'ouvrir l’écran marque comme lues toutes ses notifications non lues'
);

select is(
  public.get_my_unread_notification_count(),
  0,
  'plus rien n’est non lu après l’ouverture de l’écran'
);

select is(
  public.mark_my_notifications_read(),
  0,
  'une seconde ouverture ne marque plus rien'
);

reset role;

select ok(
  exists (
    select 1
    from private.notification_history
    where id = 900000021
      and read_at is null
  ),
  'les notifications des autres comptes restent intactes'
);

select ok(
  (
    select read_at = now() - interval '90 minutes'
    from private.notification_history
    where id = 900000015
  ),
  'une notification déjà lue garde son heure de lecture'
);

-- Sans identité.
select set_config('request.jwt.claims', '', true);
set local role authenticated;

select throws_ok(
  'select * from public.get_my_notification_history()',
  '42501', 'Authentication required',
  'lire l’historique exige une identité'
);
select throws_ok(
  'select public.get_my_unread_notification_count()',
  '42501', 'Authentication required',
  'lire le compteur exige une identité'
);
select throws_ok(
  'select public.mark_my_notifications_read()',
  '42501', 'Authentication required',
  'marquer comme lu exige une identité'
);
select throws_ok(
  'select public.delete_my_notification(900000021)',
  '42501', 'Authentication required',
  'supprimer exige une identité'
);

reset role;

-- Visiteur anonyme.
set local role anon;

select throws_ok(
  'select public.get_my_unread_notification_count()',
  '42501',
  null,
  'un visiteur anonyme n’a pas accès au compteur'
);
select throws_ok(
  'select public.delete_my_notification(900000021)',
  '42501',
  null,
  'un visiteur anonyme ne supprime rien'
);

reset role;

-- Profil archivé : un historique vide et un compteur à zéro, aucune écriture.
select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000004","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.get_my_notification_history()),
  0::bigint,
  'un profil archivé lit un historique vide'
);
select is(
  public.get_my_unread_notification_count(),
  0,
  'un profil archivé a un compteur à zéro'
);
select throws_ok(
  'select public.mark_my_notifications_read()',
  '42501', 'Active profile not found',
  'un profil archivé ne marque rien comme lu'
);
select throws_ok(
  'select public.delete_my_notification(900000031)',
  '42501', 'Active profile not found',
  'un profil archivé ne supprime rien'
);

reset role;

select ok(
  exists (
    select 1
    from private.notification_history
    where id = 900000031
      and read_at is null
  ),
  'la ligne du profil archivé reste en place'
);

-- La liste est bornée à 200 lignes, 100 par défaut.
insert into private.notification_history (profile_id, kind, title, created_at)
select
  'c7000000-0000-0000-0000-000000000003',
  'custom',
  'Message ' || position,
  now() - make_interval(mins => position)
from generate_series(1, 205) as position;

select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.get_my_notification_history(1000)),
  200::bigint,
  'la liste ne dépasse jamais 200 lignes'
);
select is(
  (select count(*) from public.get_my_notification_history()),
  100::bigint,
  'la liste rend 100 lignes par défaut'
);

reset role;

-- ---------------------------------------------------------------------------
-- 4. Lu en faisant ce que la notification demandait
-- ---------------------------------------------------------------------------

delete from private.notification_history
where profile_id between
  'c7000000-0000-0000-0000-000000000001'
  and 'c7000000-0000-0000-0000-000000000004';

insert into private.notification_history (id, profile_id, kind, match_id, title)
values
  (900000101, 'c7000000-0000-0000-0000-000000000002', 'availability_open', current_setting('test.history_match')::uuid, 'Disponibilité'),
  (900000102, 'c7000000-0000-0000-0000-000000000002', 'availability_manual', current_setting('test.history_match')::uuid, 'Tu n’as pas répondu'),
  (900000103, 'c7000000-0000-0000-0000-000000000002', 'match_rescheduled_date', current_setting('test.history_match')::uuid, 'Match reporté'),
  (900000104, 'c7000000-0000-0000-0000-000000000002', 'prediction_j5', current_setting('test.history_match')::uuid, 'Pronostic'),
  (900000105, 'c7000000-0000-0000-0000-000000000002', 'motm_open', current_setting('test.history_match')::uuid, 'Fin du match'),
  (900000106, 'c7000000-0000-0000-0000-000000000002', 'match_rescheduled_time', current_setting('test.history_match')::uuid, 'Horaire modifié'),
  (900000107, 'c7000000-0000-0000-0000-000000000002', 'availability_open', 'c7400000-0000-0000-0000-000000000002', 'Autre match'),
  (900000108, 'c7000000-0000-0000-0000-000000000003', 'availability_open', current_setting('test.history_match')::uuid, 'Disponibilité'),
  (900000109, 'c7000000-0000-0000-0000-000000000003', 'availability_manual', current_setting('test.history_match')::uuid, 'Tu n’as pas répondu'),
  (900000110, 'c7000000-0000-0000-0000-000000000003', 'prediction_j5', current_setting('test.history_match')::uuid, 'Pronostic'),
  (900000111, 'c7000000-0000-0000-0000-000000000003', 'motm_open', current_setting('test.history_match')::uuid, 'Fin du match');

-- Le staff change la disponibilité de Bruno : ce n'est pas sa réponse.
select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.admin_override_match_availability(%L::uuid, %L::uuid, %L, null, %L)',
    current_setting('test.history_match'),
    'c7300000-0000-0000-0000-000000000002',
    'absent',
    'Prévenu par téléphone'
  ),
  'le staff peut changer la disponibilité d’un joueur'
);

reset role;

select is(
  (
    select count(*)
    from private.notification_history
    where id in (900000108, 900000109)
      and read_at is null
  ),
  2::bigint,
  'une disponibilité changée par le staff ne marque pas les notifications du joueur comme lues'
);

-- Retour à « pas de réponse » (période d'indisponibilité annulée) : rien à
-- marquer, le joueur n'a pas répondu.
insert into public.match_sport_participant_events (
  participant_id, match_id, event_type, old_value, new_value,
  actor_profile_id, actor_kind
)
select
  participant.id,
  participant.match_id,
  'availability_changed',
  jsonb_build_object('status', 'absent'),
  jsonb_build_object(
    'status', 'no_response',
    'source', 'player_unavailability_cancelled'
  ),
  'c7000000-0000-0000-0000-000000000002',
  'player'
from public.match_sport_participants participant
where participant.match_id = current_setting('test.history_match')::uuid
  and participant.season_player_id = 'c7300000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from private.notification_history
    where id in (900000101, 900000102, 900000103)
      and read_at is null
  ),
  3::bigint,
  'un retour à « pas de réponse » ne marque rien comme lu'
);

-- Alice répond elle-même.
select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.set_my_match_availability(%L::uuid, %L, null)',
    current_setting('test.history_match'),
    'available'
  ),
  'Alice répond à la disponibilité'
);

reset role;

select is(
  (
    select count(*)
    from private.notification_history
    where id in (900000101, 900000102, 900000103)
      and read_at is not null
  ),
  3::bigint,
  'répondre marque comme lues l’ouverture, la relance et le report de ce match'
);

select is(
  (
    select count(*)
    from private.notification_history
    where id in (900000104, 900000105, 900000106)
      and read_at is null
  ),
  3::bigint,
  'les autres types de notifications du même match restent non lus'
);

select ok(
  (select read_at is null from private.notification_history where id = 900000107),
  'la notification d’un autre match reste non lue'
);

select is(
  (
    select count(*)
    from private.notification_history
    where id in (900000108, 900000109)
      and read_at is null
  ),
  2::bigint,
  'la réponse d’Alice ne touche pas les notifications de Bruno'
);

-- Une absence posée par une période d'indisponibilité que le joueur déclare
-- compte comme sa réponse.
insert into public.match_sport_participant_events (
  participant_id, match_id, event_type, old_value, new_value,
  actor_profile_id, actor_kind
)
select
  participant.id,
  participant.match_id,
  'availability_changed',
  jsonb_build_object('status', 'absent'),
  jsonb_build_object('status', 'absent', 'source', 'player_unavailability'),
  'c7000000-0000-0000-0000-000000000003',
  'player'
from public.match_sport_participants participant
where participant.match_id = current_setting('test.history_match')::uuid
  and participant.season_player_id = 'c7300000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from private.notification_history
    where id in (900000108, 900000109)
      and read_at is not null
  ),
  2::bigint,
  'une absence posée par la période d’indisponibilité du joueur compte comme sa réponse'
);

-- Pronostic : un pronostic non rempli ne compte pas, un pronostic rempli si.
-- Sans identité : le garde des pronostics réattribuerait sinon la ligne au
-- compte encore déclaré dans la session.
select set_config('request.jwt.claims', '', true);

update public.match_predictions
set is_filled = false,
    predicted_score_as_grinta = 1,
    updated_at = now()
where match_id = current_setting('test.history_match')::uuid
  and profile_id = 'c7000000-0000-0000-0000-000000000003';

select ok(
  (select read_at is null from private.notification_history where id = 900000110),
  'un pronostic non rempli ne marque pas le rappel comme lu'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c7000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.save_match_prediction(
    current_setting('test.history_match')::uuid, 2, 1
  ),
  'Alice remplit son pronostic'
);

reset role;

select ok(
  (select read_at is not null from private.notification_history where id = 900000104),
  'remplir son pronostic marque le rappel de pronostic comme lu'
);

select ok(
  (select read_at is null from private.notification_history where id = 900000110),
  'le pronostic d’Alice ne touche pas le rappel de Bruno'
);

-- Homme du match : le vote est écrit directement, seul le déclencheur est
-- vérifié ici (le parcours de vote a ses propres tests).
insert into public.match_sport_motm_elections (
  match_id, finalization_version, state
)
values (current_setting('test.history_match')::uuid, 1, 'draft');

insert into public.match_sport_motm_votes (
  match_id, voter_profile_id, candidate_participant_id, finalization_version
)
select
  participant.match_id,
  'c7000000-0000-0000-0000-000000000002',
  participant.id,
  1
from public.match_sport_participants participant
where participant.match_id = current_setting('test.history_match')::uuid
  and participant.season_player_id = 'c7300000-0000-0000-0000-000000000002';

select ok(
  (select read_at is not null from private.notification_history where id = 900000105),
  'voter marque l’ouverture du vote comme lue'
);

select ok(
  (select read_at is null from private.notification_history where id = 900000111),
  'le vote d’Alice ne touche pas la notification de Bruno'
);

select ok(
  (select read_at is null from private.notification_history where id = 900000106),
  'une notification sans action attendue reste non lue'
);

-- Une notification qui part après l'action (la fonction d'envoi passe après
-- coup) est rangée directement comme lue.
select public.internal_record_notification_history(
  'availability_open',
  current_setting('test.history_match')::uuid,
  array[
    'c7000000-0000-0000-0000-000000000002',
    'c7000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'Disponibilité', 'Es-tu dispo ?', 'matches', 'late-open', 'late:open'
);

select ok(
  (
    select read_at is not null
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
      and dedupe_key = 'late:open'
  ),
  'Alice a déjà répondu : la disponibilité arrive déjà lue'
);

select ok(
  (
    select read_at is null
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000003'
      and dedupe_key = 'late:open'
  ),
  'la réponse posée par le staff pour Bruno ne compte pas : non lue'
);

select public.internal_record_notification_history(
  'prediction_j5',
  current_setting('test.history_match')::uuid,
  array['c7000000-0000-0000-0000-000000000002']::uuid[],
  'Pronostic', 'Pense à ton prono', 'matches', 'late-prono', 'late:prono'
);

select public.internal_record_notification_history(
  'motm_open',
  current_setting('test.history_match')::uuid,
  array[
    'c7000000-0000-0000-0000-000000000002',
    'c7000000-0000-0000-0000-000000000003'
  ]::uuid[],
  'Fin du match', 'Vote', 'matches', 'late-motm', 'late:motm'
);

select is(
  (
    select count(*)
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000002'
      and dedupe_key in ('late:prono', 'late:motm')
      and read_at is not null
  ),
  2::bigint,
  'pronostic rempli et vote déjà fait : rappel et ouverture du vote arrivent lus'
);

select ok(
  (
    select read_at is null
    from private.notification_history
    where profile_id = 'c7000000-0000-0000-0000-000000000003'
      and dedupe_key = 'late:motm'
  ),
  'Bruno n’a pas voté : l’ouverture du vote arrive non lue'
);

-- ---------------------------------------------------------------------------
-- 5. Suppression du compte : l'historique part avec lui.
-- ---------------------------------------------------------------------------

select is(
  (
    select confdeltype
    from pg_constraint
    where conrelid = 'private.notification_history'::regclass
      and contype = 'f'
      and confrelid = 'public.profiles'::regclass
  ),
  'c'::"char",
  'supprimer un profil supprime son historique'
);

select * from finish();

rollback;
