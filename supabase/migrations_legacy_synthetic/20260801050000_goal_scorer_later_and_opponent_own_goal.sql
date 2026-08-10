-- Buteur attribué après coup, et « CSC adverse ».
--
-- Ajouter un but ouvrait aussitôt la liste des joueurs, en plein match.
-- Le but est désormais enregistré immédiatement sans buteur ; le coach
-- l'attribue quand il veut depuis la ligne correspondante de la liste
-- « Buteurs ».
--
-- Un but d'AS Grinta peut aussi être un contre-son-camp adverse : il
-- compte au score mais n'est crédité à aucun joueur. Le drapeau
-- is_opponent_own_goal distingue ce cas d'un buteur simplement pas
-- encore choisi.

alter table public.match_live_events
  add column if not exists is_opponent_own_goal boolean not null default false;

-- La contrainte imposait un buteur sur tout but d'AS Grinta.
alter table public.match_live_events
  drop constraint if exists match_live_events_check;

alter table public.match_live_events
  add constraint match_live_events_check check (
    (
      event_type = 'goal_us'
      and score_as_grinta_after is not null
      and score_adverse_after is null
      and player_in_participant_id is null
      and player_out_participant_id is null
      and not (is_opponent_own_goal and scorer_participant_id is not null)
    )
    or (
      event_type = 'goal_them'
      and score_adverse_after is not null
      and score_as_grinta_after is null
      and scorer_participant_id is null
      and player_in_participant_id is null
      and player_out_participant_id is null
      and not is_opponent_own_goal
    )
    or (
      event_type = 'substitution'
      and player_in_participant_id is not null
      and player_out_participant_id is not null
      and scorer_participant_id is null
      and score_as_grinta_after is null
      and score_adverse_after is null
      and not is_opponent_own_goal
    )
  );

create or replace function private.match_live_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
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
          nullif(btrim(scorer_profile.surnom), ''),
          nullif(btrim(scorer_player.first_name), '')
        )
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_participant_id', event.player_in_participant_id,
      'player_in_name', case
        when in_guest.id is not null then
          btrim(in_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(in_profile.surnom), ''),
          nullif(btrim(in_player.first_name), '')
        )
      end,
      'player_out_participant_id', event.player_out_participant_id,
      'player_out_name', case
        when out_guest.id is not null then
          btrim(out_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(out_profile.surnom), ''),
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

create or replace function private.adjust_match_live_score(
  p_match_id uuid,
  p_team text,
  p_delta integer,
  p_scorer_participant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_true_elapsed integer;
  v_minute integer;
  v_score_us integer;
  v_score_them integer;
  v_scorer_valid boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_team not in ('us', 'them') then
    raise exception 'Invalid team' using errcode = '22023';
  end if;
  if p_delta not in (-1, 1) then
    raise exception 'Score delta must be -1 or 1' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half,
    session.score_as_grinta, session.score_adverse
  into v_state, v_elapsed, v_running_since, v_half, v_score_us, v_score_them
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;

  v_true_elapsed := v_elapsed + case
    when v_state = 'running'
    then greatest(0, extract(epoch from now() - v_running_since))::integer
    else 0
  end;
  v_minute := v_true_elapsed / 60 + 1;

  if p_team = 'us' and p_delta = 1 then
    -- Le buteur n'est plus obligatoire : le but est enregistré tout de
    -- suite et le coach l'attribue ensuite depuis la liste « Buteurs »,
    -- sans que rien ne lui saute au visage pendant le match.
    if p_scorer_participant_id is not null then
      select exists (
        select 1 from public.match_sport_participants participant
        where participant.id = p_scorer_participant_id and participant.match_id = p_match_id
      ) into v_scorer_valid;
      if not v_scorer_valid then
        raise exception 'Unknown scorer for this match' using errcode = '22023';
      end if;
    end if;

    update public.match_live_sessions
    set score_as_grinta = least(99, v_score_us + 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;

    insert into public.match_live_events (
      match_id, event_type, minute, half, scorer_participant_id,
      score_as_grinta_after, created_by
    ) values (
      p_match_id, 'goal_us', v_minute, v_half, p_scorer_participant_id,
      least(99, v_score_us + 1), v_actor
    );
  elsif p_team = 'us' and p_delta = -1 then
    update public.match_live_sessions
    set score_as_grinta = greatest(0, v_score_us - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_team = 'them' and p_delta = 1 then
    update public.match_live_sessions
    set score_adverse = least(99, v_score_them + 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;

    insert into public.match_live_events (
      match_id, event_type, minute, half, score_adverse_after, created_by
    ) values (
      p_match_id, 'goal_them', v_minute, v_half, least(99, v_score_them + 1), v_actor
    );
  else
    update public.match_live_sessions
    set score_adverse = greatest(0, v_score_them - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

-- Attribue (ou retire) le buteur d'un but déjà enregistré.
create or replace function private.set_match_live_event_scorer(
  p_match_id uuid,
  p_event_id uuid,
  p_scorer_participant_id uuid default null,
  p_is_opponent_own_goal boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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

  update public.match_live_events
  set scorer_participant_id = p_scorer_participant_id,
      is_opponent_own_goal = coalesce(p_is_opponent_own_goal, false)
  where id = p_event_id and match_id = p_match_id;

  update public.match_live_sessions
  set updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

create or replace function public.coach_set_match_live_event_scorer(
  p_match_id uuid,
  p_event_id uuid,
  p_scorer_participant_id uuid default null,
  p_is_opponent_own_goal boolean default false
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.set_match_live_event_scorer(
    p_match_id, p_event_id, p_scorer_participant_id, p_is_opponent_own_goal
  );
$function$;

revoke execute on function private.set_match_live_event_scorer(uuid, uuid, uuid, boolean) from public, anon;
revoke execute on function public.coach_set_match_live_event_scorer(uuid, uuid, uuid, boolean) from public, anon;

grant execute on function private.set_match_live_event_scorer(uuid, uuid, uuid, boolean) to authenticated, service_role;
grant execute on function public.coach_set_match_live_event_scorer(uuid, uuid, uuid, boolean) to authenticated, service_role;
