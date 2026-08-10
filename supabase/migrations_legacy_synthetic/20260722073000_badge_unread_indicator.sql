-- Pastille « nouveau badge » : mémorise jusqu'à quelle date chaque membre a
-- consulté son armoire. Les anciennes attributions sont initialisées comme lues
-- par l'application lors de la première consultation de cet état.

create table if not exists public.badge_inbox_state (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  seen_through timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.badge_inbox_state enable row level security;

drop policy if exists badge_inbox_state_select_own
  on public.badge_inbox_state;
create policy badge_inbox_state_select_own
  on public.badge_inbox_state
  for select
  to authenticated
  using ((select auth.uid()) = profile_id);

drop policy if exists badge_inbox_state_insert_own
  on public.badge_inbox_state;
create policy badge_inbox_state_insert_own
  on public.badge_inbox_state
  for insert
  to authenticated
  with check ((select auth.uid()) = profile_id);

drop policy if exists badge_inbox_state_update_own
  on public.badge_inbox_state;
create policy badge_inbox_state_update_own
  on public.badge_inbox_state
  for update
  to authenticated
  using ((select auth.uid()) = profile_id)
  with check ((select auth.uid()) = profile_id);

grant select, insert, update on public.badge_inbox_state to authenticated;
revoke all on public.badge_inbox_state from anon;
