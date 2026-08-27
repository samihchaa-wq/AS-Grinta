begin;

-- Passes décisives : nouvelle statistique suivie au même endroit que les buts.
--
-- Contrat :
--   * une passe décisive se saisit sur un but AS Grinta attribué à un buteur,
--     jamais sur un CSC adverse ni sur un but encore non attribué ;
--   * le passeur ne peut pas être le buteur du même but ;
--   * les saisons importées ne portent aucune passe décisive : elles comptent
--     zéro, sans invention rétroactive.

-- ---------------------------------------------------------------------------
-- 1. Colonnes
-- ---------------------------------------------------------------------------

alter table public.match_player_stats
  add column if not exists assists integer not null default 0;

alter table public.match_player_stats
  drop constraint if exists match_player_stats_assists_check;
alter table public.match_player_stats
  add constraint match_player_stats_assists_check
  check (assists >= 0 and assists <= 99);

comment on column public.match_player_stats.assists is
  'Passes décisives créditées au joueur permanent pour ce match.';

alter table public.match_sport_participants
  add column if not exists final_assists integer not null default 0;

alter table public.match_sport_participants
  drop constraint if exists match_sport_participants_final_assists_check;
alter table public.match_sport_participants
  add constraint match_sport_participants_final_assists_check
  check (final_assists >= 0 and final_assists <= 99);

alter table public.match_sport_participants
  drop constraint if exists match_sport_participants_absent_assists_check;
alter table public.match_sport_participants
  add constraint match_sport_participants_absent_assists_check
  check (
    final_presence_status <> 'actual_absent'::public.sport_final_presence_status
    or final_assists = 0
  );

comment on column public.match_sport_participants.final_assists is
  'Passes décisives retenues par la validation du compte rendu.';

alter table public.match_live_events
  add column if not exists assist_participant_id uuid;

alter table public.match_live_events
  drop constraint if exists match_live_events_assist_participant_id_match_id_fkey;
alter table public.match_live_events
  add constraint match_live_events_assist_participant_id_match_id_fkey
  foreign key (assist_participant_id, match_id)
  references public.match_sport_participants(id, match_id) on delete restrict;

alter table public.match_live_events
  drop constraint if exists match_live_events_assist_consistency_check;
alter table public.match_live_events
  add constraint match_live_events_assist_consistency_check
  check (
    assist_participant_id is null
    or (
      event_type = 'goal_us'
      and not is_opponent_own_goal
      and scorer_participant_id is not null
      and assist_participant_id <> scorer_participant_id
    )
  );

comment on column public.match_live_events.assist_participant_id is
  'Passeur décisif du but AS Grinta, toujours distinct du buteur.';

-- ---------------------------------------------------------------------------
-- 2. Live : désigner buteur et passeur d'un même geste
-- ---------------------------------------------------------------------------

drop function if exists private.set_match_live_event_scorer(uuid, uuid, uuid, boolean);

