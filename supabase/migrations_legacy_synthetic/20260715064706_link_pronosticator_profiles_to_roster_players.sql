alter table public.season_players
  add column if not exists profile_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.season_players'::regclass
      and conname = 'season_players_profile_id_fkey'
  ) then
    alter table public.season_players
      add constraint season_players_profile_id_fkey
      foreign key (profile_id)
      references public.profiles(id)
      on delete set null;
  end if;
end
$$;

create unique index if not exists season_players_season_profile_unique
  on public.season_players(season_id, profile_id)
  where profile_id is not null;

comment on column public.season_players.profile_id is
  'Optional pronosticator profile linked to this roster player for the season.';

create or replace function public.staff_set_season_player_profile(
  p_season_player_id uuid,
  p_profile_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season_id uuid;
  v_profile_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_season_player_id is null then
    raise exception 'Season player id is required' using errcode = '22023';
  end if;

  select sp.season_id
  into v_season_id
  from public.season_players sp
  where sp.id = p_season_player_id
  for update;

  if not found then
    raise exception 'Season player not found' using errcode = 'P0002';
  end if;

  if p_profile_id is null then
    update public.season_players
    set profile_id = null
    where id = p_season_player_id;
    return true;
  end if;

  if p_profile_id = '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Protected technical account' using errcode = '42501';
  end if;

  select p.status
  into v_profile_status
  from public.profiles p
  where p.id = p_profile_id
  for update;

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  if v_profile_status <> 'active' then
    raise exception 'Only an active profile can be linked' using errcode = '23514';
  end if;

  update public.season_players
  set profile_id = null
  where season_id = v_season_id
    and profile_id = p_profile_id
    and id <> p_season_player_id;

  update public.season_players
  set profile_id = p_profile_id
  where id = p_season_player_id;

  return true;
end;
$$;

create or replace function public.staff_validate_profile(
  p_profile_id uuid,
  p_season_player_id uuid default null
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

  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;

  if p_profile_id = '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'Protected technical account' using errcode = '42501';
  end if;

  update public.profiles
  set status = 'active', updated_at = now()
  where id = p_profile_id
    and status = 'pending';

  if not found then
    raise exception 'Pending profile not found' using errcode = 'P0002';
  end if;

  if p_season_player_id is not null then
    perform public.staff_set_season_player_profile(
      p_season_player_id,
      p_profile_id
    );
  end if;

  return true;
end;
$$;

revoke all on function public.staff_set_season_player_profile(uuid, uuid) from public;
revoke all on function public.staff_set_season_player_profile(uuid, uuid) from anon;
grant execute on function public.staff_set_season_player_profile(uuid, uuid) to authenticated;

revoke all on function public.staff_validate_profile(uuid, uuid) from public;
revoke all on function public.staff_validate_profile(uuid, uuid) from anon;
grant execute on function public.staff_validate_profile(uuid, uuid) to authenticated;
