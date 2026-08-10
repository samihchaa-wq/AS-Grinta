create or replace function public.admin_require_password_change(p_profile_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and status = 'active'
  ) then
    raise exception 'Active admin role required';
  end if;

  if p_profile_id = auth.uid() then
    raise exception 'Use your profile to change your own password';
  end if;

  if p_profile_id = '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Protected technical account';
  end if;

  update public.profiles
  set must_change_password = true,
      password_set = true,
      updated_at = now()
  where id = p_profile_id
    and status = 'active';

  if not found then
    raise exception 'Active profile not found';
  end if;

  return true;
end;
$function$;

create or replace function public.complete_password_change()
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.profiles
  set must_change_password = false,
      password_set = true,
      updated_at = now()
  where id = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'Active profile not found';
  end if;

  return true;
end;
$function$;

revoke all on function public.admin_require_password_change(uuid) from public, anon;
revoke all on function public.complete_password_change() from public, anon;
grant execute on function public.admin_require_password_change(uuid) to authenticated;
grant execute on function public.complete_password_change() to authenticated;
