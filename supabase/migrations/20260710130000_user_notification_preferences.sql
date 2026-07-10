alter table public.profiles
  add column if not exists notify_match_reminders boolean not null default true,
  add column if not exists notify_prediction_reminders boolean not null default true;

create or replace function public.update_my_app_preferences(
  p_notify_match_reminders boolean,
  p_notify_prediction_reminders boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.profiles
  set notify_match_reminders = coalesce(p_notify_match_reminders, notify_match_reminders),
      notify_prediction_reminders = coalesce(
        p_notify_prediction_reminders,
        notify_prediction_reminders
      ),
      updated_at = now()
  where id = auth.uid();

  return found;
end;
$$;

revoke all on function public.update_my_app_preferences(boolean, boolean)
  from public, anon;
grant execute on function public.update_my_app_preferences(boolean, boolean)
  to authenticated;
