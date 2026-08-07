-- Le bootstrap métier minimal embarque volontairement des versions simplifiées
-- de ces RPC. L'ajout de season_players.player_id rendait leurs anciens alias
-- `player_id` ambigus. On conserve exactement le comportement du bootstrap en
-- nommant explicitement les identifiants de joueur de saison.

create or replace function public.staff_set_match_attendance(
  p_match_id uuid,
  p_present uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_season_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  select season_id into v_season_id from public.matches where id = p_match_id;
  if v_season_id is null then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1
    from unnest(coalesce(p_present, '{}'::uuid[])) as requested(season_player_id)
    where not exists (
      select 1
      from public.season_players sp
      where sp.id = requested.season_player_id
        and sp.season_id = v_season_id
        and sp.is_active
    )
  ) then
    raise exception 'Attendance contains an invalid player' using errcode = '22023';
  end if;
  delete from public.match_attendance where match_id = p_match_id;
  insert into public.match_attendance(match_id, season_player_id)
  select p_match_id, requested.season_player_id
  from (
    select distinct unnest(coalesce(p_present, '{}'::uuid[])) as season_player_id
  ) requested
  where requested.season_player_id is not null;
  return true;
end;
$function$;

create or replace function public.staff_set_match_mvp(
  p_match_id uuid,
  p_players uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_season_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  select season_id into v_season_id from public.matches where id = p_match_id;
  if v_season_id is null then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1
    from unnest(coalesce(p_players, '{}'::uuid[])) as requested(season_player_id)
    where not exists (
      select 1
      from public.season_players sp
      where sp.id = requested.season_player_id
        and sp.season_id = v_season_id
        and sp.is_active
    )
  ) then
    raise exception 'MVP contains an invalid player' using errcode = '22023';
  end if;
  delete from public.match_man_of_match where match_id = p_match_id;
  insert into public.match_man_of_match(match_id, season_player_id)
  select p_match_id, requested.season_player_id
  from (
    select distinct unnest(coalesce(p_players, '{}'::uuid[])) as season_player_id
  ) requested
  where requested.season_player_id is not null;
  return true;
end;
$function$;
