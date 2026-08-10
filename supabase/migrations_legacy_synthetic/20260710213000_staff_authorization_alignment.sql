create or replace function public.is_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_match_staff();
$$;

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
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  if p_role is not null
     and p_role not in ('pronostiqueur','admin','moderateur','coach') then
    raise exception 'Invalid role';
  end if;

  if p_status is not null
     and p_status not in ('pending','active','archived') then
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

revoke all on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean) from public;
revoke all on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean) from anon;
grant execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean) to authenticated;