create function private.set_match_live_event_scorer(
  p_match_id uuid,
  p_event_id uuid,
  p_scorer_participant_id uuid default null,
  p_is_opponent_own_goal boolean default false,
  p_assist_participant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_exported boolean;
  v_type text;
  v_valid boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if coalesce(p_is_opponent_own_goal, false) and p_scorer_participant_id is not null then
    raise exception 'An own goal cannot be credited to a player' using errcode = '22023';
  end if;
  if p_assist_participant_id is not null then
    if coalesce(p_is_opponent_own_goal, false) then
      raise exception 'An own goal cannot have an assist' using errcode = '22023';
    end if;
    if p_scorer_participant_id is null then
      raise exception 'An assist requires a scorer' using errcode = '22023';
    end if;
    if p_assist_participant_id = p_scorer_participant_id then
      raise exception 'The assist cannot be credited to the scorer' using errcode = '22023';
    end if;
  end if;

  select session.state, session.exported
  into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime', 'finished') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;
  if coalesce(v_exported, false) then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;

  select event.event_type into v_type
  from public.match_live_events event
  where event.id = p_event_id and event.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  if v_type <> 'goal_us' then
    raise exception 'Only an AS Grinta goal can have a scorer' using errcode = '22023';
  end if;

  if p_scorer_participant_id is not null then
    select exists (
      select 1 from public.match_sport_participants participant
      where participant.id = p_scorer_participant_id
        and participant.match_id = p_match_id
    ) into v_valid;
    if not v_valid then
      raise exception 'Unknown scorer for this match' using errcode = '22023';
    end if;
  end if;

  if p_assist_participant_id is not null then
    select exists (
      select 1 from public.match_sport_participants participant
      where participant.id = p_assist_participant_id
        and participant.match_id = p_match_id
    ) into v_valid;
    if not v_valid then
      raise exception 'Unknown assist provider for this match' using errcode = '22023';
    end if;
  end if;

  update public.match_live_events
  set scorer_participant_id = p_scorer_participant_id,
      is_opponent_own_goal = coalesce(p_is_opponent_own_goal, false),
      assist_participant_id = p_assist_participant_id
  where id = p_event_id and match_id = p_match_id;

  update public.match_live_sessions
  set updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

alter function private.set_match_live_event_scorer(uuid, uuid, uuid, boolean, uuid)
  owner to postgres;
revoke all on function private.set_match_live_event_scorer(uuid, uuid, uuid, boolean, uuid)
  from public;
grant execute on function private.set_match_live_event_scorer(uuid, uuid, uuid, boolean, uuid)
  to service_role;

drop function if exists public.coach_set_match_live_event_scorer(uuid, uuid, uuid, boolean);

create function public.coach_set_match_live_event_scorer(
  p_match_id uuid,
  p_event_id uuid,
  p_scorer_participant_id uuid default null,
  p_is_opponent_own_goal boolean default false,
  p_assist_participant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  return private.set_match_live_event_scorer(
    p_match_id,
    p_event_id,
    p_scorer_participant_id,
    p_is_opponent_own_goal,
    p_assist_participant_id
  );
end;
$function$;

alter function public.coach_set_match_live_event_scorer(uuid, uuid, uuid, boolean, uuid)
  owner to postgres;
revoke all on function public.coach_set_match_live_event_scorer(uuid, uuid, uuid, boolean, uuid)
  from public;
grant execute on function public.coach_set_match_live_event_scorer(uuid, uuid, uuid, boolean, uuid)
  to authenticated, service_role;


-- ---------------------------------------------------------------------------
-- 3. Lectures Live : le passeur voyage avec le but
-- ---------------------------------------------------------------------------

create or replace function private.match_live_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_session jsonb;
  v_events jsonb;
  v_counts jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', session.match_id,
    'state', session.state,
    'planned_duration_minutes', session.planned_duration_minutes,
    'half', session.half,
    'elapsed_seconds', session.elapsed_seconds,
    'running_since', session.running_since,
    'score_as_grinta', session.score_as_grinta,
    'score_adverse', session.score_adverse,
    'started_at', session.started_at,
    'finished_at', session.finished_at,
    'exported', session.exported,
    'exported_at', session.exported_at,
    'lineup_revision', session.lineup_revision,
    'true_elapsed_seconds',
      session.elapsed_seconds + case
        when session.state = 'running'
        then greatest(0, extract(epoch from now() - session.running_since))::integer
        else 0
      end,
    'display_minute',
      (session.elapsed_seconds + case
        when session.state = 'running'
        then greatest(0, extract(epoch from now() - session.running_since))::integer
        else 0
      end) / 60 + 1
  )
  into v_session
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if v_session is null then
    return jsonb_build_object('match_id', p_match_id, 'state', null, 'session_exists', false);
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', event.id,
      'event_type', event.event_type,
      'minute', event.minute,
      'half', event.half,
      'scorer_participant_id', event.scorer_participant_id,
      'scorer_name', case
        when scorer_guest.id is not null then
          btrim(scorer_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(scorer_profile.surnom), ''), nullif(btrim(scorer_profile.first_name), ''),
          nullif(btrim(scorer_player.first_name), '')
        )
      end,
      'assist_participant_id', event.assist_participant_id,
      'assist_name', case
        when assist_guest.id is not null then
          btrim(assist_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(assist_profile.surnom), ''), nullif(btrim(assist_profile.first_name), ''),
          nullif(btrim(assist_player.first_name), '')
        )
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_participant_id', event.player_in_participant_id,
      'player_in_name', case
        when in_guest.id is not null then
          btrim(in_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(in_profile.surnom), ''), nullif(btrim(in_profile.first_name), ''),
          nullif(btrim(in_player.first_name), '')
        )
      end,
      'player_out_participant_id', event.player_out_participant_id,
      'player_out_name', case
        when out_guest.id is not null then
          btrim(out_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(out_profile.surnom), ''), nullif(btrim(out_profile.first_name), ''),
          nullif(btrim(out_player.first_name), '')
        )
      end,
      'is_opponent_own_goal', coalesce(event.is_opponent_own_goal, false),
      'created_at', event.created_at
    ) order by event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants assist_p on assist_p.id = event.assist_participant_id
  left join public.season_players assist_player on assist_player.id = assist_p.season_player_id
  left join public.profiles assist_profile on assist_profile.id = assist_player.profile_id
  left join public.guest_players assist_guest on assist_guest.id = assist_p.guest_player_id
  left join public.match_sport_participants in_p on in_p.id = event.player_in_participant_id
  left join public.season_players in_player on in_player.id = in_p.season_player_id
  left join public.profiles in_profile on in_profile.id = in_player.profile_id
  left join public.guest_players in_guest on in_guest.id = in_p.guest_player_id
  left join public.match_sport_participants out_p on out_p.id = event.player_out_participant_id
  left join public.season_players out_player on out_player.id = out_p.season_player_id
  left join public.profiles out_profile on out_profile.id = out_player.profile_id
  left join public.guest_players out_guest on out_guest.id = out_p.guest_player_id
  where event.match_id = p_match_id;

  select coalesce(jsonb_object_agg(participant_id, times_benched), '{}'::jsonb)
  into v_counts
  from (
    select
      participant.id as participant_id,
      (
        case when coalesce(session.starting_lineup_snapshot -> participant.id::text, 'null'::jsonb) = '"bench"'::jsonb
          then 1 else 0
        end
        + coalesce((
          select count(*)
          from public.match_live_events sub_event
          where sub_event.match_id = p_match_id
            and sub_event.event_type = 'substitution'
            and sub_event.player_out_participant_id = participant.id
        ), 0)
      ) as times_benched
    from public.match_sport_participants participant
    cross join public.match_live_sessions session
    where participant.match_id = p_match_id
      and session.match_id = p_match_id
      and (participant.is_eligible or participant.final_presence_status <> 'pending')
  ) counted
  where counted.times_benched > 0;

  return v_session
    || jsonb_build_object('session_exists', true)
    || jsonb_build_object('lineup', private.composition_snapshot(p_match_id))
    || jsonb_build_object('events', v_events)
    || jsonb_build_object('substitute_counts', v_counts);
