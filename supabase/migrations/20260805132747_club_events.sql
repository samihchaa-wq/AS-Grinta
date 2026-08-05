create table public.club_events (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  title text not null,
  starts_at timestamptz not null,
  location text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint club_events_title_length check (char_length(btrim(title)) between 1 and 120),
  constraint club_events_location_length check (char_length(btrim(location)) between 1 and 300)
);

create index club_events_season_starts_idx
  on public.club_events (season_id, starts_at desc);

alter table public.club_events enable row level security;

grant select, insert, update, delete on table public.club_events to authenticated;
grant select, insert, update, delete on table public.club_events to service_role;

create policy club_events_active_read
  on public.club_events
  for select
  to authenticated
  using ((select private.is_active_profile()));

create policy club_events_admin_insert
  on public.club_events
  for insert
  to authenticated
  with check (
    (select private.is_admin())
    and created_by = (select auth.uid())
  );

create policy club_events_admin_update
  on public.club_events
  for update
  to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy club_events_admin_delete
  on public.club_events
  for delete
  to authenticated
  using ((select private.is_admin()));
