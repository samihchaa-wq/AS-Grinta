drop policy if exists push_notification_log_no_client_access
  on public.push_notification_log;

create policy push_notification_log_no_client_access
  on public.push_notification_log
  as restrictive
  for all
  to authenticated, anon
  using (false)
  with check (false);;
