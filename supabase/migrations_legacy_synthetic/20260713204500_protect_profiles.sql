-- P0: protect private profile fields while preserving public display data.

create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p)
  from public.profiles p
  where p.id = (select auth.uid());
$$;

create or replace function public.staff_profile_username(p_profile_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Accès réservé au staff.' using errcode = '42501';
  end if;

  return (
    select p.username
    from public.profiles p
    where p.id = p_profile_id
  );
end;
$$;

revoke execute on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated, service_role;

revoke execute on function public.staff_profile_username(uuid) from public, anon;
grant execute on function public.staff_profile_username(uuid) to authenticated, service_role;

-- Remove broad table access inherited from old defaults.
revoke select, update on table public.profiles from public, anon, authenticated;

-- Public directory fields needed by rankings and prediction displays.
grant select (
  id,
  first_name,
  surnom,
  photo_url,
  status
) on table public.profiles to authenticated;

-- A user may edit only the personal fields used by the profile screen.
grant update (
  first_name,
  last_name,
  updated_at
) on table public.profiles to authenticated;
