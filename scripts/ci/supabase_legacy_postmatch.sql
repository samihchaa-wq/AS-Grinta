-- CI-only compatibility shim for pre-migration post-match tables.
-- Copied into the disposable local migration chain immediately before the
-- first tracked migration that expects match_player_stats to exist.

create table if not exists public.match_player_stats (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  present boolean not null default true,
  goals integer not null default 0,
  assists integer not null default 0,
  penalty_faults integer not null default 0,
  clean_sheet boolean not null default false,
  created_at timestamptz not null default now()
);
