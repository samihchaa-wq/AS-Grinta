-- Notifications de buts / fin de match, opt-in par match.
-- La cloche est disponible pour tous les profils actifs, uniquement sur les
-- matchs championnat/amical, à partir de l'ouverture réelle des disponibilités.

create table public.match_live_notification_subscriptions (
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (match_id, profile_id)
);

alter table public.match_live_notification_subscriptions enable row level security;

revoke all on table public.match_live_notification_subscriptions
  from public, anon, authenticated;
grant select on table public.match_live_notification_subscriptions
  to authenticated;

create policy match_live_notification_subscriptions_owner_select
on public.match_live_notification_subscriptions
for select
to authenticated
using (
  profile_id = (select auth.uid())
  and (select private.is_active_profile())
);

create table private.match_live_notification_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  live_event_id uuid,
  kind text not null check (kind in ('goal_us', 'goal_them', 'full_time')),
  due_at timestamptz not null,
  scorer_deadline timestamptz,
  scorer_name text,
  score_as_grinta integer not null check (score_as_grinta between 0 and 99),
  score_adverse integer not null check (score_adverse between 0 and 99),
  state text not null default 'pending'
    check (state in ('pending', 'dispatching', 'sent', 'cancelled')),
  last_requested_at timestamptz,
  claimed_at timestamptz,
  completed_at timestamptz,
  attempted integer not null default 0 check (attempted >= 0),
  sent integer not null default 0 check (sent >= 0),
  failed integer not null default 0 check (failed >= 0),
  created_at timestamptz not null default now()
);

create unique index match_live_notification_goal_once
  on private.match_live_notification_events(live_event_id)
  where live_event_id is not null;

create unique index match_live_notification_full_time_once
  on private.match_live_notification_events(match_id)
  where kind = 'full_time';

create index match_live_notification_due_pending
  on private.match_live_notification_events(due_at)
  where state = 'pending';

create table private.match_live_notification_event_targets (
  notification_id uuid not null
    references private.match_live_notification_events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (notification_id, profile_id)
);

alter table private.match_live_notification_events enable row level security;
alter table private.match_live_notification_event_targets enable row level security;

create or replace function private.match_live_notifications_eligible(
  p_match_id uuid,
  p_at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.matches match
    join public.match_sport_workflows workflow
      on workflow.match_id = match.id
    left join public.match_live_sessions session
      on session.match_id = match.id
    where match.id = p_match_id
      and match.match_type in ('championnat', 'amical')
      and match.status = 'a_venir'
      and p_at >= workflow.availability_opens_at
      and coalesce(session.state::text, '') <> 'finished'
  );
$function$;

revoke all on function private.match_live_notifications_eligible(uuid, timestamptz)
  from public, anon, authenticated;

create or replace function public.get_match_live_notification_subscription(
  p_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid := (select auth.uid());
  v_opens_at timestamptz;
  v_eligible boolean;
  v_subscribed boolean;
begin
  if v_profile_id is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.matches match where match.id = p_match_id
  ) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select workflow.availability_opens_at
  into v_opens_at
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  v_eligible := private.match_live_notifications_eligible(p_match_id, now());

  select exists (
    select 1
    from public.match_live_notification_subscriptions subscription
    where subscription.match_id = p_match_id
      and subscription.profile_id = v_profile_id
      and subscription.completed_at is null
  ) into v_subscribed;

  return jsonb_build_object(
    'eligible', v_eligible,
    'subscribed', v_subscribed,
    'opens_at', v_opens_at
  );
end;
$function$;

revoke all on function public.get_match_live_notification_subscription(uuid)
  from public, anon;
grant execute on function public.get_match_live_notification_subscription(uuid)
  to authenticated;

create or replace function public.set_match_live_notifications(
  p_match_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id uuid := (select auth.uid());
begin
  if v_profile_id is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'Enabled flag is required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.matches match where match.id = p_match_id
  ) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if not p_enabled then
    delete from public.match_live_notification_subscriptions subscription
    where subscription.match_id = p_match_id
      and subscription.profile_id = v_profile_id;

    return public.get_match_live_notification_subscription(p_match_id);
  end if;

  if not private.match_live_notifications_eligible(p_match_id, now()) then
    raise exception 'Goal notifications are not available for this match'
      using errcode = '22023';
  end if;

  insert into public.match_live_notification_subscriptions(
    match_id,
    profile_id,
    created_at,
    updated_at,
    completed_at
  )
  values (p_match_id, v_profile_id, now(), now(), null)
  on conflict (match_id, profile_id)
  do update
  set updated_at = excluded.updated_at,
      completed_at = null;

  return public.get_match_live_notification_subscription(p_match_id);
