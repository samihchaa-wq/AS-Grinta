-- Manual/admin push actions should only count profiles that can currently be
-- targeted by Web Push. This keeps admin feedback honest and avoids consuming
-- the manual availability cooldown for players with no registered device.

create or replace function private.send_sport_availability_reminder(
  p_match_id uuid,
  p_season_player_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_row record;
  v_event_id bigint;
  v_created integer := 0;
  v_skipped_recent integer := 0;
  v_skipped_no_subscription integer := 0;
  v_target_count integer := 0;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if private.is_feature_enabled('notifications_paused') then
    raise exception 'Les notifications sont désactivées.' using errcode = '55000';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason is too long' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.match_id = p_match_id
      and workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > now()
  ) then
    raise exception 'Availability reminders are not open for this match'
      using errcode = '22023';
  end if;

  for v_row in
    select
      participant.id as participant_id,
      participant.season_player_id,
      player.profile_id
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.availability_status = 'no_response'
      and player.profile_id is not null
      and profile.status = 'active'
      and (
        p_season_player_id is null
        or participant.season_player_id = p_season_player_id
      )
    order by participant.id
  loop
    v_target_count := v_target_count + 1;

    if not exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = v_row.profile_id
    ) then
      v_skipped_no_subscription := v_skipped_no_subscription + 1;
      continue;
    end if;

    if exists (
      select 1
      from public.sport_availability_notification_events event
      where event.participant_id = v_row.participant_id
        and event.kind = 'availability_manual'
        and event.requested_at > now() - interval '10 minutes'
    ) then
      v_skipped_recent := v_skipped_recent + 1;
      continue;
    end if;

    v_event_id := private.create_sport_availability_notification(
      p_match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_manual',
      'manual',
      now(),
      v_actor,
      v_reason
    );

    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  if p_season_player_id is not null and v_target_count = 0 then
    raise exception 'Player is not waiting for an availability response'
      using errcode = '22023';
  end if;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'send_availability_reminder',
    v_actor,
    v_reason,
    jsonb_build_object(
      'season_player_id', p_season_player_id,
      'target_count', v_target_count,
      'created_count', v_created,
      'skipped_recent_count', v_skipped_recent,
      'skipped_no_subscription_count', v_skipped_no_subscription
    )
  );

  return jsonb_build_object(
    'target_count', v_target_count,
    'created_count', v_created,
    'skipped_recent_count', v_skipped_recent,
    'skipped_no_subscription_count', v_skipped_no_subscription
  );
end;
$function$;

create or replace function public.admin_send_custom_push(
  p_title text,
  p_body text,
  p_profile_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_title text := nullif(btrim(p_title), '');
  v_body text := nullif(btrim(p_body), '');
  v_recipients uuid[];
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Admin required' using errcode = '42501';
  end if;
  if private.is_feature_enabled('notifications_paused') then
    raise exception 'Les notifications sont désactivées.' using errcode = '55000';
  end if;
  if v_title is null or v_body is null then
    raise exception 'Un titre et un message sont requis' using errcode = '22023';
  end if;
  if char_length(v_title) > 80 then
    raise exception 'Le titre ne peut pas dépasser 80 caractères'
      using errcode = '22023';
  end if;
  if char_length(v_body) > 300 then
    raise exception 'Le message ne peut pas dépasser 300 caractères'
      using errcode = '22023';
  end if;
  if p_profile_ids is null or array_length(p_profile_ids, 1) is null then
    raise exception 'Choisis au moins un destinataire' using errcode = '22023';
  end if;

  select coalesce(array_agg(profile.id), '{}'::uuid[])
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active'
    and exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = profile.id
    );

  v_count := coalesce(array_length(v_recipients, 1), 0);
  if v_count = 0 then
    raise exception 'Aucun destinataire n’a activé les notifications.'
      using errcode = '22023';
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    raise exception 'Notifications push non configurées';
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'title', v_title,
      'message', v_body,
      'profile_ids', to_jsonb(v_recipients)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return v_count;
end;
$function$;
