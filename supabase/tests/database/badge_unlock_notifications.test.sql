begin;

set local search_path = public, extensions, pg_catalog;
select plan(12);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'notify_badges'
      and is_nullable = 'NO'
      and column_default = 'true'
  ),
  'la préférence badges existe, est non nullable et active par défaut'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_my_badge_notifications(boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.update_my_badge_notifications(boolean)',
    'EXECUTE'
  ),
  'la RPC de préférence badges est réservée aux clients authentifiés'
);

select ok(
  position(
    'notify_badges'
    in pg_get_functiondef('public.guard_sensitive_profile_fields()'::regprocedure)
  ) > 0,
  'un joueur peut modifier lui-même sa préférence badges'
);

select is(
  private.badge_unlock_push_message(array['Buteur']) ->> 'message',
  'Bravo, tu as débloqué le badge « Buteur » !',
  'un seul badge donne une notification au singulier'
);

select is(
  private.badge_unlock_push_message(array['Buteur', 'Passeur']) ->> 'title',
  'Nouveaux badges débloqués 🏅',
  'plusieurs badges donnent un titre au pluriel'
);

select is(
  private.badge_unlock_push_message(array['A', 'B', 'C', 'D', 'E']) ->> 'message',
  'Bravo, tu as débloqué 5 badges : « A », « B », « C » et 2 autres !',
  'au-delà de trois badges, la liste est résumée'
);

-- Fixture : un joueur actif qui a désactivé la notification, deux badges.
insert into auth.users(id, email, raw_user_meta_data)
values (
  'b4d60000-0000-0000-0000-000000000001',
  'badge-push@example.invalid',
  '{"first_name":"Badge"}'::jsonb
);

update public.profiles
set role = 'pronostiqueur',
    status = 'active',
    notify_badges = false,
    updated_at = now()
where id = 'b4d60000-0000-0000-0000-000000000001';

insert into public.badges (code, name, description, emoji, family, auto, kind, category)
values
  ('test_badge_push_a', 'Test A', '', '🏅', 'joueur', false, 'custom', 'faits_de_jeu'),
  ('test_badge_push_b', 'Test B', '', '🏅', 'joueur', false, 'custom', 'faits_de_jeu');

insert into public.profile_badges (profile_id, badge_id, source)
select 'b4d60000-0000-0000-0000-000000000001', badge.id, 'manual'
from public.badges badge
where badge.code in ('test_badge_push_a', 'test_badge_push_b');

select is(
  (
    select count(*)::integer
    from private.badge_unlock_push_queue queue
    where queue.profile_id = 'b4d60000-0000-0000-0000-000000000001'
  ),
  2,
  'chaque badge débloqué est mis en file d''attente'
);

select vault.create_secret('test-token', 'push_internal_token')
where not exists (
  select 1 from vault.secrets secret where secret.name = 'push_internal_token'
);

select is(
  private.process_badge_unlock_notifications(now()),
  0,
  'rien n''est envoyé tant que des badges peuvent encore arriver'
);

select is(
  (
    select count(*)::integer
    from private.badge_unlock_push_queue queue
    where queue.profile_id = 'b4d60000-0000-0000-0000-000000000001'
  ),
  2,
  'les badges récents restent en attente pour être regroupés'
);

select is(
  private.process_badge_unlock_notifications(now() + interval '1 minute'),
  0,
  'un joueur ayant désactivé la notification ne reçoit rien'
);

select is(
  (
    select count(*)::integer
    from private.badge_unlock_push_queue queue
    where queue.profile_id = 'b4d60000-0000-0000-0000-000000000001'
  ),
  0,
  'la file est vidée une fois traitée'
);

select ok(
  exists (
    select 1 from cron.job job
    where job.jobname = 'badge-unlock-notifications'
  ),
  'la tâche planifiée d''envoi est programmée'
);

select * from finish();
rollback;
