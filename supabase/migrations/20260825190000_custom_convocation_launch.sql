-- Allow administrators to choose when the availability/convocation workflow opens.
-- Existing behaviour remains the default: J-6 at 12:00 Europe/Paris.
-- The resolved timestamp remains authoritative in match_sport_workflows so every
-- downstream reader (availability, reminders, composition, notifications) keeps
-- using the same state machine.

alter table public.match_sport_workflows
  add column if not exists availability_schedule_mode text not null default 'automatic';

alter table public.match_sport_workflows
  drop constraint if exists match_sport_workflows_availability_schedule_mode_check;
alter table public.match_sport_workflows
  add constraint match_sport_workflows_availability_schedule_mode_check
  check (availability_schedule_mode in ('automatic', 'custom', 'now'));

comment on column public.match_sport_workflows.availability_schedule_mode is
  'How availability_opens_at was chosen: automatic (J-6 12:00 Europe/Paris), custom, or now.';

create or replace function private.resolve_match_availability_open_at(
  p_kickoff_at timestamptz,
  p_schedule_mode text,
  p_requested_at timestamptz default null
)
returns timestamptz
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_mode text := coalesce(nullif(btrim(p_schedule_mode), ''), 'automatic');
  v_resolved timestamptz;
begin
  if p_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;
  if v_mode not in ('automatic', 'custom', 'now') then
    raise exception 'Invalid availability schedule mode' using errcode = '22023';
  end if;

  v_resolved := case v_mode
    when 'automatic' then private.match_features_open_at(p_kickoff_at)
    when 'custom' then p_requested_at
    when 'now' then now()
  end;

  if v_mode = 'custom' and v_resolved is null then
    raise exception 'Custom availability opening date is required' using errcode = '22023';
  end if;
  if v_resolved is null or v_resolved >= p_kickoff_at then
    raise exception 'Availability must open before kickoff' using errcode = '22023';
  end if;

  return v_resolved;
end;
$function$;

revoke all on function private.resolve_match_availability_open_at(timestamptz, text, timestamptz)
  from public, anon, authenticated;
grant execute on function private.resolve_match_availability_open_at(timestamptz, text, timestamptz)
  to service_role;

