revoke update on public.profiles from authenticated;
grant update(first_name,last_name,photo_url,updated_at)
on public.profiles to authenticated;

create or replace function public.moderator_update_profile_admin_fields(
  p_profile_id uuid,
  p_role text,
  p_status text,
  p_is_goalkeeper boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required';
  end if;

  if p_role is not null
     and p_role not in ('pronostiqueur','admin','moderateur') then
    raise exception 'Invalid role';
  end if;

  if p_status is not null
     and p_status not in ('active','archived') then
    raise exception 'Invalid status';
  end if;

  update public.profiles
  set role = coalesce(p_role, role),
      status = coalesce(p_status, status),
      is_goalkeeper = coalesce(p_is_goalkeeper, is_goalkeeper),
      updated_at = now()
  where id = p_profile_id;

  return found;
end;
$$;

revoke execute on function public.moderator_update_profile_admin_fields(
  uuid,text,text,boolean
) from public;
revoke execute on function public.moderator_update_profile_admin_fields(
  uuid,text,text,boolean
) from anon;
grant execute on function public.moderator_update_profile_admin_fields(
  uuid,text,text,boolean
) to authenticated;
