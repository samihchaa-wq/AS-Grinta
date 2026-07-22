-- Affiche le surnom (sinon le prénom, jamais le nom) dans les listes de
-- l'effectif, des convocations et de la liste d'attente. Ajoute un
-- display_name résolu côté serveur à ces trois builders.

-- 1) Convocations (colonnes de l'effectif admin)
create or replace function private.get_match_convocations(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
      and workflow.convocation_state = 'draft'
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', count(*) filter (
      where participant.is_eligible
        and (
          (
            participant.season_player_id is not null
            and participant.availability_status = 'available'
          )
          or participant.guest_player_id is not null
        )
    ),
    'convoked_count', count(*) filter (
      where participant.is_eligible
        and participant.convocation_status = 'convoked'
        and (
          participant.availability_status = 'available'
          or participant.guest_player_id is not null
        )
    ),
    'not_convoked_count', count(*) filter (
      where participant.is_eligible
        and participant.season_player_id is not null
        and participant.availability_status = 'available'
        and participant.convocation_status = 'not_convoked'
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'display_name', case
          when guest.id is not null then
            btrim(guest.first_name) || ' (Invité)'
          else coalesce(nullif(btrim(profile.surnom), ''), btrim(player.first_name))
        end,
        'is_guest', guest.id is not null,
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'availability_status', participant.availability_status,
        'availability_updated_at', participant.availability_updated_at,
        'convocation_status', participant.convocation_status,
        'manual_override', participant.convocation_manual_override,
        'waitlist_position', waitlist.position,
        'waitlist_position_snapshot', participant.waitlist_position_snapshot,
        'recommended_not_convoked', participant.waitlist_recommended_not_convoked,
        'turn_should_consume', participant.waitlist_turn_should_consume,
        'turn_state', participant.waitlist_turn_state,
        'promoted_after_withdrawal_at', participant.promoted_after_withdrawal_at
      )
      order by
        case
          when participant.guest_player_id is not null then 0
          when participant.availability_status = 'available' then 0
          when participant.availability_status = 'no_response' then 1
          when participant.availability_status = 'absent' then 2
          else 3
        end,
        waitlist.position,
        lower(coalesce(player.first_name, guest.first_name)),
        lower(coalesce(player.last_name, guest.last_name, ''))
    ) filter (
      where participant.id is not null
        and participant.is_eligible
    ), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

-- 2) Tableau de disponibilité (effectif joueur + admin en lecture)
create or replace function private.get_match_availability_board(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'kickoff_at', match.kickoff_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'composition_published', exists (
      select 1
      from public.match_composition_publications publication
      where publication.match_id = match.id
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'display_name', case
          when guest.id is not null then btrim(guest.first_name)
          else coalesce(nullif(btrim(profile.surnom), ''), btrim(player.first_name))
        end,
        'is_guest', guest.id is not null,
        'status', participant.availability_status,
        'convocation_status', participant.convocation_status,
        'waitlist_position', waitlist.position,
        'promoted_from_participant_id', participant.promoted_from_participant_id
      )
      order by
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null) then 0
          when participant.availability_status = 'available' then 1
          when participant.availability_status = 'absent' then 2
          when participant.availability_status = 'no_response' then 3
          else 4
        end,
        waitlist.position,
        lower(coalesce(player.first_name, guest.first_name, '')),
        participant.id
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
   and participant.is_eligible
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- 3) Liste d'attente (écran admin)
create or replace function private.get_sport_waitlist(p_season_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_season_id uuid;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, (select auth.uid()));
  perform private.finalize_due_waitlist_turns_for_season(v_season_id);

  select jsonb_build_object(
    'season_id', season.id,
    'season_name', season.name,
    'entries', coalesce(jsonb_agg(
      jsonb_build_object(
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'display_name', coalesce(nullif(btrim(profile.surnom), ''), btrim(player.first_name)),
        'position', entry.position,
        'previous_season_attendance_count', entry.previous_season_attendance_count,
        'previous_season_match_count', entry.previous_season_match_count,
        'source', entry.source,
        'updated_at', entry.updated_at
      )
      order by entry.position
    ), '[]'::jsonb)
  )
  into v_result
  from public.seasons season
  left join public.sport_waitlist_entries entry on entry.season_id = season.id
  left join public.season_players player on player.id = entry.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  where season.id = v_season_id
  group by season.id, season.name;

  return v_result;
end;
$function$;
