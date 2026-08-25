-- Match meeting time shown in the practical match information.
-- NULL is intentional and means "automatic: 30 minutes before kickoff".
-- Only explicit/custom meeting instants are persisted.

alter table public.matches
  add column if not exists meeting_at timestamptz;

comment on column public.matches.meeting_at is
  'Optional explicit meeting instant. NULL means 30 minutes before kickoff.';

-- Keep a custom meeting time coherent when an older client or another server
-- path reschedules a match without explicitly sending meeting_at. The local
-- clock time follows a changed match date; if a changed kickoff would make it
-- invalid, the value falls back to NULL (automatic H-30).
create or replace function private.normalize_match_meeting_at()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_local_time time without time zone;
  v_shifted timestamptz;
begin
  if new.kickoff_at is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.kickoff_at is distinct from old.kickoff_at
     and new.meeting_at is not distinct from old.meeting_at
     and old.meeting_at is not null then
    v_local_time := (old.meeting_at at time zone 'Europe/Paris')::time;
    v_shifted := (
      ((new.kickoff_at at time zone 'Europe/Paris')::date + v_local_time)
      at time zone 'Europe/Paris'
    );
    new.meeting_at := case
      when v_shifted < new.kickoff_at then v_shifted
      else null
    end;
  end if;

  if new.meeting_at is not null and new.meeting_at >= new.kickoff_at then
    raise exception 'Meeting time must be before kickoff' using errcode = '22023';
  end if;

  return new;
end;
$function$;

revoke all on function private.normalize_match_meeting_at()
  from public, anon, authenticated;
grant execute on function private.normalize_match_meeting_at()
  to service_role;

drop trigger if exists trg_validate_match_meeting_at on public.matches;
create trigger trg_validate_match_meeting_at
before insert or update of match_date, match_time, kickoff_at, meeting_at
on public.matches
for each row
execute function private.normalize_match_meeting_at();

create or replace function private.set_match_meeting_at(
  p_match_id uuid,
  p_meeting_at timestamptz
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_kickoff_at timestamptz;
begin
  select match.kickoff_at
  into v_kickoff_at
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;
  if p_meeting_at is not null and p_meeting_at >= v_kickoff_at then
    raise exception 'Meeting time must be before kickoff' using errcode = '22023';
  end if;

  update public.matches
  set meeting_at = p_meeting_at,
      updated_at = now()
  where id = p_match_id;
end;
$function$;

revoke all on function private.set_match_meeting_at(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function private.set_match_meeting_at(uuid, timestamptz)
  to service_role;

-- New atomic creation boundary. V2 stays available to already deployed clients.
create or replace function public.admin_create_match_complete_v3(
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
  p_availability_opens_at timestamptz default null,
  p_meeting_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_match_id := public.admin_create_match_complete_v2(
    p_season_id,
    p_opponent_id,
    p_match_date,
    p_match_time,
    p_location,
    p_win,
    p_draw,
    p_loss,
    p_squad_size_limit,
    p_address,
    p_remember_address_as_default,
    p_match_type,
    p_jersey_note,
    p_availability_schedule_mode,
    p_availability_opens_at
  );

  perform private.set_match_meeting_at(v_match_id, p_meeting_at);
  return v_match_id;
end;
$function$;

revoke all on function public.admin_create_match_complete_v3(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text, text, timestamptz, timestamptz
) from public, anon;
grant execute on function public.admin_create_match_complete_v3(
  uuid, uuid, date, time without time zone, text, numeric, numeric, numeric,
  integer, text, boolean, text, text, text, timestamptz, timestamptz
) to authenticated, service_role;

create or replace function public.create_internal_match_v3(
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text default null,
  p_availability_schedule_mode text default 'automatic',
  p_availability_opens_at timestamptz default null,
  p_meeting_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_match_id := public.create_internal_match_v2(
    p_season_id,
    p_match_date,
    p_match_time,
    p_address,
    p_availability_schedule_mode,
    p_availability_opens_at
  );

  perform private.set_match_meeting_at(v_match_id, p_meeting_at);
  return v_match_id;
end;
$function$;

revoke all on function public.create_internal_match_v3(
  uuid, date, time without time zone, text, text, timestamptz, timestamptz
) from public, anon;
grant execute on function public.create_internal_match_v3(
  uuid, date, time without time zone, text, text, timestamptz, timestamptz
) to authenticated, service_role;

-- Atomic update boundaries carrying the meeting value. Legacy functions remain
-- untouched for compatibility and are called inside the same transaction.
create or replace function public.admin_update_match_complete_v2(
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
  p_meeting_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_updated boolean;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_updated := public.admin_update_match_complete(
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
    p_jersey_note
  );

  if v_updated is distinct from true then
    return false;
  end if;

  perform private.set_match_meeting_at(p_match_id, p_meeting_at);
  return true;
end;
$function$;

revoke all on function public.admin_update_match_complete_v2(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, timestamptz, integer, text, boolean, text, text,
  timestamptz
) from public, anon;
grant execute on function public.admin_update_match_complete_v2(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, timestamptz, integer, text, boolean, text, text,
  timestamptz
) to authenticated, service_role;

create or replace function public.update_internal_match_v2(
  p_match_id uuid,
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text,
  p_expected_updated_at timestamptz,
  p_meeting_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_updated boolean;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_updated := public.update_internal_match(
    p_match_id,
    p_season_id,
    p_match_date,
    p_match_time,
    p_address,
    p_expected_updated_at
  );

  if v_updated is distinct from true then
    return false;
  end if;

  perform private.set_match_meeting_at(p_match_id, p_meeting_at);
  return true;
end;
$function$;

revoke all on function public.update_internal_match_v2(
  uuid, uuid, date, time without time zone, text, timestamptz, timestamptz
) from public, anon;
grant execute on function public.update_internal_match_v2(
  uuid, uuid, date, time without time zone, text, timestamptz, timestamptz
) to authenticated, service_role;
