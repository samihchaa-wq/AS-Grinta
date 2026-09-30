begin;

-- Un seul téléphone peut piloter un Live à la fois.
-- La connexion Supabase (session_id du JWT) distingue deux téléphones même
-- lorsqu'ils utilisent le même compte coach.
alter table public.match_live_sessions
  add column if not exists pilot_profile_id uuid,
  add column if not exists pilot_session_id uuid,
  add column if not exists pilot_heartbeat_at timestamptz;

alter table public.match_live_sessions
  drop constraint if exists match_live_sessions_pilot_profile_id_fkey;
alter table public.match_live_sessions
  add constraint match_live_sessions_pilot_profile_id_fkey
  foreign key (pilot_profile_id)
  references public.profiles(id)
  on delete set null;

comment on column public.match_live_sessions.pilot_profile_id is
  'Profil du coach qui pilote actuellement le Live.';
comment on column public.match_live_sessions.pilot_session_id is
  'Session Auth du téléphone pilote ; distingue deux appareils du même coach.';
comment on column public.match_live_sessions.pilot_heartbeat_at is
  'Dernier signal du téléphone pilote. Le verrou est considéré expiré après 60 secondes.';

create or replace function private.match_live_current_session_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_session_id text;
begin
  v_session_id := nullif((select auth.jwt() ->> 'session_id'), '');
  if v_session_id is null then
    return null;
  end if;
  return v_session_id::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$function$;

revoke all on function private.match_live_current_session_id()
  from public, anon, authenticated;

