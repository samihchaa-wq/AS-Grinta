create table if not exists public.profile_badge_seen (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  badge_code text not null,
  seen_at timestamptz not null default now(),
  primary key (profile_id, badge_code)
);

alter table public.profile_badge_seen enable row level security;

drop policy if exists profile_badge_seen_select_own on public.profile_badge_seen;
create policy profile_badge_seen_select_own on public.profile_badge_seen
  for select to authenticated
  using (profile_id = (select auth.uid()));

drop policy if exists profile_badge_seen_insert_own on public.profile_badge_seen;
create policy profile_badge_seen_insert_own on public.profile_badge_seen
  for insert to authenticated
  with check (profile_id = (select auth.uid()));

grant select, insert on public.profile_badge_seen to authenticated;

insert into public.profile_badge_seen (profile_id, badge_code)
select pb.profile_id, b.code
from public.profile_badges pb
join public.badges b on b.id = pb.badge_id
on conflict do nothing;;
