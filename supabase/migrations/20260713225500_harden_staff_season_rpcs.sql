-- P0: harden staff profile and season administration RPCs.
-- All functions require an active administrator, use a fixed empty search_path,
-- validate nullable parameters explicitly, and fail when the target does not exist.

create or replace function public.staff_list_profiles()
returns table(
  id uuid,
  first_name text,
  last_name text,
  surnom text,
  username text,
  password_set boolean,
  photo_url text,
  role text,
  is_goalkeeper boolean,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.first_name,
    p.last_name,
    p.surnom,
    p.username,
    p.password_set,
    p.photo_url,
    p.role,
    p.is_goalkeeper,
    p.status,
    p.created_at,
    p.updated_at
  from public.profiles p
  where p.id <> '00000000-0000-0000-0000-000000000001'::uuid
  order by p.first_name, p.last_name;
end;
$$;

create or replace function public.staff_profile_username(p_profile_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result text;
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

  select p.username
  into result
  from public.profiles p
  where p.id = p_profile_id;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  return result;
end;
$$;

create or replace function public.admin_require_password_change(p_profile_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;

  if p_profile_id = actor_id then
    raise exception 'Use your profile to change your own password' using errcode = '22023';
  end if;

  if p_profile_id = '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Protected technical account' using errcode = '42501';
  end if;

  update public.profiles
  set must_change_password = true,
      password_set = true,
      updated_at = now()
  where id = p_profile_id
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = 'P0002';
  end if;

  return true;
end;
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

  if p_role is not null
     and p_role not in ('pronostiqueur', 'admin', 'moderateur') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;

  if p_status is not null
     and p_status not in ('pending', 'active', 'archived') then
    raise exception 'Invalid status' using errcode = '22023';
  end if;

  if p_profile_id = actor_id
     and (p_role is not null or p_status is not null) then
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
    where role = 'admin'
      and status = 'active';

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

create or replace function public.open_or_create_season(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  season_name text := btrim(coalesce(p_name, ''));
  start_year integer;
  end_year integer;
  season_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if season_name !~ '^\d{4}-\d{4}$' then
    raise exception 'Le nom doit respecter le format 2026-2027'
      using errcode = '22023';
  end if;

  start_year := substring(season_name from 1 for 4)::integer;
  end_year := substring(season_name from 6 for 4)::integer;

  if end_year <> start_year + 1 then
    raise exception 'La saison doit couvrir deux années consécutives'
      using errcode = '22023';
  end if;

  if start_year < 2000 or start_year > 2100 then
    raise exception 'Année de saison hors limites' using errcode = '22023';
  end if;

  select s.id
  into season_id
  from public.seasons s
  where s.name = season_name
  for update;

  update public.seasons
  set status = 'archived'
  where status = 'open'
    and (season_id is null or id <> season_id);

  if season_id is null then
    insert into public.seasons(name, status)
    values (season_name, 'open')
    returning id into season_id;
  else
    update public.seasons
    set status = 'open',
        season_predictions_locked_at = null
    where id = season_id;
  end if;

  return season_id;
end;
$$;

create or replace function public.set_season_status(
  p_season_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_season_id is null then
    raise exception 'Season id is required' using errcode = '22023';
  end if;

  if p_status is null
     or p_status not in ('open', 'terminee', 'archived') then
    raise exception 'Statut de saison invalide' using errcode = '22023';
  end if;

  perform 1
  from public.seasons
  where id = p_season_id
  for update;

  if not found then
    raise exception 'Season not found' using errcode = 'P0002';
  end if;

  if p_status = 'open' then
    update public.seasons
    set status = 'archived'
    where status = 'open'
      and id <> p_season_id;
  end if;

  update public.seasons
  set status = p_status
  where id = p_season_id;

  return true;
end;
$$;

create or replace function public.set_season_predictions_lock(
  p_season_id uuid,
  p_locked boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_season_id is null or p_locked is null then
    raise exception 'Season id and lock value are required' using errcode = '22023';
  end if;

  update public.seasons
  set season_predictions_locked_at = case when p_locked then now() else null end
  where id = p_season_id
    and status = 'open';

  if not found then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;

  return true;
end;
$$;

revoke execute on function public.staff_list_profiles() from public, anon;
revoke execute on function public.staff_profile_username(uuid) from public, anon;
revoke execute on function public.admin_require_password_change(uuid) from public, anon;
revoke execute on function public.moderator_update_profile_admin_fields(uuid, text, text, boolean)
  from public, anon;
revoke execute on function public.open_or_create_season(text) from public, anon;
revoke execute on function public.set_season_status(uuid, text) from public, anon;
revoke execute on function public.set_season_predictions_lock(uuid, boolean)
  from public, anon;

grant execute on function public.staff_list_profiles() to authenticated, service_role;
grant execute on function public.staff_profile_username(uuid) to authenticated, service_role;
grant execute on function public.admin_require_password_change(uuid) to authenticated, service_role;
grant execute on function public.moderator_update_profile_admin_fields(uuid, text, text, boolean)
  to authenticated, service_role;
grant execute on function public.open_or_create_season(text) to authenticated, service_role;
grant execute on function public.set_season_status(uuid, text) to authenticated, service_role;
grant execute on function public.set_season_predictions_lock(uuid, boolean)
  to authenticated, service_role;
