drop trigger if exists trg_guard_single_match_date on public.matches;
drop function if exists public.guard_single_match_date();

create unique index if not exists matches_match_date_uidx
  on public.matches (match_date);
