create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  avatar_path text,
  role public.app_role not null default 'pronostiqueur',
  is_goalkeeper boolean not null default false,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_open boolean not null default false,
  archived_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index seasons_one_open_idx
on public.seasons ((is_open))
where is_open = true;

create table public.season_players (
  season_id uuid not null references public.seasons(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (season_id, player_id)
);

create table public.opponents (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  opponent_id uuid not null references public.opponents(id) on delete restrict,
  kickoff_at timestamptz not null,
  is_home boolean not null,
  planned_duration_minutes integer not null check (planned_duration_minutes > 0),
  status public.match_status not null default 'a_venir',
  grinta_score integer check (grinta_score between 0 and 99),
  opponent_score integer check (opponent_score between 0 and 99),
  predictions_revealed_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index matches_one_per_day_idx
on public.matches (((kickoff_at at time zone 'Europe/Paris')::date));

create index matches_season_kickoff_idx
on public.matches(season_id, kickoff_at desc);
