-- Inactive roster members must not appear or receive reminders for upcoming
-- matches. Past match records remain readable and audit trails are preserved.
-- 2026-11-11: Babinski appears as "Sans réponse" despite is_active=false.
--
-- An inactive member is excluded at the API boundary (including inactive
-- coaches), all notification paths and the self-service availability write.
-- The roster update trigger also withdraws future eligibility.

create or replace function private.sync_season_player_upcoming_matches()
returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  -- Joining (including reactivation) attaches missing future match rows.
  if new.is_active and (tg_op = 'INSERT' or not old.is_active) then
    perform private.attach_season_player_to_upcoming_matches(new.id);
  end if;

  -- Leaving the roster immediately removes eligibility on *future* fixtures,
  -- without deleting answers, notification history or played match snapshots.
  -- A subsequent reactivation restores normal eligibility for those fixtures.
  if tg_op = 'UPDATE' and new.is_active is distinct from old.is_active then
    update public.match_sport_participants participant
    set is_eligible = (new.is_active and not new.is_coach),
        updated_at = now()
    from public.matches match
    where participant.season_player_id = new.id
      and participant.match_id = match.id
      and match.status = 'a_venir'
      and match.kickoff_at > now()
      and participant.is_eligible is distinct from
        (new.is_active and not new.is_coach);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.get_match_convocations(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
      and workflow.convocation_state = 'draft'
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', coalesce(opponent.name, 'Match entre nous'),
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'published_squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'has_unpublished_changes', false,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', coalesce(players.available_count, 0),
    'convoked_count', coalesce(players.convoked_count, 0),
    'not_convoked_count', coalesce(players.not_convoked_count, 0),
    'players', coalesce(players.items, '[]'::jsonb)
  )
  into v_result
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join lateral (
    select
      count(*) filter (
        where row.is_eligible
          and (
            (row.season_player_id is not null and row.availability_status = 'available')
            or row.guest_player_id is not null
          )
      )::integer as available_count,
      count(*) filter (
        where row.is_eligible
          and row.convocation_status = 'convoked'
          and (
            row.availability_status = 'available'
            or row.guest_player_id is not null
          )
      )::integer as convoked_count,
      count(*) filter (
        where row.is_eligible
          and row.season_player_id is not null
          and row.availability_status = 'available'
          and row.convocation_status = 'not_convoked'
      )::integer as not_convoked_count,
      jsonb_agg(
        jsonb_build_object(
          'participant_id', row.participant_id,
          'season_player_id', row.season_player_id,
          'guest_player_id', row.guest_player_id,
          'first_name', row.first_name,
          'last_name', row.last_name,
          'display_name', row.display_name,
          'photo_url', row.photo_url,
          'is_guest', row.guest_player_id is not null,
          'is_coach', row.is_coach,
          'is_goalkeeper', row.is_goalkeeper,
          'availability_status', row.availability_status,
          'availability_updated_at', row.availability_updated_at,
          'convocation_status', row.convocation_status,
          'published_convocation_status', row.convocation_status,
          'manual_override', row.convocation_manual_override,
          'waitlist_position', row.waitlist_position,
          'waitlist_position_snapshot', row.waitlist_position_snapshot,
          'current_season_waitlist_count', row.current_season_waitlist_count,
          'recommended_not_convoked', row.waitlist_recommended_not_convoked,
          'turn_should_consume', row.waitlist_turn_should_consume,
          'turn_state', row.waitlist_turn_state,
          'promoted_after_withdrawal_at', row.promoted_after_withdrawal_at
        )
        order by row.availability_order, row.waitlist_position,
          lower(row.first_name), lower(coalesce(row.last_name, ''))
      ) filter (
        where row.participant_id is not null
          and (row.is_eligible or row.is_coach)
      ) as items
    from (
      select
        participant.id as participant_id,
        participant.season_player_id,
        participant.guest_player_id,
        participant.is_eligible,
        coalesce(player.is_coach, false) as is_coach,
        coalesce(player.first_name, guest.first_name) as first_name,
        coalesce(player.last_name, guest.last_name) as last_name,
        case
          when guest.id is not null then btrim(guest.first_name) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''),
            nullif(btrim(profile.first_name), ''),
            btrim(player.first_name)
          )
        end as display_name,
        coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
        coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
        participant.availability_status,
        participant.availability_updated_at,
        participant.convocation_status,
        participant.convocation_manual_override,
        waitlist.position as waitlist_position,
        participant.waitlist_position_snapshot,
        coalesce(waitlist.manual_waitlist_count, 0) as current_season_waitlist_count,
        participant.waitlist_recommended_not_convoked,
        participant.waitlist_turn_should_consume,
        participant.waitlist_turn_state,
        participant.promoted_after_withdrawal_at,
        case
          when participant.guest_player_id is not null then 0
          when participant.availability_status = 'available' then 0
          when participant.availability_status = 'no_response' then 1
          when participant.availability_status = 'absent' then 2
          else 3
        end as availability_order
      from public.match_sport_participants participant
      left join public.season_players player
        on player.id = participant.season_player_id
      left join public.profiles profile on profile.id = player.profile_id
      left join public.guest_players guest
        on guest.id = participant.guest_player_id
      left join public.sport_waitlist_entries waitlist
        on waitlist.season_player_id = participant.season_player_id
       and waitlist.season_id = match.season_id
      where participant.match_id = match.id
        -- Keep finished match snapshots, but current fixtures follow the active roster.
        and (
          participant.guest_player_id is not null
          or match.status <> 'a_venir'
          or match.kickoff_at <= now()
          or coalesce(player.is_active, false)
        )
    ) row
  ) players on true
  where match.id = p_match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.get_match_availability_board(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'kickoff_at', match.kickoff_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'composition_published', exists (
      select 1
      from public.match_composition_publications publication
      where publication.match_id = match.id
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'display_name', case
          when guest.id is not null then btrim(guest.first_name)
          else coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), btrim(player.first_name))
        end,
        'is_guest', guest.id is not null,
        'is_coach', coalesce(player.is_coach, false),
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'is_unavailable', private.is_player_unavailable_at(
          profile.id, match.kickoff_at
        ),
        'status', participant.availability_status,
        'convocation_status', participant.convocation_status,
        'waitlist_position', waitlist.position,
        'promoted_from_participant_id', participant.promoted_from_participant_id
      )
      order by
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null) then 0
          when participant.availability_status = 'available' then 1
          when participant.availability_status = 'absent' then 2
          when participant.availability_status = 'no_response' then 3
          else 4
        end,
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null)
            then waitlist.position
        end desc nulls last,
        case
          when participant.convocation_status = 'not_convoked'
            and participant.availability_status = 'available'
            then waitlist.position
        end asc nulls last,
        lower(coalesce(player.first_name, guest.first_name, '')),
        participant.id
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
   and (
     participant.is_eligible
     or private.participant_is_coach(participant.season_player_id)
   )
   and (
     participant.guest_player_id is not null
     or match.status <> 'a_venir'
     or match.kickoff_at <= now()
     or exists (
       select 1 from public.season_players active_player
       where active_player.id = participant.season_player_id
         and active_player.is_active
     )
   )
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.get_sport_availability_reminder_summary(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', workflow.match_id,
    'availability_state', workflow.availability_state,
    'no_response_count', (
      select count(*)
      from public.match_sport_participants participant
      where participant.match_id = workflow.match_id
        and (
          match.status <> 'a_venir'
          or match.kickoff_at <= now()
          or exists (
            select 1 from public.season_players active_player
            where active_player.id = participant.season_player_id
              and active_player.is_active
          )
        )
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        )
        and participant.availability_status = 'no_response'
    ),
    'open_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_open'
    ),
    'j3_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_j3'
    ),
    'j1_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_j1'
    ),
    'last_manual_at', (
      select max(event.requested_at)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_manual'
    ),
    'can_remind', workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > now(),
    'players', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'season_player_id', participant.season_player_id,
          'last_reminder_at', reminder.last_reminder_at,
          'manual_cooldown_until', reminder.last_manual_at + interval '10 minutes',
          'manual_reminder_count', reminder.manual_count
        ) order by participant.season_player_id
      )
      from public.match_sport_participants participant
      left join lateral (
        select
          max(event.requested_at) as last_reminder_at,
          max(event.requested_at) filter (
            where event.kind = 'availability_manual'
          ) as last_manual_at,
          count(*) filter (
            where event.kind = 'availability_manual'
          ) as manual_count
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
      ) reminder on true
      where participant.match_id = workflow.match_id
        and (
          match.status <> 'a_venir'
          or match.kickoff_at <= now()
          or exists (
            select 1 from public.season_players active_player
            where active_player.id = participant.season_player_id
              and active_player.is_active
          )
        )
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        )
    ), '[]'::jsonb)
  )
  into v_result
  from public.match_sport_workflows workflow
  join public.matches match on match.id = workflow.match_id
  where workflow.match_id = p_match_id;

  if v_result is null then
    raise exception 'Sports workflow not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.send_sport_availability_reminder(p_match_id uuid, p_season_player_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      and (participant.is_eligible or player.is_coach)
      and participant.availability_status = 'no_response'
      and player.profile_id is not null
      and profile.status = 'active'
      and player.is_active
      and (
        p_season_player_id is null
        or participant.season_player_id = p_season_player_id
      )
    order by participant.id
  loop
    v_target_count := v_target_count + 1;

    -- Sans téléphone abonné, la relance est quand même créée pour arriver
    -- dans l'historique du joueur (même délai de dix minutes), mais elle
    -- reste comptée parmi les joueurs sans notifications, pas parmi les
    -- relances envoyées : le retour affiché à l'admin garde son sens.
    if not exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = v_row.profile_id
    ) then
      v_skipped_no_subscription := v_skipped_no_subscription + 1;
      if not exists (
        select 1
        from public.sport_availability_notification_events event
        where event.participant_id = v_row.participant_id
          and event.kind = 'availability_manual'
          and event.requested_at > now() - interval '10 minutes'
      ) then
        perform private.create_sport_availability_notification(
          p_match_id,
          v_row.participant_id,
          v_row.profile_id,
          'availability_manual',
          'manual',
          now(),
          v_actor,
          v_reason
        );
      end if;
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

