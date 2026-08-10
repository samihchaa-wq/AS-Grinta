-- Fairness and actor attribution fixes for the sports waitlist rotation.

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
  v_previous_match_count integer := 0;
  v_max_position integer := 0;
begin
  perform private.require_sports_management_enabled();

  if v_actor is null or not exists (
    select 1
    from public.profiles profile
    where profile.id = v_actor
      and profile.role = 'admin'
      and profile.status = 'active'
  ) then
    select profile.id into v_actor
    from public.profiles profile
    where profile.role = 'admin' and profile.status = 'active'
    order by profile.created_at
    limit 1;
  end if;
  if v_actor is null then
    raise exception 'Active administrator profile required' using errcode = '42501';
  end if;

  perform 1 from public.seasons season where season.id = p_season_id for update;
  if not found then
    raise exception 'Sport season not found' using errcode = 'P0002';
  end if;

  select previous.id into v_previous_season_id
  from public.seasons current
  join public.seasons previous on previous.name < current.name
  where current.id = p_season_id
  order by previous.name desc, previous.created_at desc
  limit 1;

  if v_previous_season_id is not null then
    select count(*)::integer into v_previous_match_count
    from public.matches match
    where match.season_id = v_previous_season_id
      and match.status in ('termine', 'archive');
  end if;

  select coalesce(max(entry.position), 0) into v_max_position
  from public.sport_waitlist_entries entry
  where entry.season_id = p_season_id;

  insert into public.sport_waitlist_entries (
    season_id,
    season_player_id,
    position,
    previous_season_attendance_count,
    previous_season_match_count,
    source,
    created_by,
    updated_by
  )
  select
    p_season_id,
    player.id,
    v_max_position + row_number() over (
      order by
        coalesce(previous_stats.attendance_count, 0) asc,
        player.position asc nulls last,
        lower(player.first_name),
        lower(player.last_name),
        player.id
    )::integer,
    coalesce(previous_stats.attendance_count, 0),
    v_previous_match_count,
    case
      when v_max_position = 0 then 'previous_season_attendance'
      else 'new_player'
    end,
    v_actor,
    v_actor
  from public.season_players player
  join public.profiles profile
    on profile.id = player.profile_id
   and profile.status = 'active'
  left join lateral (
    select count(distinct attendance.match_id)::integer as attendance_count
    from public.season_players previous_player
    join public.match_attendance attendance
      on attendance.season_player_id = previous_player.id
    join public.matches previous_match
      on previous_match.id = attendance.match_id
     and previous_match.status in ('termine', 'archive')
    where v_previous_season_id is not null
      and previous_player.season_id = v_previous_season_id
      and previous_player.profile_id = player.profile_id
  ) previous_stats on true
  where player.season_id = p_season_id
    and player.is_active
    and not exists (
      select 1
      from public.sport_waitlist_entries existing
      where existing.season_player_id = player.id
    )
  order by
    coalesce(previous_stats.attendance_count, 0) asc,
    player.position asc nulls last,
    lower(player.first_name),
    lower(player.last_name),
    player.id;
end;
$function$;

create or replace function private.finalize_match_waitlist_turns_internal(
  p_match_id uuid,
  p_force boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request_actor uuid := (select auth.uid());
  v_admin_actor uuid;
  v_season_id uuid;
  v_cutoff timestamptz;
  v_match_status text;
  v_entry record;
  v_max_position integer;
  v_consumed integer := 0;
begin
  perform private.require_sports_management_enabled();

  select match.season_id, workflow.late_withdrawal_cutoff_at,
    match.status, workflow.updated_by
  into v_season_id, v_cutoff, v_match_status, v_admin_actor
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if not p_force
     and v_match_status = 'a_venir'
     and (v_cutoff is null or now() <= v_cutoff) then
    return 0;
  end if;

  if private.is_admin() then
    v_admin_actor := v_request_actor;
  end if;
  perform private.ensure_sport_waitlist(v_season_id, v_admin_actor);

  for v_entry in
    select participant.id as participant_id,
      participant.season_player_id,
      waitlist.position
    from public.match_sport_participants participant
    join public.sport_waitlist_entries waitlist
      on waitlist.season_player_id = participant.season_player_id
    where participant.match_id = p_match_id
      and participant.waitlist_turn_state = 'pending'
      and participant.waitlist_turn_should_consume
    order by waitlist.position, participant.id
    for update of participant, waitlist
  loop
    select coalesce(max(entry.position), 0) + 1
    into v_max_position
    from public.sport_waitlist_entries entry
    where entry.season_id = v_season_id;

    update public.sport_waitlist_entries
    set position = v_max_position,
        source = 'manual',
        updated_by = v_admin_actor,
        updated_at = now()
    where season_player_id = v_entry.season_player_id;

    update public.match_sport_participants
    set waitlist_turn_state = 'consumed',
        waitlist_turn_updated_at = now(),
        updated_at = now()
    where id = v_entry.participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_entry.participant_id, p_match_id, 'waitlist_turn_consumed',
      jsonb_build_object('position', v_entry.position),
      jsonb_build_object('moved_to_end', true),
      case when private.is_admin() then v_request_actor else null end,
      case when private.is_admin() then 'staff' else 'system' end
    );
    v_consumed := v_consumed + 1;
  end loop;

  if v_consumed > 0 then
    perform private.resequence_sport_waitlist(v_season_id, v_admin_actor);
  end if;

  return v_consumed;
end;
$function$;

create or replace function private.normalize_waitlisted_withdrawal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_convocation_state public.sport_convocation_state;
  v_cutoff timestamptz;
begin
  if old.availability_status = 'available'
     and new.availability_status = 'absent'
     and old.convocation_status = 'not_convoked' then
    select workflow.convocation_state, workflow.late_withdrawal_cutoff_at
    into v_convocation_state, v_cutoff
    from public.match_sport_workflows workflow
    where workflow.match_id = old.match_id;

    if v_convocation_state = 'published' then
      new.convocation_status := 'not_applicable';
      new.convocation_manual_override := false;
      new.waitlist_recommended_not_convoked := false;

      if old.waitlist_turn_state = 'pending'
         and (v_cutoff is null or now() <= v_cutoff) then
        new.waitlist_turn_should_consume := false;
        new.waitlist_turn_state := 'waived';
        new.waitlist_turn_updated_at := now();
      end if;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists normalize_waitlisted_withdrawal_before_update
  on public.match_sport_participants;
create trigger normalize_waitlisted_withdrawal_before_update
before update of availability_status on public.match_sport_participants
for each row
execute function private.normalize_waitlisted_withdrawal();

revoke execute on function private.normalize_waitlisted_withdrawal()
  from public, anon, authenticated;
grant execute on function private.normalize_waitlisted_withdrawal()
  to service_role;

comment on function private.normalize_waitlisted_withdrawal() is
  'Waives a pending waitlist turn when a non-convoked player becomes absent at or before the cutoff.';
