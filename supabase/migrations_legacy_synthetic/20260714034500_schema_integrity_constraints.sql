-- Align database constraints with the application rules.

alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('pronostiqueur', 'admin', 'moderateur'));

alter table public.match_player_stats
  alter column season_player_id set not null;

alter table public.season_predictions
  alter column season_player_id set not null;

create unique index if not exists profiles_username_lower_uidx
  on public.profiles (lower(username))
  where username is not null;
