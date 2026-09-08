-- Permet à chaque administrateur d'activer ou désactiver l'alerte reçue lorsqu'un
-- joueur corrige sa disponibilité entre Présent et Absent.
--
-- Le réglage est volontairement séparé des préférences générales : les anciens
-- clients continuent à utiliser update_my_notification_preferences sans connaître
-- ce nouveau paramètre, tandis que seuls les admins peuvent modifier celui-ci.

alter table public.profiles
  add column if not exists notify_admin_availability_change boolean not null default true;

comment on column public.profiles.notify_admin_availability_change is
  'Pour un admin actif, recevoir les alertes lorsqu''un joueur passe de Présent à Absent ou inversement.';

create or replace function public.update_my_admin_availability_notification(
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
  if not public.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  update public.profiles profile
  set notify_admin_availability_change = p_enabled,
      updated_at = now()
  where profile.id = v_actor
    and profile.role = 'admin'
    and profile.status = 'active';

  if not found then
    raise exception 'Active administrator profile not found' using errcode = '42501';
  end if;

  return true;
end;
$function$;

revoke all on function public.update_my_admin_availability_notification(boolean)
  from public, anon;
grant execute on function public.update_my_admin_availability_notification(boolean)
  to authenticated, service_role;

-- La préférence est filtrée au moment de construire la liste des destinataires.
-- Une correction reste enregistrable même si le canal push tombe en panne.
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
      'message', v_message
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

revoke all on function private.notify_admin_player_availability_change()
  from public, anon, authenticated;

-- Ajoute un aperçu dédié au menu Test du centre des notifications. Les types
-- réservés aux admins sont aussi protégés côté serveur afin qu'un joueur ne
-- puisse pas les appeler directement via RPC.
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
begin
  if v_actor is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if v_kind in ('admin_pending_signup', 'admin_availability_change')
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
