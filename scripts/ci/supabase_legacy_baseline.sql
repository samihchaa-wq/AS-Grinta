-- CI-only compatibility baseline.
--
-- This file is never placed in supabase/migrations in the repository and must
-- never be applied to a hosted project. The local runner copies it into its
-- disposable workspace because the earliest committed migrations assume these
-- objects already existed from pre-migration Dashboard work.

alter table public.profiles
  add column if not exists email text,
  add column if not exists photo_url text,
  add column if not exists status text not null default 'active';

-- Historical Dashboard state used a text role column, while the first tracked
-- migration recreated it with the temporary app_role enum. Later migrations
-- consistently treat role as text, so reproduce that pre-migration state only
-- in the disposable CI database.
alter table public.profiles
  alter column role drop default,
  alter column role type text using role::text,
  alter column role set default 'pronostiqueur';

create unique index if not exists profiles_email_ci_legacy_uidx
  on public.profiles (email)
  where email is not null and email <> '';

alter table public.seasons
  add column if not exists status text not null default 'open';

alter table public.season_players
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists profile_id uuid references public.profiles(id) on delete cascade,
  add column if not exists is_goalkeeper_snapshot boolean not null default false;

create unique index if not exists season_players_id_ci_legacy_uidx
  on public.season_players(id);

create unique index if not exists season_players_season_profile_ci_legacy_uidx
  on public.season_players(season_id, profile_id);

alter table public.matches
  add column if not exists match_date date,
  add column if not exists match_time time without time zone,
  add column if not exists score_as_grinta integer,
  add column if not exists score_adverse integer,
  add column if not exists created_by uuid references public.profiles(id),
  add column if not exists result_validated_at timestamptz;

alter table public.match_participants
  add column if not exists profile_id uuid references public.profiles(id) on delete restrict;

create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.matches(id) on delete cascade,
  status text not null default 'not_started',
  elapsed_seconds integer not null default 0,
  clock_started_at timestamptz,
  controller_profile_id uuid references public.profiles(id) on delete set null,
  controller_session_id text,
  controller_disconnected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.live_positions (
  live_session_id uuid not null references public.live_sessions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  slot_code text,
  updated_at timestamptz not null default now(),
  primary key (live_session_id, profile_id)
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  team text not null,
  goal_type text not null,
  scorer_profile_id uuid references public.profiles(id) on delete set null,
  assist_profile_id uuid references public.profiles(id) on delete set null,
  assist_type text,
  minute integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.substitutions (
  id uuid primary key default gen_random_uuid(),
  live_session_id uuid not null references public.live_sessions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  minute integer not null,
  created_at timestamptz not null default now()
);

create table if not exists public.match_motm (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.match_predictions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  predicted_score_as_grinta integer not null default 0,
  predicted_score_adverse integer not null default 0,
  is_filled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (match_id, profile_id)
);

create table if not exists public.season_predictions (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  predictor_profile_id uuid not null references public.profiles(id) on delete cascade,
  player_profile_id uuid references public.profiles(id) on delete cascade,
  category text not null,
  predicted_value_20 integer not null default 0,
  is_filled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, predictor_profile_id, player_profile_id, category)
);

create table if not exists public.match_odds (
  match_id uuid primary key references public.matches(id) on delete cascade,
  odds_victoire_as_grinta numeric not null,
  odds_nul numeric not null,
  odds_victoire_adverse numeric not null,
  computed_at timestamptz not null default now()
);

create table if not exists public.formations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slots jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

-- An early hardening migration revokes this legacy trigger helper before a
-- later migration recreates it. The pre-migration project contained it.
create or replace function public.seed_predictions_for_active_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return new;
end;
$$;
