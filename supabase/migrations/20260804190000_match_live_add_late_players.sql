-- Tableau Blanc: allow staff to add late roster players or guests directly
-- to the live bench, before kickoff confirmation or while the match is live.
-- Also preserve pre-kickoff lineup corrections when the duration is saved.

create or replace function private.get_match_live_add_player_options(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_season_id uuid;
  v_state public.match_live_state;
  v_roster jsonb;
  v_guests jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach, administrator or moderator role required' using errcode = '42501';
  end if;

  select match.season_id, session.state
  into v_season_id, v_state
  from public.matches match
  join public.match_live_sessions session on session.match_id = match.id
  where match.id = p_match_id;

  if not found then
    raise exception 'Open the live workspace before adding a player' using errcode = '22023';
  end if;
  if v_state not in ('not_started', 'running', 'paused', 'halftime') then
    raise exception 'Players can only be added while the live session is open' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', candidate.participant_id,
      'season_player_id', candidate.season_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', false
    ) order by lower(candidate.display_name), candidate.season_player_id
  ), '[]'::jsonb)
  into v_roster
  from (
    select
      player.id as season_player_id,
      participant.id as participant_id,
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        btrim(concat_ws(' ', player.first_name, player.last_name)),
        'Joueur'
      ) as display_name,
      coalesce(profile.photo_url, player.photo_url) as photo_url,
      player.is_goalkeeper
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    left join public.match_sport_participants participant
      on participant.match_id = p_match_id
     and participant.season_player_id = player.id
    where player.season_id = v_season_id
      and player.is_active
      and (player.profile_id is null or profile.status = 'active')
      and not exists (
        select 1
        from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
  ) candidate;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', candidate.participant_id,
      'guest_player_id', candidate.guest_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', true
    ) order by lower(candidate.display_name), candidate.guest_player_id
  ), '[]'::jsonb)
  into v_guests
  from (
    select
      guest.id as guest_player_id,
      participant.id as participant_id,
      btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)' as display_name,
      guest.photo_url,
      guest.is_goalkeeper
    from public.guest_players guest
    left join public.match_sport_participants participant
      on participant.match_id = p_match_id
     and participant.guest_player_id = guest.id
    where guest.is_reusable
      and guest.archived_at is null
      and not exists (
        select 1
        from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
  ) candidate;

  return jsonb_build_object(
    'match_id', p_match_id,
    'session_state', v_state,
    'roster', v_roster,
    'guests', v_guests
  );
end;
$function$;

