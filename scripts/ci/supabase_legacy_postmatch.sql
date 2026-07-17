-- CI-only compatibility shim for pre-migration post-match objects.
-- Copied into the disposable local migration chain immediately before the
-- first tracked migration that expects these objects to exist.

-- Later tracked migrations replace the status constraint using text values.
-- The hosted pre-migration schema had already moved away from app_role-style
-- enums, so reproduce that state only in this disposable local database.
alter table public.matches
  alter column status drop default,
  alter column status type text using status::text,
  alter column status set default 'a_venir';

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

create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  kickoff timestamptz;
  match_status text;
begin
  select (
    (m.match_date + coalesce(m.match_time, '00:00'::time))
      at time zone 'Europe/Paris'
  ), m.status
  into kickoff, match_status
  from public.matches m
  where m.id = new.match_id;

  if kickoff is null
     or match_status <> 'a_venir'
     or now() >= kickoff - interval '5 minutes' then
    raise exception 'Pronostic fermé';
  end if;

  if auth.uid() is not null and pg_trigger_depth() <= 1 then
    new.profile_id := auth.uid();
  end if;

  return new;
end;
$$;
