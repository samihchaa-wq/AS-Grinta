-- P0: harden authenticated self-service RPCs.
-- Every function is bound to auth.uid(), requires an active profile and uses an
-- empty search_path to avoid object-shadowing attacks.

create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  result jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select to_jsonb(p)
  into result
  from public.profiles p
  where p.id = actor_id
    and p.status = 'active';

  if result is null then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return result;
end;
$$;

create or replace function public.complete_password_change()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set must_change_password = false,
      password_set = true,
      updated_at = now()
  where id = actor_id
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return true;
end;
$$;

create or replace function public.update_my_app_preferences(
  p_notify_prediction_open boolean,
  p_notify_prediction_reminders boolean,
  p_notify_match_reminders boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set notify_prediction_open =
        coalesce(p_notify_prediction_open, notify_prediction_open),
      notify_prediction_reminders =
        coalesce(p_notify_prediction_reminders, notify_prediction_reminders),
      notify_match_reminders =
        coalesce(p_notify_match_reminders, notify_match_reminders),
      updated_at = now()
  where id = actor_id
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return true;
end;
$$;

create or replace function public.register_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = actor_id
      and p.status = 'active'
  ) then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  if btrim(coalesce(p_endpoint, '')) = ''
     or btrim(coalesce(p_p256dh, '')) = ''
     or btrim(coalesce(p_auth, '')) = '' then
    raise exception 'Invalid push subscription' using errcode = '22023';
  end if;

  if length(p_endpoint) > 2048
     or length(p_p256dh) > 512
     or length(p_auth) > 512
     or length(coalesce(p_user_agent, '')) > 512 then
    raise exception 'Push subscription fields are too long' using errcode = '22001';
  end if;

  insert into public.push_subscriptions(
    profile_id,
    endpoint,
    p256dh,
    auth,
    user_agent
  )
  values (
    actor_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    p_user_agent
  )
  on conflict (endpoint) do update
  set profile_id = excluded.profile_id,
      p256dh = excluded.p256dh,
      auth = excluded.auth,
      user_agent = excluded.user_agent,
      updated_at = now();
end;
$$;

revoke execute on function public.get_my_profile() from public, anon;
revoke execute on function public.complete_password_change() from public, anon;
revoke execute on function public.update_my_app_preferences(boolean, boolean, boolean)
  from public, anon;
revoke execute on function public.register_push_subscription(text, text, text, text)
  from public, anon;

grant execute on function public.get_my_profile() to authenticated, service_role;
grant execute on function public.complete_password_change() to authenticated, service_role;
grant execute on function public.update_my_app_preferences(boolean, boolean, boolean)
  to authenticated, service_role;
grant execute on function public.register_push_subscription(text, text, text, text)
  to authenticated, service_role;
