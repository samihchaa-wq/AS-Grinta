-- Tables internes nécessaires pour exercer localement la migration de sécurité.
-- Aucun contenu de production n'est copié.

create table if not exists public.push_delivery_log (
  id bigint primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  kind text not null check (
    kind in ('new_match', 'closing_soon', 'result_validated')
  ),
  profile_id uuid references public.profiles(id) on delete set null,
  endpoint_host text,
  success boolean not null,
  status_code integer,
  error_message text,
  created_at timestamptz not null default now()
);

create table if not exists public.season_awards (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  award_type text not null,
  created_at timestamptz not null default now(),
  unique (season_id, profile_id, award_type)
);

alter table public.push_delivery_log enable row level security;
alter table public.season_awards enable row level security;