end;
$function$;

revoke all on function public.set_match_live_notifications(uuid, boolean)
  from public, anon;
grant execute on function public.set_match_live_notifications(uuid, boolean)
  to authenticated;

create or replace function private.match_live_notification_scorer_name(
  p_participant_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    nullif(btrim(profile.surnom), ''),
    nullif(btrim(profile.first_name), ''),
    nullif(btrim(player.first_name), ''),
    nullif(btrim(guest.first_name), '')
  )
  from public.match_sport_participants participant
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  where participant.id = p_participant_id;
$function$;

revoke all on function private.match_live_notification_scorer_name(uuid)
  from public, anon, authenticated;

create or replace function private.request_match_live_notification_delivery(
  p_notification_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  update private.match_live_notification_events event
  set last_requested_at = now()
  where event.id = p_notification_id
    and event.state = 'pending'
    and event.due_at <= now()
    and (
      event.last_requested_at is null
      or event.last_requested_at <= now() - interval '4 seconds'
    );

  if not found then
    return null;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return null;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'live_match',
      'live_notification_id', p_notification_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 15000
  ) into v_request_id;

  return v_request_id;
exception
  when others then
    return null;
end;
$function$;

revoke all on function private.request_match_live_notification_delivery(uuid)
  from public, anon, authenticated;

