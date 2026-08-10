-- P0: harden the internal notification pipeline.
-- All objects are schema-qualified already, so an empty search_path is safe.

alter function public.internal_push_config() set search_path = '';
alter function public.internal_push_dispatch(text, uuid) set search_path = '';
alter function public.internal_push_notify(text, uuid) set search_path = '';
alter function public.internal_push_prune(text[]) set search_path = '';
alter function public.push_closing_reminders() set search_path = '';
alter function public.push_on_match_insert() set search_path = '';
alter function public.push_on_match_result() set search_path = '';

revoke execute on function public.internal_push_config() from public, anon, authenticated;
revoke execute on function public.internal_push_dispatch(text, uuid) from public, anon, authenticated;
revoke execute on function public.internal_push_notify(text, uuid) from public, anon, authenticated;
revoke execute on function public.internal_push_prune(text[]) from public, anon, authenticated;
revoke execute on function public.push_closing_reminders() from public, anon, authenticated;
revoke execute on function public.push_on_match_insert() from public, anon, authenticated;
revoke execute on function public.push_on_match_result() from public, anon, authenticated;

grant execute on function public.internal_push_config() to service_role;
grant execute on function public.internal_push_dispatch(text, uuid) to service_role;
grant execute on function public.internal_push_notify(text, uuid) to service_role;
grant execute on function public.internal_push_prune(text[]) to service_role;
grant execute on function public.push_closing_reminders() to service_role;
