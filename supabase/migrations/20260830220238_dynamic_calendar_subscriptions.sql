create table if not exists public.calendar_subscriptions (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

alter table public.calendar_subscriptions enable row level security;
revoke all on table public.calendar_subscriptions from anon, authenticated;

create or replace function public.get_or_create_calendar_subscription_token()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_id uuid := auth.uid();
  v_token uuid;
begin
  if v_profile_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_profile_id
      and p.status = 'active'
  ) then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  insert into public.calendar_subscriptions(profile_id)
  values (v_profile_id)
  on conflict (profile_id) do nothing;

  select cs.token
  into v_token
  from public.calendar_subscriptions cs
  where cs.profile_id = v_profile_id;

  return v_token;
end;
$$;

revoke all on function public.get_or_create_calendar_subscription_token() from public, anon;
grant execute on function public.get_or_create_calendar_subscription_token() to authenticated;

create table if not exists public.calendar_match_tombstones (
  match_id uuid primary key,
  season_id uuid not null references public.seasons(id) on delete cascade,
  deleted_at timestamptz not null default now(),
  kickoff_at timestamptz,
  planned_duration_minutes integer not null default 90,
  location text,
  opponent_name text,
  address text,
  match_type text,
  championship_round integer
);

alter table public.calendar_match_tombstones enable row level security;
revoke all on table public.calendar_match_tombstones from anon, authenticated;

create or replace function private.capture_deleted_match_for_calendar()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_opponent_name text;
begin
  if old.opponent_id is not null then
    select o.name into v_opponent_name
    from public.opponents o
    where o.id = old.opponent_id;
  end if;

  insert into public.calendar_match_tombstones (
    match_id,
    season_id,
    deleted_at,
    kickoff_at,
    planned_duration_minutes,
    location,
    opponent_name,
    address,
    match_type,
    championship_round
  ) values (
    old.id,
    old.season_id,
    now(),
    old.kickoff_at,
    coalesce(old.planned_duration_minutes, 90),
    old.location,
    v_opponent_name,
    old.address,
    old.match_type,
    old.championship_round
  )
  on conflict (match_id) do update set
    season_id = excluded.season_id,
    deleted_at = excluded.deleted_at,
    kickoff_at = excluded.kickoff_at,
    planned_duration_minutes = excluded.planned_duration_minutes,
    location = excluded.location,
    opponent_name = excluded.opponent_name,
    address = excluded.address,
    match_type = excluded.match_type,
    championship_round = excluded.championship_round;

  return old;
end;
$$;

revoke all on function private.capture_deleted_match_for_calendar() from public, anon, authenticated;

drop trigger if exists trg_capture_deleted_match_for_calendar on public.matches;
create trigger trg_capture_deleted_match_for_calendar
before delete on public.matches
for each row execute function private.capture_deleted_match_for_calendar();

create index if not exists calendar_match_tombstones_season_deleted_idx
  on public.calendar_match_tombstones(season_id, deleted_at desc);
