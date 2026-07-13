-- Reduce notification table privileges to the minimum used by the app.

revoke all on table public.push_notification_log
  from public, anon, authenticated;

revoke all on table public.push_subscriptions
  from public, anon, authenticated;

grant delete on table public.push_subscriptions
  to authenticated;

-- Trusted server-side components retain full access.
grant select, insert, update, delete on table public.push_notification_log
  to service_role;
grant select, insert, update, delete on table public.push_subscriptions
  to service_role;
