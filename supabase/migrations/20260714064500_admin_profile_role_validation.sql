create or replace function public.moderator_update_profile_admin_fields(
  p_profile_id uuid,
  p_role text,
  p_status text,
  p_is_goalkeeper boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  current_row public.profiles%rowtype;
  resulting_role text;
  resulting_status text;
  active_admins integer;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;

  if p_profile_id = '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Protected technical account' using errcode = '42501';
  end if;

  select *
  into current_row
  from public.profiles
  where id = p_profile_id
  for update;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  if p_role is not null and p_role not in ('pronostiqueur', 'admin') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;

  if p_status is not null and p_status not in ('pending', 'active', 'archived') then
    raise exception 'Invalid status' using errcode = '22023';
  end if;

  if p_profile_id = actor_id and (p_role is not null or p_status is not null) then
    raise exception 'An administrator cannot change their own role or status here'
      using errcode = '42501';
  end if;

  resulting_role := coalesce(p_role, current_row.role::text);
  resulting_status := coalesce(p_status, current_row.status::text);

  if current_row.role::text = 'admin'
     and current_row.status::text = 'active'
     and (resulting_role <> 'admin' or resulting_status <> 'active') then
    select count(*)
    into active_admins
    from public.profiles
    where role = 'admin' and status = 'active';

    if active_admins <= 1 then
      raise exception 'The last active administrator cannot be removed or archived'
        using errcode = '23514';
    end if;
  end if;

  update public.profiles
  set role = resulting_role,
      status = resulting_status,
      is_goalkeeper = coalesce(p_is_goalkeeper, is_goalkeeper),
      updated_at = now()
  where id = p_profile_id;

  return true;
end;
$$;

revoke execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean)
  from public, anon;
grant execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean)
  to authenticated, service_role;
