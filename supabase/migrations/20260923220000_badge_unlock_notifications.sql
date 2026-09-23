-- Prévient un joueur lorsqu'il débloque un badge.
--
-- Un badge peut être gagné automatiquement (statistiques, HDM, pronostics…) ou
-- décerné à la main par le staff. Dans les deux cas une ligne est insérée dans
-- public.profile_badges : c'est ce point unique qui alimente la notification.
--
-- Plusieurs badges arrivent souvent ensemble (un match fait franchir plusieurs
-- paliers, un staff en décerne plusieurs d'affilée). Le trigger ne pousse donc
-- rien lui-même : il met le badge en file d'attente. Une tâche planifiée
-- regroupe ensuite, par joueur, les badges reçus et n'envoie qu'une seule
-- notification, au pluriel s'il y en a plusieurs. Elle attend que le joueur
-- n'ait plus rien reçu depuis 45 secondes avant d'envoyer.
--
-- Le réglage est séparé des préférences générales, comme celui des admins :
-- update_my_notification_preferences garde sa signature, les clients déjà
-- installés continuent de fonctionner.

alter table public.profiles
  add column if not exists notify_badges boolean not null default true;

comment on column public.profiles.notify_badges is
  'Prévenir ce joueur lorsqu''il débloque un ou plusieurs badges.';

-- Le garde des profils raisonne sur une liste blanche : sans la nouvelle
-- colonne, un joueur ne pourrait pas modifier ce réglage.
create or replace function public.guard_sensitive_profile_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid := (select auth.uid());
  old_protected jsonb;
  new_protected jsonb;
  editable constant text[] := array[
    'first_name','last_name','surnom','photo_url','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation','notify_composition','notify_badges',
    'password_set','must_change_password'
  ];
begin
  if actor_id is null then
    return new;
  end if;
  if public.is_match_staff() then
    return new;
  end if;
  if actor_id is distinct from old.id then
    raise exception 'Un utilisateur ne peut modifier que son propre profil.'
      using errcode = '42501';
  end if;

  old_protected := to_jsonb(old) - editable;
  new_protected := to_jsonb(new) - editable;

  if new_protected is distinct from old_protected then
    raise exception 'Les champs sensibles du profil ne peuvent pas être modifiés.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

create or replace function public.update_my_badge_notifications(
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'Notification preference is required' using errcode = '22004';
  end if;

  update public.profiles profile
  set notify_badges = p_enabled,
      updated_at = now()
  where profile.id = v_actor
    and profile.status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return true;
end;
$function$;

revoke all on function public.update_my_badge_notifications(boolean)
  from public, anon;
grant execute on function public.update_my_badge_notifications(boolean)
  to authenticated, service_role;

-- File d'attente : une ligne par badge reçu et pas encore annoncé.
create table if not exists private.badge_unlock_push_queue (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  queued_at timestamptz not null default now(),
  primary key (profile_id, badge_id)
);

comment on table private.badge_unlock_push_queue is
  'Badges débloqués en attente de notification, regroupés par joueur par private.process_badge_unlock_notifications.';

alter table private.badge_unlock_push_queue enable row level security;
revoke all on table private.badge_unlock_push_queue
  from public, anon, authenticated;

-- Seule une vraie attribution (INSERT) est annoncée. Transformer un badge
-- automatique en badge manuel passe par un UPDATE et ne renotifie pas.
create or replace function private.queue_badge_unlock_push()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into private.badge_unlock_push_queue (profile_id, badge_id, queued_at)
  values (new.profile_id, new.badge_id, now())
  on conflict (profile_id, badge_id) do update
    set queued_at = excluded.queued_at;
  return null;
exception when others then
  -- Une panne de notification ne doit jamais empêcher d'attribuer un badge.
  return null;
end;
$function$;

revoke all on function private.queue_badge_unlock_push()
  from public, anon, authenticated;

drop trigger if exists trg_queue_badge_unlock_push on public.profile_badges;
create trigger trg_queue_badge_unlock_push
  after insert on public.profile_badges
  for each row execute function private.queue_badge_unlock_push();

-- Texte de la notification, au singulier ou au pluriel.
create or replace function private.badge_unlock_push_message(p_names text[])
returns jsonb
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_count integer := coalesce(cardinality(p_names), 0);
  v_quoted text[];
  v_list text;
begin
  if v_count = 0 then
    return null;
  end if;

  if v_count = 1 then
    return jsonb_build_object(
      'title', 'Nouveau badge débloqué 🏅',
      'message', format('Bravo, tu as débloqué le badge « %s » !', p_names[1])
    );
  end if;

  select array_agg(format('« %s »', name) order by position)
  into v_quoted
  from unnest(p_names[1:3]) with ordinality as item(name, position);

  if v_count <= 3 then
    v_list := array_to_string(v_quoted[1:v_count - 1], ', ')
      || ' et ' || v_quoted[v_count];
  else
    v_list := array_to_string(v_quoted, ', ')
      || format(' et %s autre%s', v_count - 3, case when v_count - 3 > 1 then 's' else '' end);
  end if;

  return jsonb_build_object(
    'title', 'Nouveaux badges débloqués 🏅',
    'message', format('Bravo, tu as débloqué %s badges : %s !', v_count, v_list)
  );
end;
$function$;

revoke all on function private.badge_unlock_push_message(text[])
  from public, anon, authenticated;

-- Envoie une notification par joueur dont les badges ne bougent plus depuis
-- 45 secondes. Les badges retirés entre-temps ne sont pas annoncés.
create or replace function private.process_badge_unlock_notifications(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_sent integer := 0;
  v_row record;
  v_payload jsonb;
begin
  -- Deux exécutions simultanées ne doivent pas annoncer deux fois.
  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('process_badge_unlock_notifications', 0)
  ) then
    return 0;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    -- Sans canal push, on évite simplement que la file grossisse sans fin.
    delete from private.badge_unlock_push_queue queue
    where queue.queued_at < p_now - interval '1 day';
    return 0;
  end if;

  for v_row in
    with ready as (
      select queue.profile_id
      from private.badge_unlock_push_queue queue
      group by queue.profile_id
      having max(queue.queued_at) <= p_now - interval '45 seconds'
    ),
    taken as (
      delete from private.badge_unlock_push_queue queue
      using ready
      where queue.profile_id = ready.profile_id
      returning queue.profile_id, queue.badge_id, queue.queued_at
    )
    select
      taken.profile_id,
      array_agg(badge.name order by taken.queued_at, badge.name) as names
    from taken
    join public.badges badge on badge.id = taken.badge_id
    join public.profile_badges owned
      on owned.profile_id = taken.profile_id
     and owned.badge_id = taken.badge_id
    join public.profiles profile on profile.id = taken.profile_id
    where profile.status = 'active'
      and profile.notify_badges
    group by taken.profile_id
  loop
    v_payload := private.badge_unlock_push_message(v_row.names);
    if v_payload is null then
      continue;
    end if;

    perform net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'custom',
        'profile_ids', jsonb_build_array(v_row.profile_id),
        'title', v_payload ->> 'title',
        'message', v_payload ->> 'message'
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$function$;

revoke all on function private.process_badge_unlock_notifications(timestamptz)
  from public, anon, authenticated;

select cron.unschedule(job.jobid)
from cron.job job
where job.jobname = 'badge-unlock-notifications';

select cron.schedule(
  'badge-unlock-notifications',
  '* * * * *',
  $job$select private.process_badge_unlock_notifications(now());$job$
);

-- Aperçu depuis le menu Test de l'écran Notifications.
create or replace function public.send_test_push_kind(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
  v_subscriptions integer;
  v_recent_attempts integer;
  v_title text;
  v_body text;
  v_kind text := btrim(coalesce(p_kind, ''));
  v_badge_payload jsonb;
begin
  if v_actor is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if v_kind = 'admin_availability_change'
     and not public.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  case v_kind
    when 'test' then
      v_title := 'Test AS Grinta';
      v_body := 'Si tu vois ceci, les notifications fonctionnent 🎉';
    when 'availability_open' then
      v_title := 'Disponibilité';
      v_body := 'Dispo pour le match du 12/09 contre FC Exemple à 20h30 ?';
    when 'availability_manual' then
      v_title := 'Tu n''as pas répondu 👀';
      v_body := 'Pense à indiquer si tu es dispo pour le match contre FC Exemple !';
    when 'convocation_promoted' then
      v_title := 'Tu es convoqué';
      v_body := 'Tu es convoqué pour le match du 12/09 contre FC Exemple.';
    when 'composition_published' then
      v_title := 'La composition est en ligne';
      v_body := 'La compo du match du 12/09 contre FC Exemple est en ligne.';
    when 'prediction_j5' then
      v_title := 'Pronostic';
      v_body := 'Pense à pronostiquer pour le match du 12/09 contre FC Exemple.';
    when 'match_cancelled' then
      v_title := 'Match annulé';
      v_body := 'Le match du 12/09 contre FC Exemple à 20h30 est annulé.';
    when 'match_rescheduled_date' then
      v_title := 'Match reporté';
      v_body := 'Le match contre FC Exemple est reporté au 12/09 à 20h30. Es-tu disponible ?';
    when 'match_rescheduled_time' then
      v_title := 'Horaire du match modifié';
      v_body := 'Le match du 12/09 contre FC Exemple aura finalement lieu à 20h30.';
    when 'motm_open' then
      v_title := 'Homme du match';
      v_body := 'Pense à voter pour l’homme du match.';
    when 'motm_result_general' then
      v_title := 'Homme du match';
      v_body := 'Joueur Test a été élu Homme du match !';
    when 'motm_result_winner' then
      v_title := 'Homme du match';
      v_body := 'Bravo, tu as été élu Homme du match !';
    when 'admin_pending_signup' then
      v_title := 'Nouveau compte en attente';
      v_body := 'Joueur Test attend ta validation.';
    when 'admin_availability_change' then
      v_title := 'Changement de disponibilité';
      v_body := 'Joueur Test est passé de présent à absent à 20h30.';
    when 'badge_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(array['Buteur']);
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
    when 'badges_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(
        array['Buteur', 'Passeur']
      );
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
    else
      raise exception 'Unknown test notification kind' using errcode = '22023';
  end case;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('send_test_push:' || v_actor::text, 0)
  );

  delete from private.test_push_attempts attempt
  where attempt.profile_id = v_actor
    and attempt.attempted_at < now() - interval '1 day';

  select count(*)::integer
  into v_recent_attempts
  from private.test_push_attempts attempt
  where attempt.profile_id = v_actor
    and attempt.attempted_at >= now() - interval '10 minutes';

  if v_recent_attempts >= 3 then
    return jsonb_build_object('sent', false, 'reason', 'rate_limited');
  end if;

  select count(*)
  into v_subscriptions
  from public.push_subscriptions subscription
  where subscription.profile_id = v_actor;

  if v_subscriptions = 0 then
    return jsonb_build_object('sent', false, 'reason', 'no_subscription');
  end if;

  if coalesce(
       (private.get_notifications_paused()
          #>> '{notifications_paused,enabled}')::boolean,
       false
     ) then
    return jsonb_build_object('sent', false, 'reason', 'notifications_paused');
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return jsonb_build_object('sent', false, 'reason', 'not_configured');
  end if;

  insert into private.test_push_attempts (profile_id)
  values (v_actor);

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(v_actor),
      'title', v_title,
      'message', v_body
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return jsonb_build_object(
    'sent', true,
    'subscriptions', v_subscriptions,
    'kind', v_kind
  );
end;
$function$;

revoke all on function public.send_test_push_kind(text) from public, anon;
grant execute on function public.send_test_push_kind(text)
  to authenticated, service_role;
