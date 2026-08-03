begin;

alter table public.profiles
  add column if not exists notify_motm_vote boolean not null default true,
  add column if not exists notify_convocation boolean not null default true;

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

  old_protected := to_jsonb(old) - array[
    'first_name','last_name','surnom','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation',
    'password_set','must_change_password'
  ];
  new_protected := to_jsonb(new) - array[
    'first_name','last_name','surnom','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation',
    'password_set','must_change_password'
  ];

  if new_protected is distinct from old_protected then
    raise exception 'Les champs sensibles du profil ne peuvent pas être modifiés.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

create or replace function public.update_my_notification_preferences(
  p_notify_prediction boolean,
  p_notify_motm_vote boolean,
  p_notify_convocation boolean
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

  update public.profiles
  set notify_prediction_reminders = coalesce(p_notify_prediction, notify_prediction_reminders),
      notify_motm_vote = coalesce(p_notify_motm_vote, notify_motm_vote),
      notify_convocation = coalesce(p_notify_convocation, notify_convocation),
      updated_at = now()
  where id = v_actor
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;
  return true;
end;
$function$;

revoke all on function public.update_my_notification_preferences(boolean, boolean, boolean)
  from public, anon;
grant execute on function public.update_my_notification_preferences(boolean, boolean, boolean)
  to authenticated;

create or replace function private.match_prediction_notification_at(
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
strict
set search_path to ''
as $function$
  select (
    (((p_kickoff_at at time zone 'Europe/Paris')::date - 5) + time '12:00')
    at time zone 'Europe/Paris'
  );
$function$;

create or replace function private.match_notification_time_label(
  p_kickoff_at timestamptz
)
returns text
language sql
stable
strict
set search_path to ''
as $function$
  select case
    when extract(minute from (p_kickoff_at at time zone 'Europe/Paris'))::integer = 0
      then to_char(p_kickoff_at at time zone 'Europe/Paris', 'HH24"h"')
    else to_char(p_kickoff_at at time zone 'Europe/Paris', 'HH24"h"MI')
  end;
$function$;

alter table public.push_notification_log
  drop constraint if exists push_notification_log_kind_check;
alter table public.push_notification_log
  add constraint push_notification_log_kind_check check (kind = any(array[
    'new_match'::text,
    'closing_soon'::text,
    'result_validated'::text,
    'motm_open'::text,
    'motm_reminder'::text,
    'motm_results'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text
  ]));

alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;
alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check check (kind = any(array[
    'new_match'::text,
    'closing_soon'::text,
    'result_validated'::text,
    'availability_open'::text,
    'availability_j3'::text,
    'availability_j1'::text,
    'availability_manual'::text,
    'motm_open'::text,
    'motm_reminder'::text,
    'motm_results'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text,
    'convocation_promoted'::text
  ]));

drop index if exists public.sport_availability_notification_auto_once_idx;
create unique index sport_availability_notification_auto_once_idx
  on public.sport_availability_notification_events(participant_id, kind, scheduled_for)
  where source = 'automatic';

create or replace function public.internal_push_dispatch(
  p_kind text,
  p_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_date text;
  v_time text;
begin
  select
    m.id,
    m.kickoff_at,
    m.status,
    coalesce(o.name, 'Match entre nous') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  if p_kind = 'prediction_j5' then
    v_payload := jsonb_build_object(
      'title', 'Pronostic',
      'body', format(
        'Pense à pronostiquer pour le match du %s contre %s.',
        v_date,
        v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=prediction',
      'tag', 'match-' || p_match_id || '-prediction-j5'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_prediction_reminders
      and not exists (
        select 1
        from public.match_predictions prediction
        where prediction.match_id = p_match_id
          and prediction.profile_id = profile.id
          and prediction.is_filled
      );

  elsif p_kind in ('match_cancelled', 'match_rescheduled_date', 'match_rescheduled_time') then
    v_payload := case p_kind
      when 'match_cancelled' then jsonb_build_object(
        'title', 'Match annulé',
        'body', format(
          'Le match du %s contre %s à %s est annulé.',
          v_date, v_match.opponent_name, v_time
        ),
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-cancelled'
      )
      when 'match_rescheduled_date' then jsonb_build_object(
        'title', 'Match reporté',
        'body', case
          when private.match_features_open_at(v_match.kickoff_at) <= now()
            then format(
              'Le match contre %s est reporté au %s à %s. Es-tu disponible ?',
              v_match.opponent_name, v_date, v_time
            )
          else format(
            'Le match contre %s est reporté au %s à %s.',
            v_match.opponent_name, v_date, v_time
          )
        end,
        'url', 'matches/' || p_match_id || '/lineup?section=effectif',
        'tag', 'match-' || p_match_id || '-rescheduled-date'
      )
      else jsonb_build_object(
        'title', 'Horaire du match modifié',
        'body', format(
          'Le match du %s contre %s aura finalement lieu à %s.',
          v_date, v_match.opponent_name, v_time
        ),
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-rescheduled-time'
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
    where profile.status = 'active'
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.is_eligible
          and player.profile_id = profile.id
      );

  elsif p_kind = 'motm_open' then
    if not private.is_feature_enabled('sports_management') then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;
    if not exists (
      select 1
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() >= election.opens_at
        and now() < election.closes_at
    ) then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;

    v_payload := jsonb_build_object(
      'title', 'Homme du match',
      'body', 'Pense à voter pour l’homme du match.',
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-open'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_motm_vote
      and exists (
        select 1
        from private.match_motm_candidate_participants(p_match_id) candidate
        join public.match_sport_participants participant on participant.id = candidate.participant_id
        join public.season_players player on player.id = participant.season_player_id
        where player.profile_id = profile.id
      );

  else
    raise exception 'Unknown notification kind: %', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb)
  );
end;
$function$;

create or replace function public.internal_sport_push_dispatch(
  p_kind text,
  p_match_id uuid,
  p_profile_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_date text;
  v_time text;
begin
  if p_kind not in ('availability_open', 'availability_manual', 'convocation_promoted') then
    raise exception 'Unknown sports notification kind' using errcode = '22023';
  end if;
  if p_profile_ids is null or cardinality(p_profile_ids) = 0 then
    return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
  end if;

  select m.id, m.kickoff_at, coalesce(o.name, 'Match entre nous') as opponent_name
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
      'body', format(
        'Dispo pour le match du %s contre %s à %s ?',
        v_date, v_match.opponent_name, v_time
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-availability-open'
    )
    when 'availability_manual' then jsonb_build_object(
      'title', 'Tu n''as pas répondu 👀',
      'body', format(
        'Pense à indiquer si tu es dispo pour le match contre %s !',
        v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-availability-manual'
    )
    else jsonb_build_object(
      'title', 'Tu es convoqué',
      'body', format(
        'Tu es convoqué pour le match du %s contre %s.',
        v_date, v_match.opponent_name
      ),
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
          and participant.is_eligible
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.is_eligible
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
              and participant.is_eligible
              and participant.convocation_status = 'convoked'
              and workflow.convocation_state = 'published'
              and player.profile_id = subscription.profile_id
          ))
    );

  return jsonb_build_object('payload', v_payload, 'subscriptions', v_subscriptions);
end;
$function$;

create or replace function private.process_sport_availability_notifications(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_event_id bigint;
  v_opened integer := 0;
  v_closed integer := 0;
  v_created integer := 0;
begin
  if not private.is_feature_enabled('sports_management')
     or private.is_feature_enabled('notifications_paused') then
    return jsonb_build_object(
      'opened_workflows', 0,
      'closed_workflows', 0,
      'notifications_created', 0
    );
  end if;

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
      and participant.is_eligible
      and profile.status = 'active'
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

create or replace function public.push_prediction_j5_notifications()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_sent integer := 0;
begin
  if private.is_feature_enabled('notifications_paused') then
    return 0;
  end if;

  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and m.kickoff_at is not null
      and now() >= private.match_prediction_notification_at(m.kickoff_at)
      and now() < m.kickoff_at - interval '5 minutes'
      and (m.predictions_closed_at is null or now() < m.predictions_closed_at)
    order by m.kickoff_at
  loop
    insert into public.push_notification_log(match_id, kind, sent_at)
    values (v_match.id, 'prediction_j5', now())
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('prediction_j5', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$function$;

create or replace function private.handle_match_notification_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_in_old_window boolean := false;
  v_date_changed boolean := false;
  v_new_opens_at timestamptz;
  v_new_state public.sport_availability_state;
begin
  if old.kickoff_at is not null then
    v_in_old_window := now() >= private.match_features_open_at(old.kickoff_at)
      and now() < old.kickoff_at;
  end if;

  if old.status = 'a_venir'
     and new.status = 'annule'
     and v_in_old_window then
    if not private.is_feature_enabled('notifications_paused') then
      perform public.internal_push_notify('match_cancelled', new.id);
    end if;
    return new;
  end if;

  if old.status = 'a_venir'
     and new.status = 'a_venir'
     and old.kickoff_at is distinct from new.kickoff_at
     and new.kickoff_at is not null
     and v_in_old_window then
    v_date_changed := (old.kickoff_at at time zone 'Europe/Paris')::date
      is distinct from (new.kickoff_at at time zone 'Europe/Paris')::date;

    if v_date_changed then
      v_new_opens_at := private.match_features_open_at(new.kickoff_at);
      v_new_state := case
        when now() >= new.kickoff_at then 'closed'::public.sport_availability_state
        when now() >= v_new_opens_at then 'open'::public.sport_availability_state
        else 'pending'::public.sport_availability_state
      end;

      update public.match_sport_participants participant
      set availability_status = 'no_response',
          availability_comment_private = null,
          availability_updated_at = null,
          availability_updated_by = null,
          convocation_status = 'not_applicable',
          convocation_manual_override = false,
          waitlist_recommended_not_convoked = false,
          waitlist_turn_should_consume = false,
          updated_at = now()
      where participant.match_id = new.id
        and participant.season_player_id is not null
        and participant.is_eligible;

      update public.match_sport_workflows workflow
      set availability_opens_at = v_new_opens_at,
          availability_state = v_new_state,
          availability_opened_at = case when v_new_state = 'open' then now() else null end,
          convocation_state = 'draft',
          convocation_published_at = null,
          convocation_version = workflow.convocation_version + 1,
          updated_at = now()
      where workflow.match_id = new.id;

      delete from public.push_notification_log
      where match_id = new.id and kind = 'prediction_j5';

      if not private.is_feature_enabled('notifications_paused') then
        insert into public.push_notification_log(match_id, kind, sent_at)
        values (new.id, 'match_rescheduled_date', now())
        on conflict (match_id, kind) do update set sent_at = excluded.sent_at;
        perform public.internal_push_notify('match_rescheduled_date', new.id);
      end if;
    else
      if not private.is_feature_enabled('notifications_paused') then
        perform public.internal_push_notify('match_rescheduled_time', new.id);
      end if;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_notification_match_changes on public.matches;
create trigger trg_notification_match_changes
after update of status, kickoff_at on public.matches
for each row execute function private.handle_match_notification_change();

drop trigger if exists trg_push_on_match_result on public.matches;

create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select least(
    match.kickoff_at + interval '2 hours',
    coalesce((
      select min(version.created_at)
      from public.match_sport_finalization_versions version
      where version.match_id = p_match_id
    ), 'infinity'::timestamptz)
  )
  from public.matches match
  where match.id = p_match_id;
$function$;

create or replace function private.close_due_match_motm_elections()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_processed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select match.id as match_id
    from public.matches match
    where match.kickoff_at + interval '2 hours' <= now()
      and match.kickoff_at > now() - interval '30 days'
      and not exists (
        select 1 from public.match_sport_motm_elections election
        where election.match_id = match.id
      )
      and (
        exists (
          select 1 from public.match_composition_publications pub
          where pub.match_id = match.id
        )
        or exists (
          select 1 from public.match_sport_finalization_versions version
          where version.match_id = match.id
        )
      )
  loop
    perform private.ensure_match_motm_election(v_row.match_id);
  end loop;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state in ('draft', 'open')
    order by election.closes_at nulls last, election.match_id
    for update skip locked
  loop
    perform private.transition_match_motm_election(v_row.match_id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

create or replace function public.push_on_motm_election_opened()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_is_new_window boolean := false;
begin
  if not private.is_feature_enabled('sports_management') then
    return new;
  end if;

  if new.state = 'open' then
    if tg_op = 'INSERT' then
      v_is_new_window := true;
    else
      v_is_new_window := old.state is distinct from 'open'
        or old.opens_at is distinct from new.opens_at
        or old.closes_at is distinct from new.closes_at
        or old.finalization_version is distinct from new.finalization_version;
    end if;
  end if;

  if v_is_new_window then
    delete from public.push_notification_log
    where match_id = new.match_id
      and kind in ('motm_open', 'motm_reminder', 'motm_results');

    if not private.is_feature_enabled('notifications_paused') then
      insert into public.push_notification_log(match_id, kind, sent_at)
      values (new.match_id, 'motm_open', now())
      on conflict do nothing;
      if found then
        perform private.dispatch_motm_push('motm_open', new.match_id);
      end if;
    end if;
  end if;

  return new;
end;
$function$;

create or replace function private.push_due_motm_open_notifications(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_sent integer := 0;
begin
  if private.is_feature_enabled('notifications_paused')
     or not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state = 'open'
      and election.opens_at <= p_now
      and election.closes_at > p_now
      and not exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_open'
      )
    order by election.opens_at, election.match_id
    for update skip locked
  loop
    insert into public.push_notification_log(match_id, kind, sent_at)
    values (v_row.match_id, 'motm_open', p_now)
    on conflict do nothing;
    if found then
      perform private.dispatch_motm_push('motm_open', v_row.match_id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$function$;

create or replace function private.process_match_motm_jobs(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_transitions integer;
  v_open_notifications integer;
begin
  v_transitions := private.close_due_match_motm_elections();
  v_open_notifications := private.push_due_motm_open_notifications(p_now);
  return jsonb_build_object(
    'transitions', v_transitions,
    'open_notifications', v_open_notifications
  );
end;
$function$;

drop trigger if exists trg_push_on_motm_election_closed
  on public.match_sport_motm_elections;

update public.match_sport_motm_elections election
set opens_at = private.match_motm_opens_at(election.match_id),
    updated_at = now()
where election.state = 'draft';

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
begin
  if p_profile_id is null
     or private.is_feature_enabled('notifications_paused') then
    return false;
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
      'kind', 'convocation_promoted',
      'match_id', p_match_id,
      'profile_ids', jsonb_build_array(p_profile_id)
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

create or replace function private.notify_waitlist_promotion()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile_id uuid;
begin
  if old.convocation_status = 'not_convoked'
     and new.convocation_status = 'convoked'
     and exists (
       select 1 from public.match_sport_workflows workflow
       where workflow.match_id = new.match_id
         and workflow.convocation_state = 'published'
     ) then
    select player.profile_id
    into v_profile_id
    from public.season_players player
    join public.profiles profile on profile.id = player.profile_id
    where player.id = new.season_player_id
      and profile.status = 'active'
      and profile.notify_convocation;

    if v_profile_id is not null then
      perform private.dispatch_convocation_push(new.match_id, v_profile_id);
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_notify_waitlist_promotion
  on public.match_sport_participants;
create trigger trg_notify_waitlist_promotion
after update of convocation_status on public.match_sport_participants
for each row execute function private.notify_waitlist_promotion();

do $do$
declare
  v_job record;
begin
  for v_job in
    select jobid from cron.job
    where jobname in ('prediction-closing-reminders', 'prediction-j5-reminders')
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
end;
$do$;

select cron.schedule(
  'prediction-j5-reminders',
  '* * * * *',
  'select public.push_prediction_j5_notifications();'
);

commit;
