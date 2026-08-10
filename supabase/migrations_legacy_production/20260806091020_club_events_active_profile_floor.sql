drop policy if exists active_authenticated_profile_only
  on public.club_events;
create policy active_authenticated_profile_only
  on public.club_events
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));
;