create or replace function private.require_match_live_pilot(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
  v_pilot_profile_id uuid;
  v_pilot_session_id uuid;
  v_heartbeat_at timestamptz;
begin
  -- Les traitements serveur internes restent possibles avec la clé service.
  if (select auth.role()) = 'service_role' then
    return;
  end if;

  if v_actor is null or v_session_id is null then
    raise exception 'Authentication session required' using errcode = '42501';
  end if;

  select
    session.pilot_profile_id,
    session.pilot_session_id,
    session.pilot_heartbeat_at
  into v_pilot_profile_id, v_pilot_session_id, v_heartbeat_at
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Prends la place de pilote avant de modifier le Live.'
      using errcode = '42501';
  end if;

  if v_pilot_profile_id is distinct from v_actor
     or v_pilot_session_id is distinct from v_session_id
     or v_heartbeat_at is null
     or v_heartbeat_at < now() - interval '60 seconds' then
    raise exception 'Tu ne pilotes pas ce Live.' using errcode = '42501';
  end if;
end;
$function$;

revoke all on function private.require_match_live_pilot(uuid)
  from public, anon, authenticated;

-- État public du Live : ajoute seulement "pilote actif / ce téléphone".
-- L'identifiant de session Auth n'est jamais exposé au client.
-- S'il n'existe pas encore de session Live, une composition n'est renvoyée
-- que si elle a réellement été publiée ; on utilise le dernier instantané
-- publié afin de ne jamais exposer des modifications de brouillon.
create or replace function public.get_match_live_state(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
  v_snapshot jsonb;
  v_publication jsonb;
  v_pilot_profile_id uuid;
  v_pilot_session_id uuid;
  v_heartbeat_at timestamptz;
  v_state public.match_live_state;
  v_pilot_active boolean := false;
  v_pilot_is_me boolean := false;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  v_snapshot := private.match_live_snapshot(p_match_id);

  select
    session.pilot_profile_id,
    session.pilot_session_id,
    session.pilot_heartbeat_at,
    session.state
  into v_pilot_profile_id, v_pilot_session_id, v_heartbeat_at, v_state
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if found then
    v_pilot_active :=
      v_state <> 'finished'
      and v_pilot_profile_id is not null
      and v_pilot_session_id is not null
      and v_heartbeat_at is not null
      and v_heartbeat_at >= now() - interval '60 seconds';
    v_pilot_is_me :=
      v_pilot_active
      and v_actor is not null
      and v_session_id is not null
      and v_pilot_profile_id = v_actor
      and v_pilot_session_id = v_session_id;
  else
    if exists (
      select 1
      from public.match_compositions composition
      where composition.match_id = p_match_id
        and composition.status = 'published'
    ) then
      select publication.snapshot
      into v_publication
      from public.match_composition_publications publication
      where publication.match_id = p_match_id
      order by publication.version desc
      limit 1;

      if v_publication is not null then
        v_snapshot := v_snapshot || jsonb_build_object('lineup', v_publication);
      end if;
    end if;
  end if;

  return v_snapshot || jsonb_build_object(
    'pilot_active', v_pilot_active,
    'pilot_is_me', v_pilot_is_me
  );
end;
$function$;

-- Prendre la place normalement. Si un autre téléphone donne encore signe de
-- vie, l'état est simplement renvoyé : le client affiche alors "Prendre la main".
create or replace function public.claim_match_live_pilot(
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
  v_session_id uuid := private.match_live_current_session_id();
  v_pilot_session_id uuid;
  v_heartbeat_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if v_actor is null or v_session_id is null or not private.is_active_profile() then
    raise exception 'Active authenticated session required' using errcode = '42501';
  end if;
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.pilot_session_id, session.pilot_heartbeat_at
  into v_pilot_session_id, v_heartbeat_at
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    -- Le premier coach qui ouvre Piloter crée l'espace de travail puis prend
    -- immédiatement le verrou. L'appel privé évite le problème circulaire :
    -- l'API publique open_match_live_workspace exige ensuite d'être pilote.
    perform private.open_match_live_workspace(
      p_match_id,
      p_planned_duration_minutes
    );

    select session.pilot_session_id, session.pilot_heartbeat_at
    into v_pilot_session_id, v_heartbeat_at
    from public.match_live_sessions session
    where session.match_id = p_match_id
    for update;
  end if;

  if v_pilot_session_id is not null
     and v_pilot_session_id is distinct from v_session_id
     and v_heartbeat_at is not null
     and v_heartbeat_at >= now() - interval '60 seconds' then
    return public.get_match_live_state(p_match_id);
  end if;

  update public.match_live_sessions
  set pilot_profile_id = v_actor,
      pilot_session_id = v_session_id,
      pilot_heartbeat_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  return public.get_match_live_state(p_match_id);
end;
$function$;

revoke all on function public.claim_match_live_pilot(uuid, integer)
  from public, anon;
grant execute on function public.claim_match_live_pilot(uuid, integer)
  to authenticated, service_role;

-- Prise de main volontaire, après confirmation dans l'application.
create or replace function public.take_over_match_live_pilot(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
begin
  perform private.require_sports_management_enabled();
  if v_actor is null or v_session_id is null or not private.is_active_profile() then
    raise exception 'Active authenticated session required' using errcode = '42501';
  end if;
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  perform 1
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    perform private.open_match_live_workspace(p_match_id, null);
    perform 1
    from public.match_live_sessions session
    where session.match_id = p_match_id
    for update;
  end if;

  update public.match_live_sessions
  set pilot_profile_id = v_actor,
      pilot_session_id = v_session_id,
      pilot_heartbeat_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  return public.get_match_live_state(p_match_id);
end;
$function$;

revoke all on function public.take_over_match_live_pilot(uuid)
  from public, anon;
grant execute on function public.take_over_match_live_pilot(uuid)
  to authenticated, service_role;

create or replace function public.heartbeat_match_live_pilot(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
begin
  if v_actor is null or v_session_id is null or not private.is_active_profile() then
    raise exception 'Active authenticated session required' using errcode = '42501';
  end if;

  update public.match_live_sessions session
  set pilot_heartbeat_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where session.match_id = p_match_id
    and session.pilot_profile_id = v_actor
    and session.pilot_session_id = v_session_id
    and session.pilot_heartbeat_at >= now() - interval '60 seconds';

  return public.get_match_live_state(p_match_id);
end;
$function$;

revoke all on function public.heartbeat_match_live_pilot(uuid)
  from public, anon;
grant execute on function public.heartbeat_match_live_pilot(uuid)
  to authenticated, service_role;

create or replace function public.release_match_live_pilot(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
begin
  if v_actor is null or v_session_id is null or not private.is_active_profile() then
    raise exception 'Active authenticated session required' using errcode = '42501';
  end if;

  update public.match_live_sessions session
  set pilot_profile_id = null,
      pilot_session_id = null,
      pilot_heartbeat_at = null,
      updated_by = v_actor,
      updated_at = now()
  where session.match_id = p_match_id
    and session.pilot_profile_id = v_actor
    and session.pilot_session_id = v_session_id;

  return public.get_match_live_state(p_match_id);
end;
$function$;

revoke all on function public.release_match_live_pilot(uuid)
  from public, anon;
grant execute on function public.release_match_live_pilot(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Toutes les portes d'écriture du Live exigent maintenant ce verrou.
-- Les règles métier existantes restent dans les helpers privés déjà testés.
-- ---------------------------------------------------------------------------

create or replace function public.open_match_live_workspace(
  p_match_id uuid,
  p_planned_duration_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.open_match_live_workspace(p_match_id, p_planned_duration_minutes);
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.confirm_start_match_live(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.confirm_start_match_live(p_match_id, p_reason);
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_set_match_live_clock_state(
  p_match_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.set_match_live_clock_state(p_match_id, p_action, p_reason);
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_adjust_match_live_score(
  p_match_id uuid,
  p_team text,
  p_delta integer,
  p_scorer_participant_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.adjust_match_live_score_idempotent(
    p_match_id,
    p_team,
    p_delta,
    p_scorer_participant_id,
    p_operation_id
  );
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_save_match_live_lineup(
  p_match_id uuid,
  p_entries jsonb,
  p_substitution jsonb,
  p_expected_lineup_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.save_match_live_lineup_versioned(
    p_match_id,
    p_entries,
    p_substitution,
    p_expected_lineup_revision
  );
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_change_match_live_formation(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_expected_lineup_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_formation_code text := nullif(btrim(p_formation_code), '');
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);

  if v_formation_code is null or char_length(v_formation_code) > 32 then
    raise exception 'Invalid formation code' using errcode = '22023';
  end if;

  perform private.save_match_live_lineup_versioned(
    p_match_id,
    p_entries,
    null::jsonb,
    p_expected_lineup_revision
  );

  update public.match_compositions
  set formation_code = v_formation_code,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  if not found then
    raise exception 'Match composition not found' using errcode = 'P0002';
  end if;

  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_delete_match_live_event(
  p_match_id uuid,
  p_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.delete_match_live_event(p_match_id, p_event_id);
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_set_match_live_event_scorer(
  p_match_id uuid,
  p_event_id uuid,
  p_scorer_participant_id uuid default null,
  p_is_opponent_own_goal boolean default false,
  p_assist_participant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.set_match_live_event_scorer(
    p_match_id,
    p_event_id,
    p_scorer_participant_id,
    p_is_opponent_own_goal,
    p_assist_participant_id
  );
  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_end_match_live(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid := private.match_live_current_session_id();
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.end_match_live(p_match_id, p_reason);

  update public.match_live_sessions session
  set pilot_profile_id = null,
      pilot_session_id = null,
      pilot_heartbeat_at = null,
      updated_by = v_actor,
      updated_at = now()
  where session.match_id = p_match_id
    and session.pilot_session_id = v_session_id;

  return public.get_match_live_state(p_match_id);
end;
$function$;

create or replace function public.coach_restart_match_live_session(
  p_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);
  perform private.restart_match_live_session(p_match_id, p_reason);
  return public.get_match_live_state(p_match_id);
end;
$function$;

-- L'ajout de joueurs garde le comportement existant (notamment le compteur de
-- banc pour un joueur ajouté en cours de match), avec le verrou pilote en plus.
create or replace function public.coach_add_match_live_players(
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
  v_state public.match_live_state;
  v_before_selected uuid[];
  v_added_bench_baseline jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  perform private.require_match_live_pilot(p_match_id);

  select session.state
  into v_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  select coalesce(array_agg(entry.participant_id), array[]::uuid[])
  into v_before_selected
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone in ('field', 'bench');

  perform private.add_match_live_players(p_match_id, p_players, p_reason);

  if v_state in ('running', 'paused', 'halftime') then
    select coalesce(
      jsonb_object_agg(entry.participant_id::text, 'bench'::text),
      '{}'::jsonb
    )
    into v_added_bench_baseline
    from public.match_composition_entries entry
    join public.match_live_sessions session on session.match_id = entry.match_id
    where entry.match_id = p_match_id
      and entry.zone = 'bench'
      and not (entry.participant_id = any(v_before_selected))
      and not (
        coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
        ? entry.participant_id::text
      );

    if v_added_bench_baseline <> '{}'::jsonb then
      update public.match_live_sessions session
      set starting_lineup_snapshot =
            coalesce(session.starting_lineup_snapshot, '{}'::jsonb)
            || v_added_bench_baseline,
          updated_at = now()
      where session.match_id = p_match_id;
    end if;
  end if;

  return public.get_match_live_state(p_match_id);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Après-match : created_at permet de garder deux validations distinctes même
-- lorsqu'elles ont eu lieu dans la même minute.
-- ---------------------------------------------------------------------------

create or replace function private.get_match_live_timeline(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
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
      'created_at', event.created_at,
      'scorer_name', case
        when scorer_guest.id is not null then btrim(scorer_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(scorer_profile.surnom), ''),
          nullif(btrim(scorer_profile.first_name), ''),
          nullif(btrim(scorer_player.first_name), '')
        )
      end,
      'assist_name', case
        when assist_guest.id is not null then btrim(assist_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(assist_profile.surnom), ''),
          nullif(btrim(assist_profile.first_name), ''),
          nullif(btrim(assist_player.first_name), '')
        )
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_name', case
        when in_guest.id is not null then btrim(in_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(in_profile.surnom), ''),
          nullif(btrim(in_profile.first_name), ''),
          nullif(btrim(in_player.first_name), '')
        )
      end,
      'player_out_name', case
        when out_guest.id is not null then btrim(out_guest.first_name) || ' (Invité)'
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

-- ---------------------------------------------------------------------------
-- Notification de coup d'envoi : même circuit que les buts et la fin.
-- ---------------------------------------------------------------------------

alter table private.match_live_notification_events
  drop constraint if exists match_live_notification_events_kind_check;
alter table private.match_live_notification_events
  add constraint match_live_notification_events_kind_check
  check (kind in ('kickoff', 'goal_us', 'goal_them', 'full_time'));

create unique index if not exists match_live_notification_kickoff_once
  on private.match_live_notification_events(match_id)
  where kind = 'kickoff';

create or replace function private.queue_match_live_kickoff_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_type text;
  v_notification_id uuid;
  v_target_count integer;
begin
  if new.state::text <> 'running'
     or old.state::text <> 'not_started' then
    return new;
  end if;

  select match.match_type
  into v_match_type
  from public.matches match
  where match.id = new.match_id;

  if v_match_type not in ('championnat', 'amical') then
    return new;
  end if;

  if not exists (
    select 1
    from public.match_live_notification_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where subscription.match_id = new.match_id
      and subscription.completed_at is null
      and profile.status = 'active'
  ) then
    return new;
  end if;

  insert into private.match_live_notification_events(
    match_id,
    kind,
    due_at,
    score_as_grinta,
    score_adverse
  )
  values (
    new.match_id,
    'kickoff',
    now(),
    new.score_as_grinta,
    new.score_adverse
  )
  on conflict (match_id) where kind = 'kickoff'
  do nothing
  returning id into v_notification_id;

  if v_notification_id is null then
    return new;
  end if;

  v_target_count := private.snapshot_match_live_notification_targets(
    v_notification_id,
    new.match_id
  );

  if v_target_count = 0 then
    update private.match_live_notification_events event
    set state = 'cancelled', completed_at = now()
    where event.id = v_notification_id;
    return new;
  end if;

  perform private.request_match_live_notification_delivery(v_notification_id);
  return new;
end;
$function$;

drop trigger if exists match_live_kickoff_notification
  on public.match_live_sessions;
create trigger match_live_kickoff_notification
after update of state on public.match_live_sessions
for each row
execute function private.queue_match_live_kickoff_notification();

create or replace function public.internal_claim_match_live_notification(
  p_notification_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event private.match_live_notification_events%rowtype;
  v_match record;
  v_home_name text;
  v_away_name text;
  v_home_score integer;
  v_away_score integer;
  v_scoreline text;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_log_kind text;
begin
  update private.match_live_notification_events event
  set state = 'dispatching', claimed_at = now()
  where event.id = p_notification_id
    and event.state = 'pending'
    and event.due_at <= now()
  returning event.* into v_event;

  if not found then
    return jsonb_build_object('claimed', false);
  end if;

  select
    match.location,
    coalesce(nullif(btrim(opponent.name), ''), 'Adversaire') as opponent_name
  into v_match
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = v_event.match_id;

  if not found then
    update private.match_live_notification_events event
    set state = 'cancelled', completed_at = now()
    where event.id = v_event.id;
    return jsonb_build_object('claimed', false);
  end if;

  if v_match.location = 'domicile' then
    v_home_name := 'AS Grinta';
    v_away_name := v_match.opponent_name;
    v_home_score := v_event.score_as_grinta;
    v_away_score := v_event.score_adverse;
  else
    v_home_name := v_match.opponent_name;
    v_away_name := 'AS Grinta';
    v_home_score := v_event.score_adverse;
    v_away_score := v_event.score_as_grinta;
  end if;

  v_scoreline := format('%s %s–%s %s', v_home_name, v_home_score, v_away_score, v_away_name);

  if v_event.kind = 'kickoff' then
    v_log_kind := 'live_kickoff';
    v_payload := jsonb_build_object(
      'title', '⚽ Le match commence',
      'body', format('%s – %s', v_home_name, v_away_name),
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-kickoff'
    );
  elsif v_event.kind = 'goal_us' then
    v_log_kind := 'live_goal_us';
    v_payload := jsonb_build_object(
      'title', '⚽ But !',
      'body', case
        when nullif(btrim(v_event.scorer_name), '') is not null
          then format('But de %s ! %s', v_event.scorer_name, v_scoreline)
        else format('But pour AS Grinta ! %s', v_scoreline)
      end,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-goal-' || v_event.id
    );
  elsif v_event.kind = 'goal_them' then
    v_log_kind := 'live_goal_them';
    v_payload := jsonb_build_object(
      'title', format('⚽ But pour %s', v_match.opponent_name),
      'body', v_scoreline,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-goal-' || v_event.id
    );
  else
    v_log_kind := 'live_full_time';
    v_payload := jsonb_build_object(
      'title', '🏁 Fin du match',
      'body', v_scoreline,
      'url', 'matches/' || v_event.match_id || '/lineup?section=live',
      'tag', 'live-' || v_event.match_id || '-full-time'
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', push.profile_id,
        'endpoint', push.endpoint,
        'p256dh', push.p256dh,
        'auth', push.auth
      ) order by push.profile_id, push.endpoint
    ),
    '[]'::jsonb
  )
  into v_subscriptions
  from private.match_live_notification_event_targets target
  join public.match_live_notification_subscriptions subscription
    on subscription.match_id = v_event.match_id
   and subscription.profile_id = target.profile_id
   and subscription.completed_at is null
  join public.profiles profile
    on profile.id = target.profile_id
   and profile.status = 'active'
  join public.push_subscriptions push
    on push.profile_id = target.profile_id
  where target.notification_id = v_event.id;

  return jsonb_build_object(
    'claimed', true,
    'notification_id', v_event.id,
    'match_id', v_event.match_id,
    'kind', v_log_kind,
    'payload', v_payload,
    'subscriptions', v_subscriptions
  );
end;
$function$;

alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;
alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check
  check (
    kind = any (array[
      'availability_open'::text,
      'availability_j3'::text,
      'availability_j1'::text,
      'availability_manual'::text,
      'motm_open'::text,
      'prediction_j5'::text,
      'match_cancelled'::text,
      'match_rescheduled_date'::text,
      'match_rescheduled_time'::text,
      'convocation_promoted'::text,
      'live_kickoff'::text,
      'live_goal_us'::text,
      'live_goal_them'::text,
      'live_full_time'::text
    ])
  );

commit;
