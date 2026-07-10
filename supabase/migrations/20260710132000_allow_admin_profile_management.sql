create or replace function public.moderator_update_profile_admin_fields(
  p_profile_id uuid,
  p_role text,
  p_status text,
  p_is_goalkeeper boolean
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  current_row public.profiles%rowtype;
  role_changes boolean;
  status_changes boolean;
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  select * into current_row
  from public.profiles
  where id = p_profile_id
  for update;

  if not found then return false; end if;

  if p_role is not null
     and p_role not in ('pronostiqueur','admin','moderateur') then
    raise exception 'Invalid role';
  end if;

  if p_status is not null
     and p_status not in ('pending','active','archived') then
    raise exception 'Invalid status';
  end if;

  role_changes := p_role is not null and p_role is distinct from current_row.role::text;
  status_changes := p_status is not null and p_status is distinct from current_row.status::text;

  if (role_changes or status_changes)
     and not (public.is_admin() or public.is_exact_moderator()) then
    raise exception 'Admin or moderator role required';
  end if;

  update public.profiles
  set role = coalesce(p_role, role),
      status = coalesce(p_status, status),
      is_goalkeeper = coalesce(p_is_goalkeeper, is_goalkeeper),
      updated_at = now()
  where id = p_profile_id;

  return true;
end;
$$;
