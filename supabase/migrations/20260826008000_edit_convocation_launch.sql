-- Allow administrators to change the availability/convocation opening schedule
-- while editing an upcoming match. Existing V2 update RPCs stay available for
-- already deployed clients; V3 adds the optional schedule fields and keeps the
-- whole match edit atomic.

create or replace function public.admin_update_match_complete_v3(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric,
  p_expected_updated_at timestamptz,
  p_squad_size_limit integer default null,
  p_address text default null,
  p_remember_address_as_default boolean default false,
  p_match_type text default 'championnat',
  p_jersey_note text default null,
  p_meeting_at timestamptz default null,
  p_availability_schedule_mode text default null,
  p_availability_opens_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_updated boolean;
  v_schedule jsonb;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_updated := public.admin_update_match_complete_v2(
    p_match_id,
    p_season_id,
    p_opponent_id,
    p_match_date,
    p_match_time,
    p_location,
    p_status,
    p_win,
    p_draw,
    p_loss,
    p_expected_updated_at,
    p_squad_size_limit,
    p_address,
    p_remember_address_as_default,
    p_match_type,
    p_jersey_note,
    p_meeting_at
  );

  if v_updated is distinct from true then
    return false;
  end if;

  -- NULL means the admin did not touch this field. This is intentional: it
  -- preserves the exact current schedule, especially an already-used `now`
  -- instant, while the existing workflow logic still follows kickoff changes.
  if p_availability_schedule_mode is not null then
    v_schedule := private.sync_match_sport_workflow_v2(
      p_match_id,
      p_availability_schedule_mode,
      p_availability_opens_at
    );

    insert into private.sport_admin_audit_log(
      match_id, action, actor_profile_id, metadata
    ) values (
      p_match_id,
      'set_availability_schedule',
      (select auth.uid()),
      jsonb_build_object(
        'mode', v_schedule ->> 'availability_schedule_mode',
        'availability_opens_at', v_schedule ->> 'availability_opens_at',
        'source', 'match_edit'
      )
    );

    -- Makes an edit to `now` effective immediately while retaining the cron as
    -- the resilient fallback. Notification delivery is idempotent server-side.
    perform private.process_sport_availability_notifications(now());
  end if;

  return true;
end;
$function$;

revoke all on function public.admin_update_match_complete_v3(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, timestamptz, integer, text, boolean, text, text,
  timestamptz, text, timestamptz
) from public, anon;
grant execute on function public.admin_update_match_complete_v3(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, timestamptz, integer, text, boolean, text, text,
  timestamptz, text, timestamptz
) to authenticated, service_role;

create or replace function public.update_internal_match_v3(
  p_match_id uuid,
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text,
  p_expected_updated_at timestamptz,
  p_meeting_at timestamptz default null,
  p_availability_schedule_mode text default null,
  p_availability_opens_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_updated boolean;
  v_schedule jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_updated := public.update_internal_match_v2(
    p_match_id,
    p_season_id,
    p_match_date,
    p_match_time,
    p_address,
    p_expected_updated_at,
    p_meeting_at
  );

  if v_updated is distinct from true then
    return false;
  end if;

  if p_availability_schedule_mode is not null then
    v_schedule := private.sync_match_sport_workflow_v2(
      p_match_id,
      p_availability_schedule_mode,
      p_availability_opens_at
    );

    insert into private.sport_admin_audit_log(
      match_id, action, actor_profile_id, metadata
    ) values (
      p_match_id,
      'set_availability_schedule',
      (select auth.uid()),
      jsonb_build_object(
        'mode', v_schedule ->> 'availability_schedule_mode',
        'availability_opens_at', v_schedule ->> 'availability_opens_at',
        'source', 'internal_match_edit'
      )
    );

    perform private.process_sport_availability_notifications(now());
  end if;

  return true;
end;
$function$;

revoke all on function public.update_internal_match_v3(
  uuid, uuid, date, time without time zone, text, timestamptz,
  timestamptz, text, timestamptz
) from public, anon;
grant execute on function public.update_internal_match_v3(
  uuid, uuid, date, time without time zone, text, timestamptz,
  timestamptz, text, timestamptz
) to authenticated, service_role;
