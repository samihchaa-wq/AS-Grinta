-- Chaque notification ouvre l'écran qu'elle annonce.
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

update private.app_feature_flags
set enabled = false
where key = 'notifications_paused';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'f0e10000-0000-0000-0000-000000000001',
  'notification-screen@example.invalid',
  '{"first_name":"Ecran","last_name":"Notification"}'::jsonb
);

update public.profiles
set role = 'pronostiqueur', status = 'active', notify_badges = true,
    updated_at = now()
where id = 'f0e10000-0000-0000-0000-000000000001';

insert into public.seasons (id, name, status)
values ('f0e20000-0000-0000-0000-000000000001', '2215-2216', 'open');
insert into public.opponents (id, name)
values ('f0e30000-0000-0000-0000-000000000001', 'Ecran FC');

set local session_replication_role = replica;
insert into public.matches (
  id, season_id, opponent_id, match_date, match_time, kickoff_at, location,
  planned_duration_minutes, status, created_by, match_type, competition
) values (
  'f0e40000-0000-0000-0000-000000000001',
  'f0e20000-0000-0000-0000-000000000001',
  'f0e30000-0000-0000-0000-000000000001',
  current_date + 3, time '21:00', now() + interval '3 days', 'domicile', 90,
  'a_venir', 'f0e10000-0000-0000-0000-000000000001', 'amical', 'championnat'
);
set local session_replication_role = origin;

-- Adresse portée par le dernier envoi mis en file.
create or replace function pg_temp.last_push_url()
returns text
language sql
stable
as $function$
  select convert_from(queue.body, 'UTF8')::jsonb ->> 'url'
  from net.http_request_queue queue
  order by queue.id desc
  limit 1;
$function$;

-- ---------------------------------------------------------------------------
-- Convocation et composition : la fiche du match, sur le bon onglet
-- ---------------------------------------------------------------------------

select ok(
  private.dispatch_convocation_push(
    'f0e40000-0000-0000-0000-000000000001',
    'f0e10000-0000-0000-0000-000000000001'
  ),
  'la convocation est mise en file'
);
select is(
  pg_temp.last_push_url(),
  'matches/f0e40000-0000-0000-0000-000000000001/lineup?section=effectif',
  'la convocation ouvre l''Effectif du match'
);

select ok(
  private.dispatch_composition_published_push(
    'f0e40000-0000-0000-0000-000000000001',
    array['f0e10000-0000-0000-0000-000000000001'::uuid]
  ),
  'la composition en ligne est mise en file'
);
select is(
  pg_temp.last_push_url(),
  'matches/f0e40000-0000-0000-0000-000000000001/lineup?section=composition',
  'la composition en ligne ouvre la Composition du match'
);

-- ---------------------------------------------------------------------------
-- Badges : l'armoire
-- ---------------------------------------------------------------------------

insert into public.badges (
  code, name, description, emoji, family, auto, sort_order, kind, category,
  color
) values (
  'custom_test_notification_screen', 'Écran', 'Badge de test.', '🏅',
  'joueur', false, 999931, 'custom', 'faits_de_jeu', '#F97316'
);

insert into public.profile_badges (profile_id, badge_id, source)
select 'f0e10000-0000-0000-0000-000000000001', badge.id, 'manual'
from public.badges badge
where badge.code = 'custom_test_notification_screen';

select is(
  private.process_badge_unlock_notifications(now() + interval '1 minute'),
  1,
  'le badge débloqué est annoncé'
);
select is(
  pg_temp.last_push_url(),
  'armoire',
  'un badge débloqué ouvre l''armoire'
);

-- ---------------------------------------------------------------------------
-- Résultat HDM et changement de disponibilité
-- ---------------------------------------------------------------------------
--
-- Leurs destinataires dépendent d'un scrutin clos ou d'un changement de
-- réponse : la définition suffit à vérifier l'écran choisi.

select ok(
  pg_get_functiondef('private.dispatch_motm_result_notification(text,uuid)'::regprocedure)
    like '%''url'', ''matches/'' || p_match_id%',
  'le résultat HDM ouvre la fiche du match'
);
select ok(
  pg_get_functiondef('private.notify_admin_player_availability_change()'::regprocedure)
    like '%''url'', ''matches/'' || new.match_id || ''/lineup?section=effectif''%',
  'un changement de disponibilité ouvre l''Effectif du match'
);

-- ---------------------------------------------------------------------------
-- Notifications de test
-- ---------------------------------------------------------------------------

insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth)
values (
  'f0e10000-0000-0000-0000-000000000001',
  'https://push.example.invalid/notification-screen',
  'p256dh-test',
  'auth-test'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f0e10000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select public.send_test_push_kind('badge_unlocked');
reset role;

select is(
  pg_temp.last_push_url(),
  'armoire',
  'le test « Badge débloqué » ouvre aussi l''armoire'
);

set local role authenticated;
select public.send_test_push_kind('motm_open');
reset role;

select is(
  pg_temp.last_push_url(),
  '.',
  'un test lié à un match, sans vrai match, ouvre l''accueil'
);

select * from finish();
rollback;
