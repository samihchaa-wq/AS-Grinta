create or replace function public.is_exact_moderator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role::text, '')) in ('moderateur', 'moderator')
      and lower(coalesce(p.status::text, 'active')) = 'active'
  );
$$;

revoke all on function public.is_exact_moderator() from public, anon;
grant execute on function public.is_exact_moderator() to authenticated;

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

  if not found then
    return false;
  end if;

  if p_role is not null
     and p_role not in ('pronostiqueur','admin','moderateur','coach') then
    raise exception 'Invalid role';
  end if;

  if p_status is not null
     and p_status not in ('pending','active','archived') then
    raise exception 'Invalid status';
  end if;

  role_changes := p_role is not null and p_role is distinct from current_row.role::text;
  status_changes := p_status is not null and p_status is distinct from current_row.status::text;

  if (role_changes or status_changes) and not public.is_exact_moderator() then
    raise exception 'Moderator role required for role or status changes';
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

revoke all on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean)
  from public, anon;
grant execute on function public.moderator_update_profile_admin_fields(uuid,text,text,boolean)
  to authenticated;
