begin;

alter table public.match_weather enable row level security;

drop policy if exists active_authenticated_profile_only on public.match_weather;
create policy active_authenticated_profile_only
on public.match_weather
as restrictive
for all
to authenticated
using ((select private.is_active_profile()))
with check ((select private.is_active_profile()));

commit;