-- V2 synchronization is deliberately backward-compatible. Callers that do not
-- provide a schedule keep the existing mode. Automatic schedules follow a moved
-- kickoff; custom/now schedules remain fixed. If a moved kickoff would make a
-- preserved custom timestamp invalid, we safely fall back to automatic rather
-- than leave the match in an impossible state.
create or replace function private.sync_match_sport_workflow_v2(
  p_match_id uuid,
  p_schedule_mode text default null,
  p_requested_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_config jsonb;
  v_default_squad_size integer := 14;
  v_existing_mode text;
  v_existing_opens_at timestamptz;
  v_mode text;
  v_opens_at timestamptz;
  v_computed_state public.sport_availability_state;
  v_saved_state public.sport_availability_state;
  v_opened_at timestamptz;
  v_eligible_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.season_id, match.kickoff_at, match.status
  into v_season_id, v_kickoff_at, v_match_status
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Only upcoming matches can be synchronized' using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select workflow.availability_schedule_mode, workflow.availability_opens_at
  into v_existing_mode, v_existing_opens_at
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  if p_schedule_mode is not null then
    v_mode := lower(btrim(p_schedule_mode));
    v_opens_at := private.resolve_match_availability_open_at(
      v_kickoff_at, v_mode, p_requested_at
    );
  elsif v_existing_mode is null then
    v_mode := 'automatic';
    v_opens_at := private.match_features_open_at(v_kickoff_at);
  elsif v_existing_mode = 'automatic' then
    v_mode := 'automatic';
    v_opens_at := private.match_features_open_at(v_kickoff_at);
  else
    v_mode := v_existing_mode;
    v_opens_at := v_existing_opens_at;
    if v_opens_at is null or v_opens_at >= v_kickoff_at then
      v_mode := 'automatic';
      v_opens_at := private.match_features_open_at(v_kickoff_at);
    end if;
  end if;

  select flag.config into v_config
  from private.app_feature_flags flag
  where flag.key = 'sports_management';

  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_default_squad_size := greatest(
      1,
      least(30, (v_config ->> 'usual_squad_size')::integer)
    );
  end if;

  v_computed_state := case
    when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
    when now() >= v_opens_at then 'open'::public.sport_availability_state
    else 'pending'::public.sport_availability_state
  end;

  insert into public.match_sport_workflows as workflow (
    match_id,
    availability_state,
    availability_opens_at,
    availability_opened_at,
    availability_schedule_mode,
    squad_size_limit,
    created_by,
    updated_by
  ) values (
    p_match_id,
    v_computed_state,
    v_opens_at,
    case when v_computed_state = 'open' then now() else null end,
    v_mode,
    v_default_squad_size,
    v_actor,
    v_actor
  )
  on conflict (match_id) do update
  set availability_opens_at = excluded.availability_opens_at,
      availability_schedule_mode = excluded.availability_schedule_mode,
      availability_state = v_computed_state,
      availability_opened_at = case
        when v_computed_state = 'open'
          then coalesce(workflow.availability_opened_at, now())
        else null
      end,
      updated_by = v_actor,
      updated_at = now()
  returning availability_state, availability_opened_at
  into v_saved_state, v_opened_at;

  update public.match_sport_participants participant
  set is_eligible = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.season_player_id is not null
    and participant.is_eligible
    and not exists (
      select 1
      from public.season_players player
      where player.id = participant.season_player_id
        and player.season_id = v_season_id
        and player.is_active
        and not player.is_coach
    );

  insert into public.match_sport_participants as participant (
    match_id,
    season_player_id,
    is_eligible
  )
  select p_match_id, player.id, not player.is_coach
  from public.season_players player
  where player.season_id = v_season_id
    and player.is_active
  on conflict (match_id, season_player_id) do update
  set is_eligible = excluded.is_eligible,
      updated_at = case
        when participant.is_eligible = excluded.is_eligible
          then participant.updated_at
        else now()
      end;

  select count(*)::integer into v_eligible_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return jsonb_build_object(
    'match_id', p_match_id,
    'availability_state', v_saved_state,
    'availability_opens_at', v_opens_at,
    'availability_opened_at', v_opened_at,
    'availability_schedule_mode', v_mode,
    'kickoff_at', v_kickoff_at,
    'squad_size_limit', (
      select workflow.squad_size_limit
      from public.match_sport_workflows workflow
      where workflow.match_id = p_match_id
    ),
    'eligible_participant_count', v_eligible_count
  );
end;
$function$;

revoke all on function private.sync_match_sport_workflow_v2(uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function private.sync_match_sport_workflow_v2(uuid, text, timestamptz)
  to service_role;

create or replace function private.sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select private.sync_match_sport_workflow_v2(p_match_id, null, null);
$function$;

create or replace function private.configure_match_sport_workflow_v2(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_schedule_mode text default null,
  p_requested_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_cutoff timestamptz;
  v_synced jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit is null or p_squad_size_limit < 1 or p_squad_size_limit > 30 then
    raise exception 'Squad size limit must be between 1 and 30' using errcode = '22023';
  end if;

  v_synced := private.sync_match_sport_workflow_v2(
    p_match_id, p_schedule_mode, p_requested_at
  );

  select match.season_id, match.kickoff_at
  into v_season_id, v_kickoff_at
  from public.matches match
  where match.id = p_match_id
  for update;

  v_cutoff := (
    (((v_kickoff_at at time zone 'Europe/Paris')::date - 1) + time '12:00')
    at time zone 'Europe/Paris'
  );

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      late_withdrawal_cutoff_at = v_cutoff,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  perform private.ensure_sport_waitlist(v_season_id, v_actor);
  perform private.recompute_match_convocations_internal(p_match_id, false);

  return v_synced || jsonb_build_object('squad_size_limit', p_squad_size_limit);
end;
$function$;

revoke all on function private.configure_match_sport_workflow_v2(uuid, integer, text, timestamptz)
  from public, anon, authenticated;
grant execute on function private.configure_match_sport_workflow_v2(uuid, integer, text, timestamptz)
  to service_role;

create or replace function private.configure_match_sport_workflow(
  p_match_id uuid,
  p_squad_size_limit integer
)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
  select private.configure_match_sport_workflow_v2(
    p_match_id, p_squad_size_limit, null, null
  );
$function$;

-- The notification trigger must use the actual configured opening instant,
-- not a recomputed J-6 instant. Date changes reset responses only after the
-- workflow had actually opened. Automatic schedules follow the new date;
-- explicit schedules remain fixed when valid.
create or replace function private.handle_match_notification_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_in_old_window boolean := false;
  v_date_changed boolean := false;
  v_old_opens_at timestamptz;
  v_mode text := 'automatic';
  v_new_opens_at timestamptz;
  v_new_state public.sport_availability_state;
begin
  select workflow.availability_opens_at, workflow.availability_schedule_mode
  into v_old_opens_at, v_mode
  from public.match_sport_workflows workflow
  where workflow.match_id = old.id;

  v_old_opens_at := coalesce(v_old_opens_at, private.match_features_open_at(old.kickoff_at));
  v_mode := coalesce(v_mode, 'automatic');

  if old.kickoff_at is not null then
    v_in_old_window := now() >= v_old_opens_at and now() < old.kickoff_at;
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
      if v_mode = 'automatic' then
        v_new_opens_at := private.match_features_open_at(new.kickoff_at);
      else
        v_new_opens_at := v_old_opens_at;
        if v_new_opens_at >= new.kickoff_at then
          v_mode := 'automatic';
          v_new_opens_at := private.match_features_open_at(new.kickoff_at);
        end if;
      end if;

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
          availability_schedule_mode = v_mode,
          availability_state = v_new_state,
          availability_opened_at = case
            when v_new_state = 'open' then coalesce(workflow.availability_opened_at, now())
            else null
          end,
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

-- Atomic creation RPC for championship/friendly matches. It intentionally
-- creates the match before configuring sports management so a custom future
-- schedule cannot briefly trigger the legacy J-6 workflow.
create or replace function public.admin_create_match_complete_v2(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null,
  p_availability_schedule_mode text default 'automatic',
  p_availability_opens_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
  v_squad_size_limit integer;
  v_workflow jsonb;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_squad_size_limit := private.resolve_match_squad_size_limit(p_squad_size_limit);

  v_match_id := public.create_match_with_odds(
    p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_win, p_draw, p_loss
  );

  v_workflow := private.configure_match_sport_workflow_v2(
    v_match_id,
    v_squad_size_limit,
    p_availability_schedule_mode,
    p_availability_opens_at
  );

  perform public.admin_set_match_address(
    v_match_id, p_address, p_remember_address_as_default
  );
  perform public.admin_set_match_type(v_match_id, p_match_type);
  perform public.admin_set_match_jersey(v_match_id, p_jersey_note);

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, metadata
  ) values (
    v_match_id,
    'set_availability_schedule',
    (select auth.uid()),
    jsonb_build_object(
      'mode', v_workflow ->> 'availability_schedule_mode',
      'availability_opens_at', v_workflow ->> 'availability_opens_at',
      'source', 'match_creation'
    )
  );

  -- Makes "now" truly immediate while retaining the cron as a resilient
  -- fallback. The notification event table makes this safe to call repeatedly.
  perform private.process_sport_availability_notifications(now());

  return v_match_id;
end;
$function$;

revoke all on function public.admin_create_match_complete_v2(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text, text, timestamptz
) from public, anon;
grant execute on function public.admin_create_match_complete_v2(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text, text, timestamptz
) to authenticated, service_role;

create or replace function public.create_internal_match_v2(
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text default null,
  p_availability_schedule_mode text default 'automatic',
  p_availability_opens_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
  v_workflow jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Season, date and time are required' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Match date is outside allowed bounds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.seasons season
    where season.id = p_season_id and season.status = 'open'
  ) then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;

  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, match_type, address, created_by
  ) values (
    p_season_id, null, p_match_date, p_match_time, 'domicile',
    90, 'a_venir', 'entre_nous', nullif(btrim(p_address), ''), (select auth.uid())
  ) returning id into v_match_id;

  v_workflow := private.configure_match_sport_workflow_v2(
    v_match_id, 30, p_availability_schedule_mode, p_availability_opens_at
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, metadata
  ) values (
    v_match_id,
    'set_availability_schedule',
    (select auth.uid()),
    jsonb_build_object(
      'mode', v_workflow ->> 'availability_schedule_mode',
      'availability_opens_at', v_workflow ->> 'availability_opens_at',
      'source', 'internal_match_creation'
    )
  );

  perform private.process_sport_availability_notifications(now());
  return v_match_id;
end;
$function$;

revoke all on function public.create_internal_match_v2(
  uuid, date, time without time zone, text, text, timestamptz
) from public, anon;
grant execute on function public.create_internal_match_v2(
  uuid, date, time without time zone, text, text, timestamptz
) to authenticated, service_role;

-- Explicit read RPC for clients that need the resolved opening instant without
-- exposing workflow write access.
create or replace function public.get_match_availability_schedule(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', workflow.match_id,
    'mode', workflow.availability_schedule_mode,
    'availability_opens_at', workflow.availability_opens_at,
    'availability_state', workflow.availability_state,
    'availability_opened_at', workflow.availability_opened_at
  ) into v_result
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id
    and private.can_read_sport_workflow(workflow.match_id);

  return v_result;
end;
$function$;

revoke all on function public.get_match_availability_schedule(uuid) from public, anon;
grant execute on function public.get_match_availability_schedule(uuid)
  to authenticated, service_role;
