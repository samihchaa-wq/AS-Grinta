begin;

-- Chaque notification ouvre l'écran qu'elle annonce.
--
-- Ouvrir une notification amène sur l'adresse qu'elle porte. Les
-- notifications de match préparées par internal_push_dispatch,
-- internal_sport_push_dispatch et le Live en portaient déjà une. Celles qui
-- passent par l'envoi « contenu préparé » (kind custom) n'en avaient pas :
-- elles ouvraient toutes l'accueil. Elles indiquent désormais leur écran :
--
-- * convocation              → fiche du match, Effectif ;
-- * composition en ligne     → fiche du match, Composition ;
-- * résultat Homme du match  → fiche du match terminé (score, HDM) ;
-- * changement de dispo      → fiche du match, Effectif (administrateurs) ;
-- * badge(s) débloqué(s)     → armoire à badges ;
-- * notifications de test    → même écran que la vraie quand il n'a pas
--   besoin d'un match (badges, compte en attente), sinon l'accueil.
--
-- Le message libre d'un administrateur reste sans écran : il ouvre l'accueil.
--
-- La fonction send-push ignore l'adresse tant qu'elle n'est pas redéployée :
-- les deux livraisons peuvent se faire dans n'importe quel ordre, une
-- notification ouvre au pire l'accueil comme avant.
--
-- Chaque corps est repris à l'identique de sa dernière définition
-- (20260831103500, 20261002120000, baseline 20260809232339, 20260908193000,
-- 20260923220000), à la seule clé 'url' près. create or replace conserve
-- propriétaires, droits et commentaires.

-- ---------------------------------------------------------------------------
-- Convocation
-- ---------------------------------------------------------------------------

