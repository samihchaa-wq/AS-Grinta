create table public.match_participants (
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  is_goalkeeper_for_match boolean not null default false,
  selected_at timestamptz not null default now(),
  primary key (match_id, player_id)
);