create or replace function private.add_match_live_players(
  p_match_id uuid,
  p_players jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_season_id uuid;
  v_item jsonb;
  v_kind text;
  v_season_player_id uuid;
  v_guest_player_id uuid;
  v_participant_id uuid;
  v_first_name text;
  v_last_name text;
  v_is_goalkeeper boolean;
  v_bench_order integer;
  v_added_count integer := 0;
  v_guest public.guest_players%rowtype;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach, administrator or moderator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;
  if p_players is null or jsonb_typeof(p_players) <> 'array'
     or jsonb_array_length(p_players) < 1
     or jsonb_array_length(p_players) > 30 then
    raise exception 'Players must be a non-empty JSON array of at most 30 items' using errcode = '22023';
  end if;

  select match.season_id, session.state
  into v_season_id, v_state
  from public.matches match
  join public.match_live_sessions session on session.match_id = match.id
  where match.id = p_match_id
  for update of session;

  if not found then
    raise exception 'Open the live workspace before adding a player' using errcode = '22023';
  end if;
  if v_state not in ('not_started', 'running', 'paused', 'halftime') then
    raise exception 'Players can only be added while the live session is open' using errcode = '22023';
  end if;

  perform 1
  from public.match_compositions composition
  where composition.match_id = p_match_id
  for update;
  if not found then
    raise exception 'Live composition not found' using errcode = 'P0002';
  end if;

  select coalesce(max(entry.sort_order), -1) + 1
  into v_bench_order
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone = 'bench';

  for v_item in select value from jsonb_array_elements(p_players)
  loop
    v_kind := lower(coalesce(nullif(btrim(v_item ->> 'kind'), ''), ''));
    v_season_player_id := null;
    v_guest_player_id := null;
    v_participant_id := null;
    v_first_name := null;
    v_last_name := null;
    v_is_goalkeeper := coalesce((v_item ->> 'is_goalkeeper')::boolean, false);

    if v_kind = 'roster' then
      begin
        v_season_player_id := nullif(v_item ->> 'season_player_id', '')::uuid;
      exception when invalid_text_representation then
        raise exception 'Invalid roster player identifier' using errcode = '22023';
      end;
      if v_season_player_id is null then
        raise exception 'Roster player identifier is required' using errcode = '22023';
      end if;

      perform 1
      from public.season_players player
      left join public.profiles profile on profile.id = player.profile_id
      where player.id = v_season_player_id
        and player.season_id = v_season_id
        and player.is_active
        and (player.profile_id is null or profile.status = 'active')
      for update of player;
      if not found then
        raise exception 'Roster player is not active for this match season' using errcode = '22023';
      end if;

      select participant.id
      into v_participant_id
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.season_player_id = v_season_player_id
      for update;

      if not found then
        insert into public.match_sport_participants (
          match_id,
          season_player_id,
          is_eligible,
          availability_status,
          convocation_status,
          convocation_manual_override,
          selection_status,
          final_presence_status,
          final_presence_confirmed_at,
          final_presence_confirmed_by
        ) values (
          p_match_id,
          v_season_player_id,
          true,
          'available',
          'convoked',
          true,
          'substitute',
          'present',
          now(),
          v_actor
        ) returning id into v_participant_id;
      end if;

    elsif v_kind in ('guest', 'new_guest') then
      if v_kind = 'guest' then
        begin
          v_guest_player_id := nullif(v_item ->> 'guest_player_id', '')::uuid;
        exception when invalid_text_representation then
          raise exception 'Invalid guest player identifier' using errcode = '22023';
        end;
        if v_guest_player_id is null then
          raise exception 'Guest player identifier is required' using errcode = '22023';
        end if;

        select guest.* into v_guest
        from public.guest_players guest
        where guest.id = v_guest_player_id
          and guest.is_reusable
          and guest.archived_at is null
        for update;
        if not found then
          raise exception 'Guest player is unavailable or archived' using errcode = '22023';
        end if;
      else
        v_first_name := nullif(btrim(v_item ->> 'first_name'), '');
        v_last_name := nullif(btrim(v_item ->> 'last_name'), '');
        if v_first_name is null then
          raise exception 'Guest first name is required' using errcode = '22023';
        end if;
        if char_length(v_first_name) > 80
           or (v_last_name is not null and char_length(v_last_name) > 80) then
          raise exception 'Guest name cannot exceed 80 characters per field' using errcode = '22023';
        end if;

        select guest.* into v_guest
        from public.guest_players guest
        where guest.is_reusable
          and guest.archived_at is null
          and lower(btrim(guest.first_name)) = lower(v_first_name)
          and lower(coalesce(btrim(guest.last_name), '')) = lower(coalesce(v_last_name, ''))
          and guest.is_goalkeeper = v_is_goalkeeper
        order by guest.created_at
        limit 1
        for update;

        if not found then
          insert into public.guest_players (
            first_name,
            last_name,
            is_goalkeeper,
            created_by,
            updated_by
          ) values (
            v_first_name,
            v_last_name,
            v_is_goalkeeper,
            v_actor,
            v_actor
          ) returning * into v_guest;
        end if;
        v_guest_player_id := v_guest.id;
      end if;

      select participant.id
      into v_participant_id
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.guest_player_id = v_guest_player_id
      for update;

      if not found then
        insert into public.match_sport_participants (
          match_id,
          guest_player_id,
          is_eligible,
          availability_status,
          convocation_status,
          convocation_manual_override,
          waitlist_turn_state,
          selection_status,
          final_presence_status,
          final_presence_confirmed_at,
          final_presence_confirmed_by
        ) values (
          p_match_id,
          v_guest_player_id,
          true,
          'not_applicable',
          'convoked',
          true,
          'not_applicable',
          'substitute',
          'present',
          now(),
          v_actor
        ) returning id into v_participant_id;
      end if;
    else
      raise exception 'Player kind must be roster, guest or new_guest' using errcode = '22023';
    end if;

    if exists (
      select 1
      from public.match_composition_entries entry
      where entry.match_id = p_match_id
        and entry.participant_id = v_participant_id
        and entry.zone in ('field', 'bench')
    ) then
      raise exception 'A selected player is already present in the live lineup' using errcode = '22023';
    end if;

    update public.match_sport_participants participant
    set is_eligible = true,
        availability_status = case
          when participant.guest_player_id is null then 'available'::public.sport_availability_status
          else 'not_applicable'::public.sport_availability_status
        end,
        availability_comment_private = null,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        convocation_status = 'convoked',
        convocation_manual_override = true,
        waitlist_position_snapshot = null,
        waitlist_recommended_not_convoked = false,
        waitlist_turn_should_consume = false,
        waitlist_turn_state = 'not_applicable',
        selection_status = 'substitute',
        selection_updated_at = now(),
        selection_updated_by = v_actor,
        final_presence_status = 'present',
        final_presence_confirmed_at = now(),
        final_presence_confirmed_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id
      and participant.match_id = p_match_id;

    insert into public.match_composition_entries (
      match_id,
      participant_id,
      zone,
      x,
      y,
      slot_label,
      sort_order
    ) values (
      p_match_id,
      v_participant_id,
      'bench',
      null,
      null,
      null,
      v_bench_order
    )
    on conflict (match_id, participant_id) do update
    set zone = 'bench',
        x = null,
        y = null,
        slot_label = null,
        sort_order = excluded.sort_order,
        updated_at = now();

    v_bench_order := v_bench_order + 1;
    v_added_count := v_added_count + 1;
  end loop;

  update public.match_compositions
  set last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  update public.match_live_sessions
  set lineup_revision = lineup_revision + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'add_match_live_players',
    v_actor,
    v_reason,
    jsonb_build_object(
      'added_count', v_added_count,
      'session_state', v_state
    )
  );

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function private.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_match_status text;
  v_kickoff_at timestamptz;
  v_default_duration integer;
  v_existing_state public.match_live_state;
  v_publication_snapshot jsonb;
  v_formation text;
  v_has_entries boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status, match.kickoff_at, match.planned_duration_minutes
  into v_match_status, v_kickoff_at, v_default_duration
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() < v_kickoff_at then
    raise exception 'Live tracking is only available once kickoff has occurred'
      using errcode = '22023';
  end if;

  select session.state into v_existing_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if found then
    if v_existing_state <> 'not_started' then
      return private.match_live_snapshot(p_match_id);
    end if;

    update public.match_live_sessions
    set planned_duration_minutes = greatest(
          1,
          least(200, coalesce(p_planned_duration_minutes, planned_duration_minutes))
        ),
        updated_by = v_actor,
        updated_at = now()
    where match_id = p_match_id;

    select exists (
      select 1
      from public.match_composition_entries entry
      where entry.match_id = p_match_id
    ) into v_has_entries;

    if v_has_entries then
      return private.match_live_snapshot(p_match_id);
    end if;
  end if;

  select publication.snapshot, publication.formation_code
  into v_publication_snapshot, v_formation
  from public.match_composition_publications publication
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_publication_snapshot is null then
    raise exception 'No published composition to start from' using errcode = '22023';
  end if;

  insert into public.match_live_sessions (
    match_id, state, planned_duration_minutes, updated_by
  ) values (
    p_match_id, 'not_started',
    greatest(1, least(200, coalesce(p_planned_duration_minutes, v_default_duration))),
    v_actor
  )
  on conflict (match_id) do update
  set planned_duration_minutes = greatest(
        1,
        least(200, coalesce(p_planned_duration_minutes, match_live_sessions.planned_duration_minutes))
      ),
      updated_by = v_actor,
      updated_at = now();

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select
    p_match_id,
    (entry ->> 'participant_id')::uuid,
    (entry ->> 'zone')::public.sport_composition_zone,
    case when entry ->> 'x' is null then null else (entry ->> 'x')::numeric end,
    case when entry ->> 'y' is null then null else (entry ->> 'y')::numeric end,
    entry ->> 'slot_label',
    coalesce((entry ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(v_publication_snapshot -> 'entries') entry
  where (entry ->> 'zone') in ('field', 'bench', 'not_selected');

  update public.match_compositions
  set formation_code = v_formation,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.get_match_live_add_player_options(p_match_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_match_live_add_player_options(p_match_id);
$function$;

create or replace function public.coach_add_match_live_players(
  p_match_id uuid,
  p_players jsonb,
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.add_match_live_players(p_match_id, p_players, p_reason);
$function$;

revoke execute on function private.get_match_live_add_player_options(uuid) from public, anon;
revoke execute on function private.add_match_live_players(uuid, jsonb, text) from public, anon;
revoke execute on function public.get_match_live_add_player_options(uuid) from public, anon;
revoke execute on function public.coach_add_match_live_players(uuid, jsonb, text) from public, anon;

grant execute on function private.get_match_live_add_player_options(uuid) to authenticated, service_role;
grant execute on function private.add_match_live_players(uuid, jsonb, text) to authenticated, service_role;
grant execute on function public.get_match_live_add_player_options(uuid) to authenticated, service_role;
grant execute on function public.coach_add_match_live_players(uuid, jsonb, text) to authenticated, service_role;
