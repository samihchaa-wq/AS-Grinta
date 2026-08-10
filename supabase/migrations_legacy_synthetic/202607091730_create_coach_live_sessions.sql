begin;

create table if not exists public.coach_match_sessions (
  match_id uuid primary key references public.matches(id) on delete cascade,
  formation_code text not null default '4-3-3',
  lineup jsonb not null default '{}'::jsonb,
  bench jsonb not null default '[]'::jsonb,
  score_as_grinta integer not null default 0 check (score_as_grinta >= 0),
  score_adverse integer not null default 0 check (score_adverse >= 0),
  elapsed_seconds integer not null default 0 check (elapsed_seconds >= 0),
  planned_duration_minutes integer not null default 90 check (planned_duration_minutes between 1 and 200),
  is_running boolean not null default false,
  started_at timestamptz,
  paused_at timestamptz,
  ended_at timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.coach_match_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  event_type text not null check (event_type in ('goal_us', 'goal_them', 'substitution')),
  minute integer not null check (minute >= 0),
  scorer_profile_id uuid references public.profiles(id) on delete set null,
  assist_profile_id uuid references public.profiles(id) on delete set null,
  player_in_profile_id uuid references public.profiles(id) on delete set null,
  player_out_profile_id uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists coach_match_events_match_id_created_at_idx
  on public.coach_match_events(match_id, created_at);

alter table public.coach_match_sessions enable row level security;
alter table public.coach_match_events enable row level security;

create or replace function public.is_match_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role::text, '')) in ('admin', 'moderateur', 'moderator', 'coach')
      and lower(coalesce(p.status::text, 'active')) = 'active'
  );
$$;

revoke all on function public.is_match_staff() from public;
grant execute on function public.is_match_staff() to authenticated;

DROP POLICY IF EXISTS coach_sessions_read_authenticated ON public.coach_match_sessions;
CREATE POLICY coach_sessions_read_authenticated
ON public.coach_match_sessions
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS coach_sessions_write_staff ON public.coach_match_sessions;
CREATE POLICY coach_sessions_write_staff
ON public.coach_match_sessions
FOR ALL
TO authenticated
USING (public.is_match_staff())
WITH CHECK (public.is_match_staff());

DROP POLICY IF EXISTS coach_events_read_authenticated ON public.coach_match_events;
CREATE POLICY coach_events_read_authenticated
ON public.coach_match_events
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS coach_events_write_staff ON public.coach_match_events;
CREATE POLICY coach_events_write_staff
ON public.coach_match_events
FOR ALL
TO authenticated
USING (public.is_match_staff())
WITH CHECK (public.is_match_staff());

alter table public.coach_match_sessions replica identity full;
alter table public.coach_match_events replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.coach_match_sessions;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.coach_match_events;
    exception when duplicate_object then null;
    end;
  end if;
end $$;

commit;
