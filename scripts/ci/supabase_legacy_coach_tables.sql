-- CI-only compatibility shim applied after the historical post-match cleanup.
-- One tracked migration drops these tables and the next migration immediately
-- references them. Recreate only the table shapes required by that later step
-- inside the disposable local migration chain.

create table if not exists public.coach_match_sessions (
  match_id uuid primary key references public.matches(id) on delete cascade,
  formation_code text not null default '4-3-3',
  lineup jsonb not null default '{}'::jsonb,
  bench jsonb not null default '[]'::jsonb,
  score_as_grinta integer not null default 0 check (score_as_grinta >= 0),
  score_adverse integer not null default 0 check (score_adverse >= 0),
  elapsed_seconds integer not null default 0 check (elapsed_seconds >= 0),
  planned_duration_minutes integer not null default 90
    check (planned_duration_minutes between 1 and 200),
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
  event_type text not null
    check (event_type in ('goal_us', 'goal_them', 'substitution')),
  minute integer not null check (minute >= 0),
  scorer_profile_id uuid references public.profiles(id) on delete set null,
  assist_profile_id uuid references public.profiles(id) on delete set null,
  player_in_profile_id uuid references public.profiles(id) on delete set null,
  player_out_profile_id uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
