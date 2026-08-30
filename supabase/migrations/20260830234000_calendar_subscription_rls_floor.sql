drop policy if exists "active_authenticated_profile_only"
  on public.calendar_subscriptions;
create policy "active_authenticated_profile_only"
  on public.calendar_subscriptions
  as restrictive to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

drop policy if exists "active_authenticated_profile_only"
  on public.calendar_match_tombstones;
create policy "active_authenticated_profile_only"
  on public.calendar_match_tombstones
  as restrictive to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));