end;
$function$;

create or replace function private.get_match_live_timeline(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_exported boolean;
  v_events jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select session.exported into v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if not found or not coalesce(v_exported, false) then
    return null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'event_type', event.event_type,
      'minute', event.minute,
      'half', event.half,
      'scorer_name', case
        when scorer_guest.id is not null then
          btrim(scorer_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(scorer_profile.surnom), ''),
          nullif(btrim(scorer_profile.first_name), ''),
          nullif(btrim(scorer_player.first_name), '')
        )
      end,
      'assist_name', case
        when assist_guest.id is not null then
          btrim(assist_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(assist_profile.surnom), ''),
          nullif(btrim(assist_profile.first_name), ''),
          nullif(btrim(assist_player.first_name), '')
        )
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_name', case
        when in_guest.id is not null then
          btrim(in_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(in_profile.surnom), ''),
          nullif(btrim(in_profile.first_name), ''),
          nullif(btrim(in_player.first_name), '')
        )
      end,
      'player_out_name', case
        when out_guest.id is not null then
          btrim(out_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(out_profile.surnom), ''),
          nullif(btrim(out_profile.first_name), ''),
          nullif(btrim(out_player.first_name), '')
        )
      end
    ) order by event.half, event.minute, event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants assist_p on assist_p.id = event.assist_participant_id
  left join public.season_players assist_player on assist_player.id = assist_p.season_player_id
  left join public.profiles assist_profile on assist_profile.id = assist_player.profile_id
  left join public.guest_players assist_guest on assist_guest.id = assist_p.guest_player_id
  left join public.match_sport_participants in_p on in_p.id = event.player_in_participant_id
  left join public.season_players in_player on in_player.id = in_p.season_player_id
  left join public.profiles in_profile on in_profile.id = in_player.profile_id
  left join public.guest_players in_guest on in_guest.id = in_p.guest_player_id
  left join public.match_sport_participants out_p on out_p.id = event.player_out_participant_id
  left join public.season_players out_player on out_player.id = out_p.season_player_id
  left join public.profiles out_profile on out_profile.id = out_player.profile_id
  left join public.guest_players out_guest on out_guest.id = out_p.guest_player_id
  where event.match_id = p_match_id;

  return jsonb_build_object('match_id', p_match_id, 'events', v_events);
end;
$function$;

commit;