create or replace function private.snapshot_match_live_notification_targets(
  p_notification_id uuid,
  p_match_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  insert into private.match_live_notification_event_targets(
    notification_id,
    profile_id
  )
  select
    p_notification_id,
    subscription.profile_id
  from public.match_live_notification_subscriptions subscription
  join public.profiles profile
    on profile.id = subscription.profile_id
  where subscription.match_id = p_match_id
    and subscription.completed_at is null
    and profile.status = 'active'
  on conflict do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke all on function private.snapshot_match_live_notification_targets(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.queue_match_live_goal_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_type text;
  v_score_us integer;
  v_score_them integer;
  v_notification_id uuid;
  v_scorer_name text;
  v_target_count integer;
begin
  if new.event_type not in ('goal_us', 'goal_them') then
    return new;
  end if;

  select match.match_type
  into v_match_type
  from public.matches match
  where match.id = new.match_id;

  if v_match_type not in ('championnat', 'amical') then
    return new;
  end if;

  if not exists (
    select 1
    from public.match_live_notification_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where subscription.match_id = new.match_id
      and subscription.completed_at is null
      and profile.status = 'active'
  ) then
    return new;
  end if;

  select session.score_as_grinta, session.score_adverse
  into v_score_us, v_score_them
  from public.match_live_sessions session
  where session.match_id = new.match_id;

  if not found then
    return new;
  end if;

  if new.event_type = 'goal_us' and new.scorer_participant_id is not null then
    v_scorer_name :=
      private.match_live_notification_scorer_name(new.scorer_participant_id);
  end if;

  insert into private.match_live_notification_events(
    match_id,
    live_event_id,
    kind,
    due_at,
    scorer_deadline,
    scorer_name,
    score_as_grinta,
    score_adverse
  )
  values (
    new.match_id,
    new.id,
    new.event_type,
    case
      when new.event_type = 'goal_them' then now()
      when new.scorer_participant_id is not null then now()
      else new.created_at + interval '60 seconds'
    end,
    case
      when new.event_type = 'goal_us'
        then new.created_at + interval '60 seconds'
      else null
    end,
    v_scorer_name,
    v_score_us,
    v_score_them
  )
  on conflict (live_event_id) where live_event_id is not null
  do nothing
  returning id into v_notification_id;

  if v_notification_id is null then
    return new;
  end if;

  v_target_count := private.snapshot_match_live_notification_targets(
    v_notification_id,
    new.match_id
  );

  if v_target_count = 0 then
    update private.match_live_notification_events event
    set state = 'cancelled',
        completed_at = now()
    where event.id = v_notification_id;
    return new;
  end if;

  if new.event_type = 'goal_them'
     or new.scorer_participant_id is not null then
    perform private.request_match_live_notification_delivery(v_notification_id);
  end if;

  return new;
end;
$function$;

drop trigger if exists match_live_goal_notification_insert
  on public.match_live_events;
create trigger match_live_goal_notification_insert
after insert on public.match_live_events
for each row
execute function private.queue_match_live_goal_notification();

create or replace function private.update_match_live_goal_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_notification_id uuid;
  v_scorer_name text;
begin
  if new.event_type <> 'goal_us' then
    return new;
  end if;

  if new.scorer_participant_id is not distinct from old.scorer_participant_id
     and new.is_opponent_own_goal is not distinct from old.is_opponent_own_goal then
    return new;
  end if;

  if new.scorer_participant_id is not null then
    v_scorer_name :=
      private.match_live_notification_scorer_name(new.scorer_participant_id);
  end if;

  update private.match_live_notification_events event
  set scorer_name = v_scorer_name,
      due_at = now()
  where event.live_event_id = new.id
    and event.kind = 'goal_us'
    and event.state = 'pending'
    and now() <= event.scorer_deadline
  returning event.id into v_notification_id;

  if v_notification_id is not null then
    perform private.request_match_live_notification_delivery(v_notification_id);
  end if;

  return new;
end;
$function$;

drop trigger if exists match_live_goal_notification_update
  on public.match_live_events;
create trigger match_live_goal_notification_update
after update of scorer_participant_id, is_opponent_own_goal
on public.match_live_events
for each row
execute function private.update_match_live_goal_notification();

create or replace function private.cancel_deleted_match_live_goal_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update private.match_live_notification_events event
  set state = 'cancelled',
      completed_at = now()
  where event.live_event_id = old.id
    and event.state = 'pending';

  return old;
end;
$function$;

drop trigger if exists match_live_goal_notification_delete
  on public.match_live_events;
create trigger match_live_goal_notification_delete
before delete on public.match_live_events
for each row
execute function private.cancel_deleted_match_live_goal_notification();

create or replace function private.queue_match_live_full_time_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_type text;
  v_notification_id uuid;
  v_target_count integer;
begin
  if new.state::text <> 'finished'
     or old.state::text = 'finished' then
    return new;
  end if;

  select match.match_type
  into v_match_type
  from public.matches match
  where match.id = new.match_id;

  if v_match_type not in ('championnat', 'amical') then
    return new;
  end if;

  if not exists (
    select 1
    from public.match_live_notification_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where subscription.match_id = new.match_id
      and subscription.completed_at is null
      and profile.status = 'active'
  ) then
    return new;
  end if;

  insert into private.match_live_notification_events(
    match_id,
    kind,
    due_at,
    score_as_grinta,
    score_adverse
  )
  values (
    new.match_id,
    'full_time',
    now(),
    new.score_as_grinta,
    new.score_adverse
  )
  on conflict (match_id) where kind = 'full_time'
  do nothing
  returning id into v_notification_id;

  if v_notification_id is null then
    return new;
  end if;

  v_target_count := private.snapshot_match_live_notification_targets(
    v_notification_id,
    new.match_id
  );

  if v_target_count = 0 then
    update private.match_live_notification_events event
    set state = 'cancelled',
        completed_at = now()
    where event.id = v_notification_id;
    return new;
  end if;

  perform private.request_match_live_notification_delivery(v_notification_id);
  return new;
end;
$function$;

drop trigger if exists match_live_full_time_notification
  on public.match_live_sessions;
create trigger match_live_full_time_notification
after update of state on public.match_live_sessions
for each row
execute function private.queue_match_live_full_time_notification();

create or replace function public.internal_claim_match_live_notification(
  p_notification_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event private.match_live_notification_events%rowtype;
  v_match record;
  v_home_name text;
  v_away_name text;
  v_home_score integer;
  v_away_score integer;
  v_scoreline text;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_log_kind text;
begin
  update private.match_live_notification_events event
  set state = 'dispatching',
      claimed_at = now()
  where event.id = p_notification_id
    and event.state = 'pending'
    and event.due_at <= now()
  returning event.* into v_event;

  if not found then
    return jsonb_build_object('claimed', false);
  end if;

  select
    match.location,
    coalesce(nullif(btrim(opponent.name), ''), 'Adversaire') as opponent_name
  into v_match
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = v_event.match_id;

  if not found then
    update private.match_live_notification_events event
    set state = 'cancelled', completed_at = now()
    where event.id = v_event.id;
    return jsonb_build_object('claimed', false);
  end if;

  if v_match.location = 'domicile' then
    v_home_name := 'AS Grinta';
    v_away_name := v_match.opponent_name;
    v_home_score := v_event.score_as_grinta;
    v_away_score := v_event.score_adverse;
  else
    v_home_name := v_match.opponent_name;
    v_away_name := 'AS Grinta';
    v_home_score := v_event.score_adverse;
    v_away_score := v_event.score_as_grinta;
  end if;

  v_scoreline := format(
    '%s %s–%s %s',
    v_home_name,
    v_home_score,
    v_away_score,
    v_away_name
  );

  if v_event.kind = 'goal_us' then
    v_log_kind := 'live_goal_us';
    v_payload := jsonb_build_object(
      'title', '⚽ But !',
      'body', case
        when nullif(btrim(v_event.scorer_name), '') is not null
          then format('But de %s ! %s', v_event.scorer_name, v_scoreline)
        else format('But pour AS Grinta ! %s', v_scoreline)
      end,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-goal-' || v_event.id
    );
  elsif v_event.kind = 'goal_them' then
    v_log_kind := 'live_goal_them';
    v_payload := jsonb_build_object(
      'title', format('⚽ But pour %s', v_match.opponent_name),
      'body', v_scoreline,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-goal-' || v_event.id
    );
  else
    v_log_kind := 'live_full_time';
    v_payload := jsonb_build_object(
      'title', '🏁 Fin du match',
      'body', v_scoreline,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-full-time'
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', push.profile_id,
        'endpoint', push.endpoint,
        'p256dh', push.p256dh,
        'auth', push.auth
      )
      order by push.profile_id, push.endpoint
    ),
    '[]'::jsonb
  )
  into v_subscriptions
  from private.match_live_notification_event_targets target
  join public.match_live_notification_subscriptions subscription
    on subscription.match_id = v_event.match_id
   and subscription.profile_id = target.profile_id
   and subscription.completed_at is null
  join public.profiles profile
    on profile.id = target.profile_id
   and profile.status = 'active'
  join public.push_subscriptions push
    on push.profile_id = target.profile_id
  where target.notification_id = v_event.id;

  return jsonb_build_object(
    'claimed', true,
    'notification_id', v_event.id,
    'match_id', v_event.match_id,
    'kind', v_log_kind,
    'payload', v_payload,
    'subscriptions', v_subscriptions
  );
end;
$function$;

revoke all on function public.internal_claim_match_live_notification(uuid)
  from public, anon, authenticated;
grant execute on function public.internal_claim_match_live_notification(uuid)
  to service_role;

create or replace function public.internal_mark_match_live_notification_delivery(
  p_notification_id uuid,
  p_attempted integer,
  p_sent integer,
  p_failed integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_kind text;
begin
  if p_attempted < 0 or p_sent < 0 or p_failed < 0
     or p_sent + p_failed <> p_attempted then
    raise exception 'Invalid delivery counters' using errcode = '22023';
  end if;

  update private.match_live_notification_events event
  set state = 'sent',
      attempted = p_attempted,
      sent = p_sent,
      failed = p_failed,
      completed_at = now()
  where event.id = p_notification_id
    and event.state = 'dispatching'
  returning event.match_id, event.kind
  into v_match_id, v_kind;

  if not found then
    return false;
  end if;

  if v_kind = 'full_time' then
    update public.match_live_notification_subscriptions subscription
    set completed_at = now(),
        updated_at = now()
    where subscription.match_id = v_match_id
      and subscription.completed_at is null;
  end if;

  return true;
end;
$function$;

revoke all on function public.internal_mark_match_live_notification_delivery(
  uuid, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.internal_mark_match_live_notification_delivery(
  uuid, integer, integer, integer
) to service_role;

create or replace function private.process_due_match_live_notifications(
  p_limit integer default 50
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event record;
  v_requested integer := 0;
begin
  for v_event in
    select event.id
    from private.match_live_notification_events event
    where event.state = 'pending'
      and event.due_at <= now()
      and (
        event.last_requested_at is null
        or event.last_requested_at <= now() - interval '4 seconds'
      )
    order by event.due_at, event.created_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  loop
    if private.request_match_live_notification_delivery(v_event.id) is not null then
      v_requested := v_requested + 1;
    end if;
  end loop;

  return v_requested;
end;
$function$;

revoke all on function private.process_due_match_live_notifications(integer)
  from public, anon, authenticated;
grant execute on function private.process_due_match_live_notifications(integer)
  to service_role;

alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;
alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check
  check (
    kind = any (array[
      'availability_open'::text,
      'availability_j3'::text,
      'availability_j1'::text,
      'availability_manual'::text,
      'motm_open'::text,
      'prediction_j5'::text,
      'match_cancelled'::text,
      'match_rescheduled_date'::text,
      'match_rescheduled_time'::text,
      'convocation_promoted'::text,
      'live_goal_us'::text,
      'live_goal_them'::text,
      'live_full_time'::text
    ])
  );

do $do$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname = 'live-match-notification-dispatch'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'live-match-notification-dispatch',
    '5 seconds',
    $cron$select private.process_due_match_live_notifications(50);$cron$
  );
end;
$do$;