CREATE OR REPLACE FUNCTION private.process_sport_availability_notifications(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row record;
  v_event_id bigint;
  v_opened integer := 0;
  v_closed integer := 0;
  v_created integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'opened_workflows', 0,
      'closed_workflows', 0,
      'notifications_created', 0
    );
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where match.status = 'a_venir'
      and match.kickoff_at > p_now
      and workflow.availability_state = 'pending'
      and workflow.availability_opens_at <= p_now
  ) then
    with opened as (
      update public.match_sport_workflows workflow
      set availability_state = 'open',
          availability_opened_at = coalesce(workflow.availability_opened_at, p_now),
          updated_at = p_now
      from public.matches match
      where match.id = workflow.match_id
        and match.status = 'a_venir'
        and match.kickoff_at > p_now
        and workflow.availability_state = 'pending'
        and workflow.availability_opens_at <= p_now
      returning workflow.match_id
    )
    select count(*)::integer into v_opened from opened;
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.availability_state <> 'closed'
      and (match.status <> 'a_venir' or match.kickoff_at <= p_now)
  ) then
    with closed as (
      update public.match_sport_workflows workflow
      set availability_state = 'closed', updated_at = p_now
      from public.matches match
      where match.id = workflow.match_id
        and workflow.availability_state <> 'closed'
        and (match.status <> 'a_venir' or match.kickoff_at <= p_now)
      returning workflow.match_id
    )
    select count(*)::integer into v_closed from closed;
  end if;

  if private.is_feature_enabled('notifications_paused') then
    return jsonb_build_object(
      'opened_workflows', v_opened,
      'closed_workflows', v_closed,
      'notifications_created', 0
    );
  end if;

  for v_row in
    select
      workflow.match_id,
      workflow.availability_opens_at,
      workflow.availability_opened_at,
      participant.id as participant_id,
      player.profile_id
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    join public.match_sport_participants participant on participant.match_id = workflow.match_id
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > p_now
      and (participant.is_eligible or player.is_coach)
      and player.is_active
      and profile.status = 'active'
      and not private.is_player_unavailable_at(player.profile_id, match.kickoff_at)
      and not exists (
        select 1
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
          and event.kind = 'availability_open'
          and event.source = 'automatic'
          and event.scheduled_for = workflow.availability_opens_at
      )
      and not exists (
        select 1
        from public.push_notification_log log
        where log.match_id = workflow.match_id
          and log.kind = 'match_rescheduled_date'
          and workflow.availability_opened_at is not null
          and log.sent_at >= workflow.availability_opened_at
      )
    order by match.kickoff_at, participant.id
  loop
    v_event_id := private.create_sport_availability_notification(
      v_row.match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_open',
      'automatic',
      v_row.availability_opens_at,
      null,
      null
    );
    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'opened_workflows', v_opened,
    'closed_workflows', v_closed,
    'notifications_created', v_created
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.get_my_match_availability(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', participant.match_id,
    'participant_id', participant.id,
    'season_player_id', participant.season_player_id,
    'is_eligible', participant.is_eligible,
    'is_coach', player.is_coach,
    'availability_status', participant.availability_status,
    'private_comment', participant.availability_comment_private,
    'availability_updated_at', participant.availability_updated_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'kickoff_at', match.kickoff_at,
    'unavailability_reason', unavailability.reason,
    'unavailability_starts_on', unavailability.starts_on,
    'unavailability_ends_on', unavailability.ends_on,
    'can_respond', (participant.is_eligible or player.is_coach)
      and now() >= workflow.availability_opens_at
      and now() < match.kickoff_at
      and workflow.availability_state <> 'closed'
      and unavailability.id is null,
    'composition_state', workflow.composition_state,
    'convocation_state', workflow.convocation_state,
    'convocation_status', case
      when workflow.convocation_state = 'published'
        and (participant.is_eligible or player.is_coach)
        then participant.convocation_status::text
      else null
    end
  ) into v_result
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  left join lateral (
    select period.id, period.reason, period.starts_on, period.ends_on
    from public.player_unavailabilities period
    where period.profile_id = player.profile_id
      and (match.kickoff_at at time zone 'Europe/Paris')::date
          between period.starts_on and period.ends_on
    order by period.starts_on
    limit 1
  ) unavailability on true
  where participant.match_id = p_match_id
    and player.profile_id = v_actor
    and (
      player.is_active
      or match.status <> 'a_venir'
      or match.kickoff_at <= now()
    );

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.set_my_match_availability(p_match_id uuid, p_status text, p_private_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_is_eligible boolean;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_composition_state public.sport_composition_state;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
  v_is_coach boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('available', 'absent') then
    raise exception 'Availability status must be available or absent' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status = 'available' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.is_eligible, player.is_coach,
    participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_is_eligible, v_is_coach, v_old_status, v_old_comment,
    v_workflow_state,
    v_opens_at, v_composition_state, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and (participant.is_eligible or player.is_coach)
    and player.is_active
    and player.profile_id = v_actor
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;
  if private.is_player_unavailable_at(v_actor, v_kickoff_at) then
    raise exception 'Ce match tombe dans une indisponibilité que tu as déclarée.'
      using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_forced_by_unavailability = false,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'player'
    );

    -- Le coach répond comme tout le monde, mais il n'occupe aucune place de
    -- la rotation : sa réponse le pose dans l'effectif ou l'en retire sans
    -- jamais faire monter ni redescendre un joueur de la liste d'attente.
    if v_is_coach then
      perform private.recompute_match_convocations_internal(p_match_id, false);
    elsif v_is_eligible then
      if v_convocation_state = 'published'
         and v_old_status = 'available'
         and v_new_status = 'absent' then
        v_promoted_player_id := private.handle_convoked_withdrawal(
          p_match_id, v_participant_id, v_actor, 'player'
        );
      elsif v_convocation_state = 'published'
         and v_old_status = 'absent'
         and v_new_status = 'available' then
        v_promoted_player_id := private.restore_returning_convoked_player(
          p_match_id, v_participant_id, v_actor, 'player'
        );
      else
        perform private.recompute_match_convocations_internal(p_match_id, false);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id,
    'composition_already_published',
      v_composition_state in ('published', 'updated', 'closed')
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.internal_sport_push_dispatch(p_kind text, p_match_id uuid, p_profile_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_recipients jsonb;
  v_date text;
  v_time text;
begin
  if p_kind not in ('availability_open', 'availability_manual', 'convocation_promoted') then
    raise exception 'Unknown sports notification kind' using errcode = '22023';
  end if;
  if p_profile_ids is null or cardinality(p_profile_ids) = 0 then
    return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
  end if;

  select m.id, m.kickoff_at, nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  v_payload := case p_kind
    when 'availability_open' then jsonb_build_object(
      'title', 'Disponibilité',
      'body', case
        when v_match.opponent_name is null then format(
          'Es-tu disponible pour le match entre nous du %s à %s ?',
          v_date, v_time
        )
        else format(
          'Es-tu disponible pour le match du %s contre %s à %s ?',
          v_date, v_match.opponent_name, v_time
        )
      end,
      'url', 'matches?match=' || p_match_id,
      'tag', 'sport-' || p_match_id || '-availability-open'
    )
    when 'availability_manual' then jsonb_build_object(
      'title', 'Tu n''as pas répondu 👀',
      'body', case
        when v_match.opponent_name is null then
          'Pense à indiquer si tu es disponible pour le match entre nous !'
        else format(
          'Pense à indiquer si tu es disponible pour le match contre %s !',
          v_match.opponent_name
        )
      end,
      'url', 'matches?match=' || p_match_id,
      'tag', 'sport-' || p_match_id || '-availability-manual'
    )
    else jsonb_build_object(
      'title', 'Tu es convoqué',
      'body', case
        when v_match.opponent_name is null then format(
          'Tu es convoqué pour le match entre nous du %s.',
          v_date
        )
        else format(
          'Tu es convoqué pour le match du %s contre %s.',
          v_date, v_match.opponent_name
        )
      end,
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-convocation'
    )
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id', subscription.profile_id,
    'endpoint', subscription.endpoint,
    'p256dh', subscription.p256dh,
    'auth', subscription.auth
  )), '[]'::jsonb)
  into v_subscriptions
  from public.push_subscriptions subscription
  join public.profiles profile on profile.id = subscription.profile_id
  where subscription.profile_id = any(p_profile_ids)
    and profile.status = 'active'
    and (
      (p_kind = 'availability_open' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.is_active
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.is_active
          and participant.availability_status = 'no_response'
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'convocation_promoted'
          and profile.notify_convocation
          and exists (
            select 1
            from public.match_sport_participants participant
            join public.season_players player on player.id = participant.season_player_id
            join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
            where participant.match_id = p_match_id
              and (participant.is_eligible or player.is_coach)
          and player.is_active
              and participant.convocation_status = 'convoked'
              and workflow.convocation_state = 'published'
              and player.profile_id = subscription.profile_id
          ))
    );

  -- Mêmes conditions sans les téléphones abonnés : l'historique reçoit aussi
  -- les joueurs sans appareil.
  select coalesce(jsonb_agg(profile.id order by profile.id), '[]'::jsonb)
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active'
    and (
      (p_kind = 'availability_open' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.is_active
          and player.profile_id = profile.id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
          and player.is_active
          and participant.availability_status = 'no_response'
          and player.profile_id = profile.id
      ))
      or (p_kind = 'convocation_promoted'
          and profile.notify_convocation
          and exists (
            select 1
            from public.match_sport_participants participant
            join public.season_players player on player.id = participant.season_player_id
            join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
            where participant.match_id = p_match_id
              and (participant.is_eligible or player.is_coach)
          and player.is_active
              and participant.convocation_status = 'convoked'
              and workflow.convocation_state = 'published'
              and player.profile_id = profile.id
          ))
    );

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', v_subscriptions,
    'recipient_profile_ids', v_recipients
  );