create or replace function private.dispatch_convocation_push(
  p_match_id uuid,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text := 'Tu es convoqué';
  v_body text;
  v_match record;
begin
  if p_profile_id is null
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_body := case
    when v_match.opponent_name is null then format(
      'Tu es convoqué pour le match entre nous du %s.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'Tu es convoqué pour le match du %s contre %s.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
      v_match.opponent_name
    )
  end;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';
  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(p_profile_id),
      'title', v_title,
      'message', v_body,
      'url', 'matches/' || p_match_id || '/lineup?section=effectif'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Composition en ligne
-- ---------------------------------------------------------------------------

create or replace function private.dispatch_composition_published_push(
  p_match_id uuid,
  p_profile_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text;
  v_body text;
  v_match record;
begin
  if p_profile_ids is null
     or cardinality(p_profile_ids) = 0
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    m.match_type,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_title := case
    when v_match.match_type = 'entre_nous'
      then 'Les compositions sont en ligne'
    else 'La composition est en ligne'
  end;

  v_body := case
    when v_match.match_type = 'entre_nous' then format(
      'Les compositions du match entre nous du %s sont prêtes.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'La composition du match du %s contre %s est en ligne.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
      v_match.opponent_name
    )
  end;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';
  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', to_jsonb(p_profile_ids),
      'title', v_title,
      'message', v_body,
      'url', 'matches/' || p_match_id || '/lineup?section=composition'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Résultat Homme du match
-- ---------------------------------------------------------------------------

create or replace function private.dispatch_motm_result_notification(
  p_kind text,
  p_match_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_payload jsonb;
  v_token text;
  v_profile_ids jsonb;
  v_title text;
  v_message text;
  v_request_id bigint;
begin
  if p_kind not in ('motm_result_general', 'motm_result_winner') then
    raise exception 'Unknown MOTM result notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management')
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  v_payload := private.match_motm_result_notification_payloads(p_match_id);
  if p_kind = 'motm_result_general' then
    v_profile_ids := coalesce(v_payload -> 'general_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'general_title';
    v_message := v_payload ->> 'general_message';
  else
    v_profile_ids := coalesce(v_payload -> 'winner_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'winner_title';
    v_message := v_payload ->> 'winner_message';
  end if;

  if jsonb_array_length(v_profile_ids) = 0 then
    return true;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', v_profile_ids,
      'title', v_title,
      'message', v_message,
      'url', 'matches/' || p_match_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception
  when others then
    return false;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Changement de disponibilité (administrateurs)
-- ---------------------------------------------------------------------------

create or replace function private.notify_admin_player_availability_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_player_profile_id uuid;
  v_display_name text;
  v_admin_profile_ids uuid[];
  v_message text;
  v_token text;
  v_request_id bigint;
begin
  if old.availability_status is not distinct from new.availability_status
     or old.availability_status::text not in ('available', 'absent')
     or new.availability_status::text not in ('available', 'absent') then
    return new;
  end if;

  if new.season_player_id is null or new.availability_updated_by is null then
    return new;
  end if;

  select
    player.profile_id,
    coalesce(
      nullif(btrim(profile.surnom), ''),
      nullif(btrim(profile.first_name), ''),
      nullif(btrim(player.first_name), ''),
      'Un joueur'
    )
  into v_player_profile_id, v_display_name
  from public.season_players player
  left join public.profiles profile on profile.id = player.profile_id
  where player.id = new.season_player_id;

  if v_player_profile_id is null
     or v_player_profile_id is distinct from new.availability_updated_by
     or not exists (
       select 1
       from public.profiles actor
       where actor.id = v_player_profile_id
         and actor.status = 'active'
     ) then
    return new;
  end if;

  select array_agg(profile.id order by profile.id)
  into v_admin_profile_ids
  from public.profiles profile
  where profile.role = 'admin'
    and profile.status = 'active'
    and profile.notify_admin_availability_change;

  if v_admin_profile_ids is null or cardinality(v_admin_profile_ids) = 0 then
    return new;
  end if;

  v_message := private.admin_availability_change_message(
    v_display_name,
    old.availability_status::text,
    new.availability_status::text,
    coalesce(new.availability_updated_at, now())
  );
  if v_message is null then
    return new;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return new;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', to_jsonb(v_admin_profile_ids),
      'title', 'Changement de disponibilité',
      'message', v_message,
      'url', 'matches/' || new.match_id || '/lineup?section=effectif'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return new;
exception when others then
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Badges débloqués
-- ---------------------------------------------------------------------------

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
        'message', v_payload ->> 'message',
        'url', 'armoire'
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

-- ---------------------------------------------------------------------------
-- Notifications de test
-- ---------------------------------------------------------------------------

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
  -- Les exemples liés à un match n'ont pas de vrai match : ils ouvrent
  -- l'accueil. Les autres ouvrent le même écran que la vraie notification.
  v_url text := '.';
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
      v_body := 'Es-tu disponible pour le match du 12/09 contre FC Exemple à 20h30 ?';
    when 'availability_manual' then
      v_title := 'Tu n''as pas répondu 👀';
      v_body := 'Pense à indiquer si tu es disponible pour le match contre FC Exemple !';
    when 'convocation_promoted' then
      v_title := 'Tu es convoqué';
      v_body := 'Tu es convoqué pour le match du 12/09 contre FC Exemple.';
    when 'composition_published' then
      v_title := 'La composition est en ligne';
      v_body := 'La composition du match du 12/09 contre FC Exemple est en ligne.';
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
      v_body := 'Pense à voter pour l’Homme du match.';
    when 'motm_result_general' then
      v_title := 'Homme du match';
      v_body := 'Joueur Test a été élu Homme du match !';
    when 'motm_result_winner' then
      v_title := 'Homme du match';
      v_body := 'Bravo, tu as été élu Homme du match !';
    when 'admin_pending_signup' then
      v_title := 'Nouveau compte en attente';
      v_body := 'Joueur Test attend ta validation.';
      v_url := 'admin/administration';
    when 'admin_availability_change' then
      v_title := 'Changement de disponibilité';
      v_body := 'À 20h30, Joueur Test est passé de présent à absent.';
    when 'badge_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(array['Buteur']);
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
      v_url := 'armoire';
    when 'badges_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(
        array['Buteur', 'Passeur']
      );
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
      v_url := 'armoire';
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
      'message', v_body,
      'url', v_url
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

commit;
