
create or replace function private.ensure_sport_waitlist(
  p_season_id uuid,
  p_actor uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := coalesce(p_actor, (select auth.uid()));
  v_previous_season_id uuid;
  v_previous_season_name text;
  v_prev_has_inapp boolean := false;
  v_previous_match_count integer := 0;
  v_max_position integer := 0;
begin
  perform private.require_sports_management_enabled();

  if v_actor is null or not exists (
    select 1 from public.profiles profile
    where profile.id = v_actor and profile.role = 'admin' and profile.status = 'active'
  ) then
    select profile.id into v_actor
    from public.profiles profile
    where profile.role = 'admin' and profile.status = 'active'
    order by profile.created_at limit 1;
  end if;
  if v_actor is null then
    raise exception 'Active administrator profile required' using errcode = '42501';
  end if;

  perform 1 from public.seasons season where season.id = p_season_id for update;
  if not found then
    raise exception 'Sport season not found' using errcode = 'P0002';
  end if;

  select previous.id, previous.name into v_previous_season_id, v_previous_season_name
  from public.seasons current
  join public.seasons previous on previous.name < current.name
  where current.id = p_season_id
  order by previous.name desc, previous.created_at desc limit 1;

  if v_previous_season_id is not null then
    select exists (
      select 1 from public.match_attendance attendance
      join public.matches match on match.id = attendance.match_id
      where match.season_id = v_previous_season_id
    ) into v_prev_has_inapp;
  end if;

  if v_prev_has_inapp then
    select count(*)::integer into v_previous_match_count
    from public.matches match
    where match.season_id = v_previous_season_id and match.status in ('termine', 'archive');
  elsif v_previous_season_name is not null then
    select coalesce(max(h.matches_played), 0)::integer into v_previous_match_count
    from public.historical_player_statistics h
    where h.scope = 'previous' and h.season_name = v_previous_season_name;
  end if;

  select coalesce(max(entry.position), 0) into v_max_position
  from public.sport_waitlist_entries entry where entry.season_id = p_season_id;

  insert into public.sport_waitlist_entries (
    season_id, season_player_id, position, previous_season_attendance_count,
    previous_season_match_count, source, created_by, updated_by
  )
  select
    p_season_id, player.id,
    v_max_position + row_number() over (
      order by coalesce(previous_stats.attendance_count, 0) asc,
        player.position asc nulls last, lower(player.first_name),
        lower(player.last_name), player.id
    )::integer,
    coalesce(previous_stats.attendance_count, 0),
    v_previous_match_count,
    case when v_max_position = 0 then 'previous_season_attendance' else 'new_player' end,
    v_actor, v_actor
  from public.season_players player
  left join lateral (
    select case when v_prev_has_inapp then inapp.cnt else hist.mp end as attendance_count
    from (
      select count(distinct attendance.match_id)::integer as cnt
      from public.season_players previous_player
      join public.match_attendance attendance on attendance.season_player_id = previous_player.id
      join public.matches previous_match on previous_match.id = attendance.match_id
        and previous_match.status in ('termine', 'archive')
      where v_previous_season_id is not null
        and previous_player.season_id = v_previous_season_id
        and (
          (previous_player.profile_id is not null and previous_player.profile_id = player.profile_id)
          or lower(btrim(concat_ws(' ', previous_player.first_name, nullif(previous_player.last_name, ''))))
             = lower(btrim(concat_ws(' ', player.first_name, nullif(player.last_name, ''))))
        )
    ) inapp
    cross join (
      select max(h.matches_played)::integer as mp
      from public.historical_player_statistics h
      where h.scope = 'previous'
        and (v_previous_season_name is null or h.season_name = v_previous_season_name)
        and (
          (h.profile_id is not null and h.profile_id = player.profile_id)
          or lower(btrim(h.player_name))
             = lower(btrim(concat_ws(' ', player.first_name, nullif(player.last_name, ''))))
        )
    ) hist
  ) previous_stats on true
  where player.season_id = p_season_id
    and player.is_active
    and not exists (
      select 1 from public.sport_waitlist_entries existing
      where existing.season_player_id = player.id
    )
  order by coalesce(previous_stats.attendance_count, 0) asc,
    player.position asc nulls last, lower(player.first_name),
    lower(player.last_name), player.id;
end;
$function$;

do $$
declare v_season uuid;
begin
  if private.is_feature_enabled('sports_management') then
    for v_season in select id from public.seasons where status = 'open' loop
      if not exists (
        select 1 from public.sport_waitlist_entries entry
        where entry.season_id = v_season and entry.source = 'manual'
      ) then
        delete from public.sport_waitlist_entries where season_id = v_season;
        perform private.ensure_sport_waitlist(v_season, null);
      end if;
    end loop;
  end if;
end $$;
;