end;
$function$;

-- Repair existing inactive members in pending fixtures without erasing
-- historic responses or delivery evidence.
update public.match_sport_participants participant
set is_eligible = false,
    updated_at = now()
from public.matches match, public.season_players player
where match.id = participant.match_id
  and player.id = participant.season_player_id
  and not player.is_active
  and match.status = 'a_venir'
  and match.kickoff_at > now()
  and participant.is_eligible;

-- The Babinski (Roman) roster row was newly created on 2026-11-11 while
-- unneeded. Its untouched future "no response" rows can be cleared, except
-- those with notification, decision, lineup or match-action history.
-- One 16-Nov opening notification is already completed; keep its parent row
-- as an inert, invisible audit anchor.
delete from public.match_sport_participants participant
using public.matches match
where participant.match_id = match.id
  and participant.season_player_id = 'fdccd9a2-4918-486f-84ff-e5cf7256cc54'::uuid
  and match.status = 'a_venir'
  and match.kickoff_at > now()
  and participant.availability_status = 'no_response'
  and participant.convocation_status = 'not_applicable'
  and not participant.convocation_manual_override
  and not exists (select 1 from public.sport_availability_notification_events n
                  where n.participant_id = participant.id)
  and not exists (select 1 from public.match_sport_participant_events e
                  where e.participant_id = participant.id)
  and not exists (select 1 from public.match_composition_entries c
                  where c.participant_id = participant.id)
  and not exists (select 1 from public.match_internal_composition_entries c
                  where c.participant_id = participant.id)
  and not exists (select 1 from public.match_live_events e
                  where e.match_id = participant.match_id and
                    participant.id in (e.scorer_participant_id,e.assist_participant_id,
                                       e.player_in_participant_id,e.player_out_participant_id))
  and not exists (select 1 from public.match_sport_goal_actions e
                  where e.match_id = participant.match_id and
                    participant.id in (e.scorer_participant_id,e.assist_participant_id));
