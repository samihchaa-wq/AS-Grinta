-- Replay-only reconstruction of the database objects and column transitions
-- that already existed in production before migration history was recorded.
--
-- This file is NOT deployed to production. The 427 SQL files in
-- supabase/migrations remain the exact production-recorded history.

alter table public.profiles
  add column if not exists status text not null default 'active',
  add column if not exists photo_url text;

alter table public.seasons
  add column if not exists status text not null default 'open';

-- The recorded history created these tables with player_id, while the next
-- recorded migrations already use profile_id. Preserve that missing rename.
alter table public.season_players
  rename column player_id to profile_id;
alter table public.season_players
  drop constraint if exists season_players_pkey;
alter table public.season_players
  add column if not exists id uuid not null default gen_random_uuid(),
  add column if not exists is_goalkeeper_snapshot boolean not null default false;
alter table public.season_players
  add primary key (id);
create unique index if not exists season_players_season_profile_uidx
  on public.season_players(season_id, profile_id);

alter table public.match_participants
  rename column player_id to profile_id;

-- The design-v1 migrations immediately use these names although no recorded
-- migration creates them. On a real database they were already present.
alter table public.matches
  add column if not exists match_date date,
  add column if not exists match_time time without time zone,
  add column if not exists location text,
  add column if not exists score_as_grinta integer,
  add column if not exists score_adverse integer,
  add column if not exists created_by uuid references public.profiles(id) on delete restrict;

update public.matches
set match_date = coalesce(match_date, (kickoff_at at time zone 'Europe/Paris')::date),
    match_time = coalesce(match_time, (kickoff_at at time zone 'Europe/Paris')::time),
    location = coalesce(location, case when is_home then 'domicile' else 'exterieur' end),
    score_as_grinta = coalesce(score_as_grinta, grinta_score),
    score_adverse = coalesce(score_adverse, opponent_score);

create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.matches(id) on delete cascade,
  status text not null default 'not_started',
  formation text,
  controller_profile_id uuid references public.profiles(id) on delete set null,
  controller_session_id text,
  controller_disconnected_at timestamptz,
  elapsed_seconds integer not null default 0,
  clock_started_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.live_positions (
  id uuid primary key default gen_random_uuid(),
  live_session_id uuid not null references public.live_sessions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  slot_code text,
  x_pct numeric,
  y_pct numeric,
  is_on_pitch boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (live_session_id, profile_id)
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  team text not null,
  minute integer not null default 0,
  goal_type text,
  scorer_profile_id uuid references public.profiles(id) on delete set null,
  assist_type text,
  assist_profile_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.substitutions (
  id uuid primary key default gen_random_uuid(),
  live_session_id uuid not null references public.live_sessions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  minute integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.match_motm (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.match_odds (
  match_id uuid primary key references public.matches(id) on delete cascade,
  odds_victoire_as_grinta numeric not null,
  odds_nul numeric not null,
  odds_victoire_adverse numeric not null,
  computed_at timestamptz not null default now()
);

create table if not exists public.match_predictions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  predicted_score_as_grinta integer not null default 0,
  predicted_score_adverse integer not null default 0,
  is_filled boolean not null default false,
  submitted_at timestamptz,
  points_awarded integer not null default 0,
  details jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (match_id, profile_id)
);

create table if not exists public.season_predictions (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  predictor_profile_id uuid not null references public.profiles(id) on delete cascade,
  player_profile_id uuid not null references public.profiles(id) on delete cascade,
  category text not null,
  predicted_value_20 integer not null default 0,
  is_filled boolean not null default false,
  submitted_at timestamptz,
  points_awarded integer not null default 0,
  is_correct boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, predictor_profile_id, player_profile_id, category)
);

create table if not exists public.formations (
  code text primary key,
  name text,
  created_at timestamptz not null default now()
);

insert into public.formations(code, name) values
  ('4-4-2', '4-4-2'),
  ('4-3-3', '4-3-3'),
  ('4-2-3-1', '4-2-3-1'),
  ('3-5-2', '3-5-2')
on conflict (code) do nothing;
