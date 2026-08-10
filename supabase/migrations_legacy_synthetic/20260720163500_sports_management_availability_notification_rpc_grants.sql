-- Public SECURITY INVOKER wrappers must be allowed to execute their private,
-- authorization-enforcing helpers. Anonymous roles remain excluded.

revoke execute on function private.send_sport_availability_reminder(uuid, uuid, text)
  from public, anon;
revoke execute on function private.get_sport_availability_reminder_summary(uuid)
  from public, anon;

grant execute on function private.send_sport_availability_reminder(uuid, uuid, text)
  to authenticated, service_role;
grant execute on function private.get_sport_availability_reminder_summary(uuid)
  to authenticated, service_role;

grant execute on function public.admin_send_match_availability_reminder(uuid, uuid, text)
  to service_role;
grant execute on function public.admin_get_match_availability_reminders(uuid)
  to service_role;
