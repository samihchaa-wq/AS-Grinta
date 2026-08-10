


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."match_live_state" AS ENUM (
    'not_started',
    'running',
    'paused',
    'halftime',
    'finished'
);


ALTER TYPE "public"."match_live_state" OWNER TO "postgres";


CREATE TYPE "public"."sport_availability_state" AS ENUM (
    'pending',
    'open',
    'closed'
);


ALTER TYPE "public"."sport_availability_state" OWNER TO "postgres";


CREATE TYPE "public"."sport_availability_status" AS ENUM (
    'no_response',
    'available',
    'absent',
    'not_applicable'
);


ALTER TYPE "public"."sport_availability_status" OWNER TO "postgres";


CREATE TYPE "public"."sport_composition_state" AS ENUM (
    'none',
    'draft',
    'published',
    'updated',
    'closed'
);


ALTER TYPE "public"."sport_composition_state" OWNER TO "postgres";


CREATE TYPE "public"."sport_composition_zone" AS ENUM (
    'available',
    'field',
    'bench',
    'not_selected'
);


ALTER TYPE "public"."sport_composition_zone" OWNER TO "postgres";


CREATE TYPE "public"."sport_convocation_state" AS ENUM (
    'draft',
    'published',
    'closed'
);


ALTER TYPE "public"."sport_convocation_state" OWNER TO "postgres";


CREATE TYPE "public"."sport_convocation_status" AS ENUM (
    'not_applicable',
    'convoked',
    'not_convoked'
);


ALTER TYPE "public"."sport_convocation_status" OWNER TO "postgres";


CREATE TYPE "public"."sport_final_presence_status" AS ENUM (
    'pending',
    'present',
    'actual_absent'
);


ALTER TYPE "public"."sport_final_presence_status" OWNER TO "postgres";


CREATE TYPE "public"."sport_presence_state" AS ENUM (
    'pending',
    'confirmed'
);


ALTER TYPE "public"."sport_presence_state" OWNER TO "postgres";


CREATE TYPE "public"."sport_selection_status" AS ENUM (
    'undecided',
    'starter',
    'substitute',
    'not_selected'
);


ALTER TYPE "public"."sport_selection_status" OWNER TO "postgres";


CREATE TYPE "public"."sport_vote_state" AS ENUM (
    'unavailable',
    'draft',
    'open',
    'closed',
    'cancelled'
);


ALTER TYPE "public"."sport_vote_state" OWNER TO "postgres";


CREATE TYPE "public"."sport_waitlist_turn_state" AS ENUM (
    'not_applicable',
    'pending',
    'consumed',
    'waived'
);


ALTER TYPE "public"."sport_waitlist_turn_state" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid" DEFAULT NULL::"uuid", "p_first_name" "text" DEFAULT NULL::"text", "p_last_name" "text" DEFAULT NULL::"text", "p_is_goalkeeper" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_first_name text := nullif(btrim(p_first_name), '');
  v_last_name text := nullif(btrim(p_last_name), '');
  v_reason text := nullif(btrim(p_reason), '');
  v_guest public.guest_players%rowtype;
  v_participant_id uuid;
  v_was_eligible boolean;
  v_created boolean := false;
  v_reactivated boolean := false;
  v_match_status text;
  v_kickoff_at timestamptz;
  v_sort_order integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at
  into v_match_status, v_kickoff_at
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Guests can only be managed before kickoff' using errcode = '22023';
  end if;

  if p_guest_player_id is not null then
    select guest.* into v_guest
    from public.guest_players guest
    where guest.id = p_guest_player_id
    for update;

    if not found then
      raise exception 'Guest player not found' using errcode = 'P0002';
    end if;
    if not v_guest.is_reusable then
      raise exception 'Archived guest must be restored before reuse' using errcode = '22023';
    end if;
  else
    if v_first_name is null then
      raise exception 'Guest first name is required' using errcode = '22023';
    end if;
    if char_length(v_first_name) > 80
      or (v_last_name is not null and char_length(v_last_name) > 80) then
      raise exception 'Guest name cannot exceed 80 characters per field'
        using errcode = '22023';
    end if;

    select guest.* into v_guest
    from public.guest_players guest
    where guest.is_reusable
      and lower(btrim(guest.first_name)) = lower(v_first_name)
      and lower(coalesce(btrim(guest.last_name), '')) =
          lower(coalesce(v_last_name, ''))
      and guest.is_goalkeeper = coalesce(p_is_goalkeeper, false)
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
        coalesce(p_is_goalkeeper, false),
        v_actor,
        v_actor
      )
      returning * into v_guest;
      v_created := true;
    end if;
  end if;

  select participant.id, participant.is_eligible
  into v_participant_id, v_was_eligible
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.guest_player_id = v_guest.id
  for update;

  if found then
    v_reactivated := not v_was_eligible;
    update public.match_sport_participants participant
    set is_eligible = true,
        availability_status = 'not_applicable',
        availability_comment_private = null,
        convocation_status = 'convoked',
        convocation_manual_override = true,
        waitlist_position_snapshot = null,
        waitlist_recommended_not_convoked = false,
        waitlist_turn_should_consume = false,
        waitlist_turn_state = 'not_applicable',
        selection_status = case
          when participant.is_eligible then participant.selection_status
          else 'undecided'::public.sport_selection_status
        end,
        updated_at = now()
    where participant.id = v_participant_id;
  else
    insert into public.match_sport_participants (
      match_id,
      guest_player_id,
      is_eligible,
      availability_status,
      convocation_status,
      convocation_manual_override,
      waitlist_turn_state
    ) values (
      p_match_id,
      v_guest.id,
      true,
      'not_applicable',
      'convoked',
      true,
      'not_applicable'
    )
    returning id into v_participant_id;
    v_reactivated := true;
  end if;

  if exists (
    select 1 from public.match_compositions composition
    where composition.match_id = p_match_id
  ) then
    select coalesce(max(entry.sort_order), -1) + 1
    into v_sort_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.zone = 'available';

    insert into public.match_composition_entries (
      match_id,
      participant_id,
      zone,
      sort_order
    ) values (
      p_match_id,
      v_participant_id,
      'available',
      coalesce(v_sort_order, 0)
    )
    on conflict (match_id, participant_id) do nothing;

    update public.match_compositions composition
    set has_unpublished_changes = true,
        last_modified_at = now(),
        last_modified_by = v_actor
    where composition.match_id = p_match_id;
  end if;

  if v_reactivated then
    insert into public.match_sport_participant_events (
      participant_id,
      match_id,
      event_type,
      old_value,
      new_value,
      actor_profile_id,
      actor_kind
    ) values (
      v_participant_id,
      p_match_id,
      'guest_added',
      jsonb_build_object('eligible', false),
      jsonb_build_object(
        'eligible', true,
        'guest_player_id', v_guest.id,
        'created_catalog_entry', v_created
      ),
      v_actor,
      'staff'
    );
  end if;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    case
      when v_created then 'create_and_add_guest'
      when v_reactivated then 'add_guest'
      else 'reuse_existing_match_guest'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'guest_player_id', v_guest.id,
      'participant_id', v_participant_id,
      'created_catalog_entry', v_created,
      'reactivated', v_reactivated
    )
  );

  return jsonb_build_object(
    'guest_player_id', v_guest.id,
    'participant_id', v_participant_id,
    'created_catalog_entry', v_created,
    'match_guests', private.get_match_guests(p_match_id)
  );
end;
$$;


ALTER FUNCTION "private"."add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
  v_last_event_id uuid;
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
    -- Le « − » retire le dernier but de notre équipe déjà saisi, plutôt que
    -- de décrémenter un compteur déconnecté du journal : le buteur retiré
    -- disparaît alors correctement de « Faits du match ». Comme c'est le
    -- dernier but de ce type par construction (tri décroissant), aucun
    -- autre événement du même type n'a besoin d'être renuméroté.
    select event.id into v_last_event_id
    from public.match_live_events event
    where event.match_id = p_match_id and event.event_type = 'goal_us'
    order by event.created_at desc
    limit 1
    for update;

    if v_last_event_id is not null then
      delete from public.match_live_events where id = v_last_event_id;
    end if;

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
    select event.id into v_last_event_id
    from public.match_live_events event
    where event.match_id = p_match_id and event.event_type = 'goal_them'
    order by event.created_at desc
    limit 1
    for update;

    if v_last_event_id is not null then
      delete from public.match_live_events where id = v_last_event_id;
    end if;

    update public.match_live_sessions
    set score_adverse = greatest(0, v_score_them - 1), updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_version integer;
  v_state public.sport_vote_state;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select election.finalization_version, election.state
  into v_version, v_state
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;
  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;

  if v_state in ('draft', 'open') then
    raise exception 'Le vote HDM se ferme automatiquement exactement 24 h après la validation du compte rendu.'
      using errcode = '22023';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  update public.match_sport_motm_elections
  set state = 'cancelled', closes_at = null, closed_at = null,
      total_votes = 0, max_votes = 0, updated_at = now()
  where match_id = p_match_id;
  update public.match_sport_workflows
  set vote_state = 'cancelled', updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'cancel_motm_vote', v_actor, v_reason,
    jsonb_build_object('finalization_version', v_version)
  );

  return jsonb_build_object('match_id', p_match_id, 'state', 'cancelled');
end;
$$;


ALTER FUNCTION "private"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_version integer;
  v_closes_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select election.finalization_version, election.closes_at
  into v_version, v_closes_at
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
    and election.state = 'open'
  for update;

  if not found then
    raise exception 'Only an open MOTM vote can be closed' using errcode = '22023';
  end if;
  if v_closes_at is null then
    raise exception 'MOTM close deadline is missing' using errcode = '22023';
  end if;
  if now() < v_closes_at then
    raise exception 'MOTM vote must remain open until its 24-hour deadline'
      using errcode = '22023';
  end if;

  if not private.close_match_motm_election(p_match_id, false) then
    raise exception 'MOTM vote could not be closed' using errcode = '22023';
  end if;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'close_motm_vote_manual',
    v_actor,
    v_reason,
    jsonb_build_object(
      'finalization_version', v_version,
      'closes_at', v_closes_at
    )
  );

  return private.get_admin_match_motm_dashboard(p_match_id);
end;
$$;


ALTER FUNCTION "private"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_has_ballot boolean;
  v_version integer;
  v_state public.sport_vote_state;
  v_closes_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.matches match where match.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select coalesce(
    (
      select finalization.validated_at + interval '24 hours'
      from public.match_sport_finalizations finalization
      where finalization.match_id = p_match_id
    ),
    (
      select match.result_validated_at + interval '24 hours'
      from public.matches match
      where match.id = p_match_id
    )
  ) into v_closes_at;

  if v_closes_at is null or now() >= v_closes_at then
    raise exception 'MOTM vote cannot be restarted after the post-match window closes'
      using errcode = '22023';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_version := private.match_motm_anchor_version(p_match_id);
  v_state := (case when v_has_ballot then 'open' else 'cancelled' end)::public.sport_vote_state;

  insert into public.match_sport_motm_elections as election (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then now() else null end,
    case when v_has_ballot then v_closes_at else null end,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do update
  set finalization_version = excluded.finalization_version,
      state = excluded.state,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      closed_at = null,
      total_votes = 0,
      max_votes = 0,
      updated_at = now();

  update public.match_sport_workflows
  set vote_state = v_state, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_motm_vote', v_actor, v_reason,
    jsonb_build_object(
      'anchor_version', v_version,
      'state', v_state,
      'closes_at', v_closes_at
    )
  );

  return jsonb_build_object(
    'match_id', p_match_id,
    'state', v_state,
    'closes_at', case when v_has_ballot then v_closes_at else null end
  );
end;
$$;


ALTER FUNCTION "private"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."apply_coach_flag_to_participants"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.is_coach is distinct from old.is_coach then
    update public.match_sport_participants participant
    set is_eligible = not new.is_coach,
        updated_at = now()
    from public.matches match
    where participant.season_player_id = new.id
      and participant.match_id = match.id
      and match.status = 'a_venir';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."apply_coach_flag_to_participants"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."assert_match_postgame_correction_open"("p_match_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
  v_closes_at timestamptz;
begin
  select match.status::text,
         private.match_postgame_correction_closes_at(match.id)
  into v_status, v_closes_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_status = 'archive' then
    raise exception 'La fenêtre de correction du match est fermée.'
      using errcode = '22023';
  end if;

  if v_status = 'termine'
     and (v_closes_at is null or now() >= v_closes_at) then
    raise exception 'La fenêtre de correction de 24 h est fermée.'
      using errcode = '22023';
  end if;
end;
$$;


ALTER FUNCTION "private"."assert_match_postgame_correction_open"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."assert_match_postgame_correction_open"("p_match_id" "uuid") IS 'Refuse toute correction post-match à partir de la clôture du vote HDM, sans prolonger la fenêtre lors des corrections.';



CREATE OR REPLACE FUNCTION "private"."can_read_sport_participant"("p_participant_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.is_feature_enabled('sports_management')
    and private.is_active_profile()
    and (
      private.is_admin()
      or exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.id = p_participant_id
          and player.profile_id = (select auth.uid())
      )
    );
$$;


ALTER FUNCTION "private"."can_read_sport_participant"("p_participant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."can_read_sport_workflow"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.is_feature_enabled('sports_management')
    and private.is_active_profile()
    and (
      private.is_admin()
      or exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and player.profile_id = (select auth.uid())
      )
    );
$$;


ALTER FUNCTION "private"."can_read_sport_workflow"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."capture_player_alias"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_alias text;
begin
  if new.player_id is null then
    return new;
  end if;

  case tg_table_name
    when 'profiles' then
      v_alias := btrim(concat_ws(' ', new.first_name, nullif(new.last_name, '')));
    when 'season_players' then
      v_alias := btrim(concat_ws(' ', new.first_name, nullif(new.last_name, '')));
    when 'guest_players' then
      v_alias := btrim(concat_ws(' ', new.first_name, nullif(new.last_name, '')));
    when 'historical_player_statistics' then
      v_alias := btrim(new.player_name);
    else
      return new;
  end case;

  if coalesce(v_alias, '') <> '' then
    insert into public.player_aliases(player_id, alias)
    values (new.player_id, v_alias)
    on conflict do nothing;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."capture_player_alias"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_election public.match_sport_motm_elections%rowtype;
  v_voter_participant_id uuid;
  v_candidate_profile_id uuid;
  v_candidate_ok boolean;
  v_cast_at timestamptz := now();
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  perform private.ensure_match_motm_election(p_match_id);
  perform private.transition_match_motm_election(p_match_id);

  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;

  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;
  if v_election.state <> 'open'
     or v_election.opens_at is null
     or v_cast_at < v_election.opens_at
     or v_cast_at >= v_election.closes_at then
    raise exception 'MOTM vote is closed' using errcode = '22023';
  end if;

  select participant.id into v_voter_participant_id
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where profile.id = v_actor
    and profile.status = 'active'
  order by participant.id
  limit 1;

  if v_voter_participant_id is null then
    raise exception 'Only a registered player from the lineup can vote'
      using errcode = '42501';
  end if;

  select true, candidate_player.profile_id
  into v_candidate_ok, v_candidate_profile_id
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  left join public.season_players candidate_player
    on candidate_player.id = participant.season_player_id
  where participant.id = p_candidate_participant_id;

  if not coalesce(v_candidate_ok, false) then
    raise exception 'Candidate must be part of the published lineup' using errcode = '22023';
  end if;
  if v_candidate_profile_id = v_actor then
    raise exception 'A player cannot vote for himself' using errcode = '22023';
  end if;

  begin
    insert into public.match_sport_motm_votes(
      match_id, voter_profile_id, candidate_participant_id,
      finalization_version, cast_at
    ) values (
      p_match_id, v_actor, p_candidate_participant_id,
      v_election.finalization_version, v_cast_at
    );
  exception
    when unique_violation then
      raise exception 'MOTM vote is immutable and has already been cast'
        using errcode = '23505';
  end;

  update public.match_sport_motm_elections
  set total_votes = total_votes + 1, updated_at = now()
  where match_id = p_match_id;

  return jsonb_build_object(
    'accepted', true,
    'cast_at', v_cast_at,
    'closes_at', v_election.closes_at
  );
end;
$$;


ALTER FUNCTION "private"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."close_due_match_motm_elections"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row record;
  v_processed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state in ('draft', 'open')
    order by election.closes_at nulls last, election.match_id
    for update skip locked
  loop
    perform private.transition_match_motm_election(v_row.match_id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$$;


ALTER FUNCTION "private"."close_due_match_motm_elections"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."close_match_motm_election"("p_match_id" "uuid", "p_require_due" boolean DEFAULT true) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_election public.match_sport_motm_elections%rowtype;
  v_total integer := 0;
  v_max integer := 0;
begin
  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;

  if not found then
    return false;
  end if;
  if v_election.state not in ('open', 'draft') then
    return v_election.state = 'closed';
  end if;
  if p_require_due
     and (v_election.closes_at is null or now() < v_election.closes_at) then
    return false;
  end if;

  delete from public.match_sport_motm_results where match_id = p_match_id;

  insert into public.match_sport_motm_results(
    match_id, participant_id, finalization_version, votes_count, is_winner
  )
  select
    participant.match_id,
    participant.id,
    v_election.finalization_version,
    count(vote.voter_profile_id)::integer,
    false
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  left join public.match_sport_motm_votes vote
    on vote.match_id = participant.match_id
   and vote.candidate_participant_id = participant.id
  group by participant.match_id, participant.id;

  select coalesce(sum(result.votes_count), 0), coalesce(max(result.votes_count), 0)
  into v_total, v_max
  from public.match_sport_motm_results result
  where result.match_id = p_match_id;

  update public.match_sport_motm_results
  set is_winner = v_max > 0 and votes_count = v_max,
      computed_at = now()
  where match_id = p_match_id;

  delete from public.match_man_of_match where match_id = p_match_id;
  insert into public.match_man_of_match(match_id, season_player_id)
  select result.match_id, participant.season_player_id
  from public.match_sport_motm_results result
  join public.match_sport_participants participant
    on participant.id = result.participant_id
   and participant.match_id = result.match_id
  where result.match_id = p_match_id
    and result.is_winner
    and participant.season_player_id is not null
  on conflict do nothing;

  update public.match_sport_motm_elections
  set state = 'closed',
      opens_at = coalesce(opens_at, v_election.closes_at - interval '24 hours'),
      closed_at = now(),
      total_votes = v_total,
      max_votes = v_max,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_workflows
  set vote_state = 'closed', updated_at = now()
  where match_id = p_match_id;

  return true;
end;
$$;


ALTER FUNCTION "private"."close_match_motm_election"("p_match_id" "uuid", "p_require_due" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."composition_snapshot"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'match_id', composition.match_id,
    'formation_code', composition.formation_code,
    'status', composition.status,
    'version', composition.version,
    'has_unpublished_changes', composition.has_unpublished_changes,
    'squad_size_exception_approved', composition.squad_size_exception_approved,
    'published_at', composition.published_at,
    'last_modified_at', composition.last_modified_at,
    'field_count', count(*) filter (where entry.zone = 'field'),
    'bench_count', count(*) filter (where entry.zone = 'bench'),
    'not_selected_count', count(*) filter (where entry.zone = 'not_selected'),
    'available_count', count(*) filter (where entry.zone = 'available'),
    'has_goalkeeper_warning', not coalesce(bool_or(
      entry.zone = 'field'
      and coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
    ), false),
    'entries', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'participant_id', participant.id,
          'season_player_id', participant.season_player_id,
          'guest_player_id', participant.guest_player_id,
          'display_name', case
            when guest.id is not null then
              btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
            else coalesce(
              nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
              nullif(btrim(player.first_name), ''),
              btrim(concat_ws(' ', player.first_name, player.last_name))
            )
          end,
          'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
          'is_guest', guest.id is not null,
          'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
          'zone', entry.zone,
          'x', entry.x,
          'y', entry.y,
          'slot_label', entry.slot_label,
          'sort_order', entry.sort_order,
          'availability_status', participant.availability_status,
          'convocation_status', participant.convocation_status,
          'selection_status', participant.selection_status
        ) order by
          case entry.zone
            when 'field' then 1
            when 'bench' then 2
            when 'available' then 3
            else 4
          end,
          entry.sort_order,
          lower(coalesce(profile.surnom, profile.first_name, player.first_name, guest.first_name)),
          participant.id
      ) filter (where entry.participant_id is not null),
      '[]'::jsonb
    )
  ) into v_result
  from public.match_compositions composition
  left join public.match_composition_entries entry
    on entry.match_id = composition.match_id
  left join public.match_sport_participants participant
    on participant.id = entry.participant_id
   and participant.match_id = entry.match_id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  where composition.match_id = p_match_id
  group by composition.match_id;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."composition_snapshot"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_cutoff timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit is null or p_squad_size_limit < 1 or p_squad_size_limit > 30 then
    raise exception 'Squad size limit must be between 1 and 30' using errcode = '22023';
  end if;

  perform private.sync_match_sport_workflow(p_match_id);

  select match.season_id, match.kickoff_at
  into v_season_id, v_kickoff_at
  from public.matches match
  where match.id = p_match_id
  for update;

  v_cutoff := (
    (
      (v_kickoff_at at time zone 'Europe/Paris')::date - 1
    ) + time '12:00'
  ) at time zone 'Europe/Paris';

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      late_withdrawal_cutoff_at = v_cutoff,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  perform private.ensure_sport_waitlist(v_season_id, v_actor);
  return private.recompute_match_convocations_internal(p_match_id, false);
end;
$$;


ALTER FUNCTION "private"."configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_kickoff_at timestamptz;
  v_field_count integer;
  v_composition_version integer;
  v_snapshot_map jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, match.kickoff_at
  into v_state, v_kickoff_at
  from public.match_live_sessions session
  join public.matches match on match.id = session.match_id
  where session.match_id = p_match_id
  for update of session;

  if not found then
    raise exception 'Open the live workspace before starting the match'
      using errcode = '22023';
  end if;
  if v_state <> 'not_started' then
    raise exception 'The match has already been started' using errcode = '22023';
  end if;
  if v_kickoff_at is null
     or now() < v_kickoff_at - interval '15 minutes' then
    raise exception 'Le Live ouvre 15 minutes avant le coup d’envoi.'
      using errcode = '22023';
  end if;

  select count(*) filter (where zone = 'field') into v_field_count
  from public.match_composition_entries
  where match_id = p_match_id;
  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters'
      using errcode = '22023';
  end if;

  select composition.version into v_composition_version
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  select coalesce(
    jsonb_object_agg(entry.participant_id::text, entry.zone),
    '{}'::jsonb
  )
  into v_snapshot_map
  from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.zone in ('field', 'bench');

  update public.match_live_sessions
  set state = 'running',
      started_at = now(),
      running_since = now(),
      elapsed_seconds = 0,
      half = 1,
      starting_composition_version = v_composition_version,
      starting_lineup_snapshot = v_snapshot_map,
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
    'start_match_live',
    v_actor,
    v_reason,
    jsonb_build_object('field_count', v_field_count)
  );

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."create_match_with_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_match_id := public.create_match_with_odds(
    p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_win, p_draw, p_loss
  );
  perform private.configure_match_sport_workflow(v_match_id, p_squad_size_limit);
  return v_match_id;
end;
$$;


ALTER FUNCTION "private"."create_match_with_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."create_player_identity"("p_display_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_player_id uuid;
  v_display_name text := nullif(btrim(p_display_name), '');
begin
  if v_display_name is null then
    raise exception 'Player display name is required' using errcode = '22023';
  end if;

  insert into public.players(display_name)
  values (v_display_name)
  returning id into v_player_id;

  insert into public.player_aliases(player_id, alias)
  values (v_player_id, v_display_name)
  on conflict do nothing;

  return v_player_id;
end;
$$;


ALTER FUNCTION "private"."create_player_identity"("p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_finalized boolean;
  v_expected_count integer;
  v_input_count integer;
  v_field_count integer;
  v_selected_count integer;
  v_present_count integer;
  v_invalid_count integer;
  v_exception_used boolean;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Composition entries must be a JSON array' using errcode = '22023';
  end if;
  if v_formation is not null and char_length(v_formation) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select
    match.status::text,
    match.kickoff_at,
    workflow.squad_size_limit,
    finalization.match_id is not null
  into v_match_status, v_kickoff_at, v_squad_limit, v_finalized
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('termine', 'archive') or now() < v_kickoff_at then
    raise exception 'Post-match composition requires a finished match'
      using errcode = '22023';
  end if;
  if not v_finalized then
    raise exception 'The match must be finalized before creating its composition'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from public.match_compositions composition
    where composition.match_id = p_match_id
  ) or exists (
    select 1 from public.match_composition_publications publication
    where publication.match_id = p_match_id
  ) then
    raise exception 'A composition already exists for this match'
      using errcode = '55000';
  end if;

  create temporary table if not exists pg_temp.postmatch_composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.postmatch_composition_input;

  begin
    insert into pg_temp.postmatch_composition_input(
      participant_id, zone, x, y, slot_label, sort_order
    )
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a composition'
        using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count
  from pg_temp.postmatch_composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.is_eligible
      or participant.final_presence_status <> 'pending'
    );
  if v_input_count <> v_expected_count then
    raise exception 'Every finalized participant must appear exactly once'
      using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.postmatch_composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and (
     participant.is_eligible
     or participant.final_presence_status <> 'pending'
   )
  where participant.id is null
     or input.zone = 'available'
     or (
       input.zone = 'field'
       and (
         input.x is null or input.y is null
         or input.x < 0 or input.x > 1
         or input.y < 0 or input.y > 1
       )
     )
     or (input.zone <> 'field' and (input.x is not null or input.y is not null))
     or (
       participant.final_presence_status = 'present'
       and input.zone not in ('field', 'bench')
     )
     or (
       participant.final_presence_status <> 'present'
       and input.zone <> 'not_selected'
     );
  if v_invalid_count > 0 then
    raise exception 'Composition must contain only actual present players'
      using errcode = '22023';
  end if;

  select
    count(*) filter (where input.zone = 'field'),
    count(*) filter (where input.zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.postmatch_composition_input input;
  select count(*) into v_present_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present';

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_selected_count <> v_present_count then
    raise exception 'Every actual present player must be on the field or bench'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  perform set_config(
    'as_grinta.allow_postmatch_composition_write',
    'on',
    true
  );

  insert into public.match_compositions(
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, published_at, published_by,
    last_modified_at, last_modified_by, closed_at
  ) values (
    p_match_id, v_formation, 'published', 1, false,
    v_exception_used, now(), v_actor, now(), v_actor, now()
  );

  insert into public.match_composition_entries(
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.postmatch_composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      final_selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.postmatch_composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = 'published',
      composition_version = 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  update public.match_sport_finalizations finalization
  set composition_version = 1,
      updated_at = now()
  where finalization.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', 'postmatch'
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot,
    publication_kind, published_by
  ) values (
    p_match_id, 1, v_formation, v_snapshot, 'postmatch', v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'publish_postmatch_composition',
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', 1,
      'publication_kind', 'postmatch',
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'present_count', v_present_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.get_published_match_composition(p_match_id);
end;
$$;


ALTER FUNCTION "private"."create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."create_sport_availability_notification"("p_match_id" "uuid", "p_participant_id" "uuid", "p_profile_id" "uuid", "p_kind" "text", "p_source" "text", "p_scheduled_for" timestamp with time zone, "p_requested_by" "uuid", "p_reason" "text") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_event_id bigint;
begin
  insert into public.sport_availability_notification_events (
    match_id,
    participant_id,
    profile_id,
    kind,
    source,
    scheduled_for,
    requested_by,
    reason
  ) values (
    p_match_id,
    p_participant_id,
    p_profile_id,
    p_kind,
    p_source,
    p_scheduled_for,
    p_requested_by,
    nullif(trim(p_reason), '')
  )
  on conflict do nothing
  returning id into v_event_id;

  if v_event_id is not null then
    perform private.dispatch_sport_notification_event(v_event_id);
  end if;

  return v_event_id;
end;
$$;


ALTER FUNCTION "private"."create_sport_availability_notification"("p_match_id" "uuid", "p_participant_id" "uuid", "p_profile_id" "uuid", "p_kind" "text", "p_source" "text", "p_scheduled_for" timestamp with time zone, "p_requested_by" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_exported boolean;
  v_score_us integer;
  v_score_them integer;
  v_type text;
  v_created_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported,
         session.score_as_grinta, session.score_adverse
  into v_state, v_exported, v_score_us, v_score_them
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime', 'finished') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;
  if coalesce(v_exported, false) then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;

  select event.event_type, event.created_at into v_type, v_created_at
  from public.match_live_events event
  where event.id = p_event_id and event.match_id = p_match_id
  for update;

  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;

  delete from public.match_live_events
  where id = p_event_id and match_id = p_match_id;

  if v_type = 'goal_us' then
    -- Renuméroter les buts de notre équipe déjà saisis après celui-ci : leur
    -- score figé doit reculer d'une unité pour rester cohérent avec la
    -- suppression.
    update public.match_live_events
    set score_as_grinta_after = score_as_grinta_after - 1
    where match_id = p_match_id
      and event_type = 'goal_us'
      and created_at > v_created_at;

    update public.match_live_sessions
    set score_as_grinta = greatest(0, v_score_us - 1),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif v_type = 'goal_them' then
    update public.match_live_events
    set score_adverse_after = score_adverse_after - 1
    where match_id = p_match_id
      and event_type = 'goal_them'
      and created_at > v_created_at;

    update public.match_live_sessions
    set score_adverse = greatest(0, v_score_them - 1),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  else
    update public.match_live_sessions
    set updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."dispatch_convocation_push"("p_match_id" "uuid", "p_profile_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
  v_request_id bigint;
  v_title text := 'Tu es convoqué';
  v_body text;
  v_match record;
begin
  if p_profile_id is null
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    coalesce(o.name, 'Match entre nous') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_body := format(
    'Tu es convoqué pour le match du %s contre %s.',
    to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
    v_match.opponent_name
  );

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';
  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(p_profile_id),
      'title', v_title,
      'message', v_body
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$$;


ALTER FUNCTION "private"."dispatch_convocation_push"("p_match_id" "uuid", "p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."dispatch_motm_push"("p_kind" "text", "p_match_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
  v_request_id bigint;
begin
  if p_kind <> 'motm_open' then
    raise exception 'Unknown MOTM notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management') then
    return false;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', p_kind,
      'match_id', p_match_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception
  when others then
    return false;
end;
$$;


ALTER FUNCTION "private"."dispatch_motm_push"("p_kind" "text", "p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."dispatch_motm_result_notification"("p_kind" "text", "p_match_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_payload jsonb;
  v_token text;
  v_profile_ids jsonb;
  v_title text;
  v_message text;
  v_request_id bigint;
begin
  if p_kind not in ('motm_result_general', 'motm_result_winner') then
    raise exception 'Unknown MOTM result notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management')
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  v_payload := private.match_motm_result_notification_payloads(p_match_id);
  if p_kind = 'motm_result_general' then
    v_profile_ids := coalesce(v_payload -> 'general_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'general_title';
    v_message := v_payload ->> 'general_message';
  else
    v_profile_ids := coalesce(v_payload -> 'winner_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'winner_title';
    v_message := v_payload ->> 'winner_message';
  end if;

  if jsonb_array_length(v_profile_ids) = 0 then
    return true;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', v_profile_ids,
      'title', v_title,
      'message', v_message
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception
  when others then
    return false;
end;
$$;


ALTER FUNCTION "private"."dispatch_motm_result_notification"("p_kind" "text", "p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."dispatch_motm_result_notification"("p_kind" "text", "p_match_id" "uuid") IS 'Met en file un push ciblé de résultat HDM via le transport interne sécurisé.';



CREATE OR REPLACE FUNCTION "private"."dispatch_sport_notification_event"("p_event_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_event record;
  v_token text;
  v_request_id bigint;
begin
  select event.id, event.kind, event.match_id, event.profile_id
  into v_event
  from public.sport_availability_notification_events event
  where event.id = p_event_id
  for update;

  if not found then
    return false;
  end if;

  if v_event.id is null then
    return false;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    update public.sport_availability_notification_events
    set dispatch_status = 'dispatch_failed'
    where id = p_event_id;
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', v_event.kind,
      'match_id', v_event.match_id,
      'profile_ids', jsonb_build_array(v_event.profile_id),
      'notification_event_id', v_event.id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  update public.sport_availability_notification_events
  set dispatch_status = 'dispatch_requested',
      dispatch_requested_at = now(),
      network_request_id = v_request_id
  where id = p_event_id;

  return true;
exception
  when others then
    update public.sport_availability_notification_events
    set dispatch_status = 'dispatch_failed'
    where id = p_event_id;
    return false;
end;
$$;


ALTER FUNCTION "private"."dispatch_sport_notification_event"("p_event_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."end_match_live"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.elapsed_seconds, session.running_since
  into v_state, v_elapsed, v_running_since
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('running', 'paused', 'halftime') then
    raise exception 'The match is not currently live' using errcode = '22023';
  end if;

  update public.match_live_sessions
  set state = 'finished',
      elapsed_seconds = v_elapsed + case
        when v_state = 'running'
        then greatest(0, extract(epoch from now() - v_running_since))::integer
        else 0
      end,
      running_since = null,
      finished_at = now(),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (p_match_id, 'end_match_live', v_actor, v_reason, '{}'::jsonb);

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."end_match_live"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."enrich_match_convocation_history"("p_payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_set(
    p_payload,
    '{players}',
    coalesce(
      (
        select jsonb_agg(
          player || jsonb_build_object(
            'current_season_waitlist_count',
            case
              when nullif(player ->> 'season_player_id', '') is null then 0
              else coalesce((
                select swe.manual_waitlist_count
                from public.sport_waitlist_entries swe
                where swe.season_player_id = (player ->> 'season_player_id')::uuid
              ), 0)
            end
          )
          order by ordinal
        )
        from jsonb_array_elements(coalesce(p_payload -> 'players', '[]'::jsonb))
          with ordinality as rows(player, ordinal)
      ),
      '[]'::jsonb
    ),
    true
  );
$$;


ALTER FUNCTION "private"."enrich_match_convocation_history"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."enrich_sport_waitlist_history"("p_payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_set(
    p_payload,
    '{entries}',
    coalesce(
      (
        select jsonb_agg(
          entry || jsonb_build_object(
            'current_season_waitlist_count',
            coalesce((
              select swe.manual_waitlist_count
              from public.sport_waitlist_entries swe
              where swe.season_player_id = (entry ->> 'season_player_id')::uuid
            ), 0)
          )
          order by ordinal
        )
        from jsonb_array_elements(coalesce(p_payload -> 'entries', '[]'::jsonb))
          with ordinality as rows(entry, ordinal)
      ),
      '[]'::jsonb
    ),
    true
  );
$$;


ALTER FUNCTION "private"."enrich_sport_waitlist_history"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."ensure_guest_player_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.player_id is null then
    new.player_id := private.create_player_identity(
      btrim(concat_ws(' ', new.first_name, nullif(new.last_name, '')))
    );
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."ensure_guest_player_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."ensure_historical_player_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile_player_id uuid;
  v_matched_player_id uuid;
begin
  if new.player_id is not null then
    return new;
  end if;

  if new.profile_id is not null then
    select p.player_id into v_profile_player_id
    from public.profiles p
    where p.id = new.profile_id;
  end if;

  if v_profile_player_id is not null then
    new.player_id := v_profile_player_id;
    return new;
  end if;

  select min(a.player_id::text)::uuid
  into v_matched_player_id
  from public.player_aliases a
  where private.normalize_player_name(a.alias)
    = private.normalize_player_name(new.player_name)
  having count(distinct a.player_id) = 1;

  new.player_id := coalesce(
    v_matched_player_id,
    private.create_player_identity(btrim(new.player_name))
  );
  return new;
end;
$$;


ALTER FUNCTION "private"."ensure_historical_player_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."ensure_match_motm_election"("p_match_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_exists boolean;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select private.match_motm_opens_at(p_match_id) into v_opens_at;
  if v_opens_at is null then
    return;
  end if;

  if exists (
    select 1
    from public.matches match
    where match.id = p_match_id
      and match.status = 'annule'
  ) then
    return;
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  if not v_has_ballot then
    return;
  end if;

  v_closes_at := v_opens_at + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    'draft'::public.sport_vote_state,
    v_opens_at,
    v_closes_at,
    null,
    0,
    0,
    now(),
    now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = 'draft',
      updated_at = now()
  where match_id = p_match_id;
end;
$$;


ALTER FUNCTION "private"."ensure_match_motm_election"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."ensure_profile_player_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if coalesce(new.email, '') = 'historique@as-grinta.invalid' then
    return new;
  end if;

  if new.player_id is null then
    new.player_id := private.create_player_identity(
      coalesce(
        nullif(btrim(concat_ws(' ', new.first_name, nullif(new.last_name, ''))), ''),
        nullif(btrim(new.username), ''),
        'Joueur'
      )
    );
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."ensure_profile_player_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."ensure_season_player_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile_player_id uuid;
begin
  if new.player_id is not null then
    return new;
  end if;

  if new.profile_id is not null then
    select p.player_id into v_profile_player_id
    from public.profiles p
    where p.id = new.profile_id;
  end if;

  new.player_id := coalesce(
    v_profile_player_id,
    private.create_player_identity(
      btrim(concat_ws(' ', new.first_name, nullif(new.last_name, '')))
    )
  );
  return new;
end;
$$;


ALTER FUNCTION "private"."ensure_season_player_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."ensure_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."ensure_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."finalize_due_waitlist_turns_for_season"("p_season_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_total integer := 0;
begin
  perform private.require_sports_management_enabled();

  for v_match in
    select workflow.match_id
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where match.season_id = p_season_id
      and workflow.convocation_state = 'published'
      and exists (
        select 1 from public.match_sport_participants participant
        where participant.match_id = workflow.match_id
          and participant.waitlist_turn_state = 'pending'
          and participant.waitlist_turn_should_consume
      )
      and (
        match.status <> 'a_venir'
        or (
          workflow.late_withdrawal_cutoff_at is not null
          and now() > workflow.late_withdrawal_cutoff_at
        )
      )
    order by workflow.late_withdrawal_cutoff_at, workflow.match_id
  loop
    v_total := v_total
      + private.finalize_match_waitlist_turns_internal(v_match.match_id, false);
  end loop;
  return v_total;
end;
$$;


ALTER FUNCTION "private"."finalize_due_waitlist_turns_for_season"("p_season_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_existing_version integer := 0;
  v_composition_version integer := 0;
  v_expected integer;
  v_received integer;
  v_present_count integer;
  v_starter_count integer;
  v_goal_total integer;
  v_clean_sheet_count integer;
  v_permanent_present uuid[];
  v_permanent_scorers jsonb;
  v_permanent_clean_sheet uuid;
  v_snapshot jsonb;
  v_kind text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin()
     and not (
       current_setting('as_grinta.allow_coach_live_finalize', true) = 'on'
       and private.is_match_coach_or_admin(p_match_id)
     ) then
    raise exception 'Active administrator role or validated Live coach context required'
      using errcode = '42501';
  end if;
  if p_score_as_grinta is null or p_score_as_grinta not between 0 and 99
     or p_score_adverse is null or p_score_adverse not between 0 and 99 then
    raise exception 'Scores must be between 0 and 99' using errcode = '22023';
  end if;
  if p_participants is null or jsonb_typeof(p_participants) <> 'array' then
    raise exception 'Participants payload must be a JSON array' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at, workflow.composition_version
  into v_match_status, v_kickoff_at, v_composition_version
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;

  select finalization.version
  into v_existing_version
  from public.match_sport_finalizations finalization
  where finalization.match_id = p_match_id
  for update;

  if not found then
    v_existing_version := 0;
  end if;

  if v_match_status not in ('a_venir', 'termine') then
    raise exception 'Only upcoming or finished matches can be validated' using errcode = '22023';
  end if;
  if now() < v_kickoff_at and not exists (
    select 1
    from public.match_live_sessions live_session
    where live_session.match_id = p_match_id
      and live_session.state = 'finished'
  ) then
    raise exception 'The match cannot be finalized before kickoff' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.sport_final_input (
    participant_id uuid primary key,
    present boolean not null,
    final_selection_status public.sport_selection_status not null,
    goals integer not null,
    clean_sheet boolean not null
  ) on commit drop;
  truncate table pg_temp.sport_final_input;

  begin
    insert into pg_temp.sport_final_input(
      participant_id, present, final_selection_status, goals, clean_sheet
    )
    select
      (item ->> 'participant_id')::uuid,
      coalesce((item ->> 'present')::boolean, false),
      (item ->> 'final_selection_status')::public.sport_selection_status,
      coalesce((item ->> 'goals')::integer, 0),
      coalesce((item ->> 'clean_sheet')::boolean, false)
    from jsonb_array_elements(p_participants) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once' using errcode = '22023';
    when invalid_text_representation or numeric_value_out_of_range or check_violation then
      raise exception 'Invalid final participant entry' using errcode = '22023';
  end;

  select count(*) into v_received from pg_temp.sport_final_input;
  select count(*) into v_expected
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (participant.is_eligible or participant.final_presence_status <> 'pending');
  if v_received <> v_expected then
    raise exception 'Every match participant must appear exactly once' using errcode = '22023';
  end if;
  if exists (
    select 1
    from pg_temp.sport_final_input input
    left join public.match_sport_participants participant
      on participant.id = input.participant_id
     and participant.match_id = p_match_id
     and (participant.is_eligible or participant.final_presence_status <> 'pending')
    where participant.id is null
  ) then
    raise exception 'Finalization contains an unknown participant' using errcode = '22023';
  end if;

  if exists (
    select 1 from pg_temp.sport_final_input input
    where input.goals < 0 or input.goals > 99
      or input.final_selection_status = 'undecided'
      or (
        not input.present and (
          input.final_selection_status <> 'not_selected'
          or input.goals <> 0
          or input.clean_sheet
        )
      )
      or (input.goals > 0 and not input.present)
  ) then
    raise exception 'Final presence, role and statistics are inconsistent' using errcode = '22023';
  end if;

  select
    count(*) filter (where present),
    count(*) filter (where present and final_selection_status = 'starter'),
    coalesce(sum(goals), 0),
    count(*) filter (where clean_sheet)
  into v_present_count, v_starter_count, v_goal_total, v_clean_sheet_count
  from pg_temp.sport_final_input;

  if v_present_count = 0 then
    raise exception 'At least one present participant is required' using errcode = '22023';
  end if;
  if v_starter_count > 11 then
    raise exception 'A match cannot have more than eleven actual starters' using errcode = '22023';
  end if;
  if v_goal_total > p_score_as_grinta then
    raise exception 'Attributed goals exceed the AS Grinta score' using errcode = '22023';
  end if;
  if v_clean_sheet_count > 1 then
    raise exception 'Only one goalkeeper can receive the clean sheet' using errcode = '22023';
  end if;
  if v_clean_sheet_count = 1 and p_score_adverse <> 0 then
    raise exception 'Clean sheet is impossible when the opponent scored' using errcode = '22023';
  end if;
  if exists (
    select 1
    from pg_temp.sport_final_input input
    join public.match_sport_participants participant on participant.id = input.participant_id
    left join public.season_players player on player.id = participant.season_player_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where input.clean_sheet
      and (
        not input.present
        or not coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
      )
  ) then
    raise exception 'Clean sheet must belong to a present goalkeeper' using errcode = '22023';
  end if;

  select coalesce(array_agg(participant.season_player_id), '{}'::uuid[])
  into v_permanent_present
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.present and participant.season_player_id is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'season_player_id', participant.season_player_id,
    'goals', input.goals
  )), '[]'::jsonb)
  into v_permanent_scorers
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.goals > 0 and participant.season_player_id is not null;

  select participant.season_player_id into v_permanent_clean_sheet
  from pg_temp.sport_final_input input
  join public.match_sport_participants participant on participant.id = input.participant_id
  where input.clean_sheet and participant.season_player_id is not null
  limit 1;

  perform public.staff_set_match_attendance(p_match_id, v_permanent_present);
  perform public.staff_set_match_mvp(p_match_id, '{}'::uuid[]);
  perform public.finalize_match_postgame(
    p_match_id,
    p_score_adverse,
    v_permanent_scorers,
    v_permanent_clean_sheet,
    p_score_as_grinta
  );

  create temporary table if not exists pg_temp.old_sport_final (
    participant_id uuid primary key,
    presence_status public.sport_final_presence_status not null,
    selection_status public.sport_selection_status not null,
    goals integer not null,
    clean_sheet boolean not null
  ) on commit drop;
  truncate table pg_temp.old_sport_final;
  insert into pg_temp.old_sport_final
  select participant.id, participant.final_presence_status,
    participant.final_selection_status, participant.final_goals,
    participant.final_clean_sheet
  from public.match_sport_participants participant
  where participant.match_id = p_match_id;

  update public.match_sport_participants participant
  set final_presence_status = case
        when input.present then 'present'::public.sport_final_presence_status
        else 'actual_absent'::public.sport_final_presence_status
      end,
      final_selection_status = input.final_selection_status,
      final_goals = input.goals,
      final_clean_sheet = input.clean_sheet,
      final_presence_confirmed_at = now(),
      final_presence_confirmed_by = v_actor,
      updated_at = now()
  from pg_temp.sport_final_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  insert into public.match_sport_participant_events(
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  )
  select participant.id, p_match_id, 'final_presence_validated',
    jsonb_build_object(
      'presence_status', old.presence_status,
      'selection_status', old.selection_status,
      'goals', old.goals,
      'clean_sheet', old.clean_sheet
    ),
    jsonb_build_object(
      'presence_status', participant.final_presence_status,
      'selection_status', participant.final_selection_status,
      'goals', participant.final_goals,
      'clean_sheet', participant.final_clean_sheet
    ),
    v_actor, 'staff'
  from public.match_sport_participants participant
  join pg_temp.old_sport_final old on old.participant_id = participant.id
  where participant.match_id = p_match_id
    and (
      old.presence_status is distinct from participant.final_presence_status
      or old.selection_status is distinct from participant.final_selection_status
      or old.goals is distinct from participant.final_goals
      or old.clean_sheet is distinct from participant.final_clean_sheet
    );

  update public.match_sport_workflows
  set availability_state = 'closed',
      composition_state = 'closed',
      presence_state = 'confirmed',
      vote_state = 'draft',
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  v_kind := case when v_existing_version = 0 then 'initial' else 'correction' end;

  insert into public.match_sport_finalizations(
    match_id, version, score_as_grinta, score_adverse,
    composition_version, validated_by, corrected_at, corrected_by
  ) values (
    p_match_id, 1, p_score_as_grinta, p_score_adverse,
    v_composition_version, v_actor, null, null
  )
  on conflict (match_id) do update
  set version = match_sport_finalizations.version + 1,
      score_as_grinta = excluded.score_as_grinta,
      score_adverse = excluded.score_adverse,
      composition_version = excluded.composition_version,
      corrected_at = now(),
      corrected_by = v_actor,
      updated_at = now();

  v_snapshot := private.match_sport_finalization_snapshot(p_match_id)
    || jsonb_build_object('validation_kind', v_kind);

  insert into public.match_sport_finalization_versions(
    match_id, version, snapshot, validation_kind, created_by
  )
  select finalization.match_id, finalization.version, v_snapshot, v_kind, v_actor
  from public.match_sport_finalizations finalization
  where finalization.match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_kind = 'initial' then 'validate_final_attendance' else 'correct_final_attendance' end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_existing_version + 1,
      'score_as_grinta', p_score_as_grinta,
      'score_adverse', p_score_adverse,
      'present_count', v_present_count,
      'starter_count', v_starter_count,
      'guest_present_count', (
        select count(*)
        from pg_temp.sport_final_input input
        join public.match_sport_participants participant on participant.id = input.participant_id
        where input.present and participant.guest_player_id is not null
      ),
      'attributed_goals', v_goal_total
    )
  );

  return v_snapshot;
end;
$$;


ALTER FUNCTION "private"."finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."finalize_match_waitlist_turns_internal"("p_match_id" "uuid", "p_force" boolean DEFAULT false) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."finalize_match_waitlist_turns_internal"("p_match_id" "uuid", "p_force" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_admin_match_composition"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.composition_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."get_admin_match_composition"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_admin_match_motm_dashboard"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  perform private.close_match_motm_election(p_match_id, true);

  select jsonb_build_object(
    'match_id', election.match_id,
    'opponent_name', opponent.name,
    'kickoff_at', match.kickoff_at,
    'score_as_grinta', match.score_as_grinta,
    'score_adverse', match.score_adverse,
    'state', election.state,
    'opens_at', election.opens_at,
    'closes_at', election.closes_at,
    'closed_at', election.closed_at,
    'finalization_version', election.finalization_version,
    'eligible_voter_count', eligible.count,
    'votes_received', votes.count,
    'candidate_count', candidates.count,
    'participation_rate', case
      when eligible.count = 0 then 0
      else round((votes.count::numeric * 100) / eligible.count, 1)
    end,
    'total_votes', case when election.state = 'closed' then election.total_votes else null end,
    'max_votes', case when election.state = 'closed' then election.max_votes else null end,
    'notifications', jsonb_build_object(
      'open', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_open'
      ),
      'reminder', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_reminder'
      ),
      'results', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_results'
      )
    ),
    'winners', case when election.state = 'closed' then coalesce((
      select jsonb_agg(jsonb_build_object(
        'participant_id', participant.id,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end,
        'is_guest', guest.id is not null,
        'votes_count', result.votes_count
      ) order by lower(coalesce(player.first_name, guest.first_name)), participant.id)
      from public.match_sport_motm_results result
      join public.match_sport_participants participant
        on participant.id = result.participant_id
       and participant.match_id = result.match_id
      left join public.season_players player on player.id = participant.season_player_id
      left join public.guest_players guest on guest.id = participant.guest_player_id
      where result.match_id = election.match_id and result.is_winner
    ), '[]'::jsonb) else '[]'::jsonb end,
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', audit.action,
        'reason', audit.reason,
        'created_at', audit.created_at,
        'actor_name', btrim(concat_ws(' ', profile.first_name, profile.last_name)),
        'metadata', audit.metadata
      ) order by audit.created_at desc, audit.id desc)
      from private.sport_admin_audit_log audit
      left join public.profiles profile on profile.id = audit.actor_profile_id
      where audit.match_id = election.match_id
        and audit.action in (
          'open_motm_vote',
          'reset_motm_vote_after_correction',
          'restart_motm_vote',
          'cancel_motm_vote',
          'close_motm_vote_early'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  cross join lateral (
    select count(distinct profile.id)::integer as count
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
      and profile.status = 'active'
  ) eligible
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_motm_votes vote
    where vote.match_id = election.match_id
      and vote.finalization_version = election.finalization_version
  ) votes
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_participants participant
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
  ) candidates
  where election.match_id = p_match_id;

  if v_result is null then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_admin_match_motm_dashboard"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_admin_match_sport_finalization"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  v_result := private.match_sport_finalization_snapshot(p_match_id);
  if v_result is null then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_admin_match_sport_finalization"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_all_historical_match_results"() RETURNS TABLE("id" "uuid", "match_date" "date", "opponent_name" "text", "score_as_grinta" smallint, "score_adverse" smallint, "is_home" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select h.id, h.match_date, o.name, h.score_as_grinta, h.score_adverse, h.is_home
  from public.historical_match_scores h
  join public.opponents o on o.id = h.opponent_id
  order by h.match_date desc, h.id desc;
end;
$$;


ALTER FUNCTION "private"."get_all_historical_match_results"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_finished_bench_counts"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', current_participant.id,
      'finished_bench_count', (
        select count(*)
        from public.match_sport_participants hist
        join public.matches hist_match on hist_match.id = hist.match_id
        where hist_match.status in ('termine', 'archive')
          and hist.match_id <> p_match_id
          and hist.final_selection_status = 'substitute'
          and (
            (current_participant.season_player_id is not null
              and hist.season_player_id = current_participant.season_player_id)
            or (current_participant.guest_player_id is not null
              and hist.guest_player_id = current_participant.guest_player_id)
          )
      )
    )
  ), '[]'::jsonb)
  into v_result
  from public.match_sport_participants current_participant
  where current_participant.match_id = p_match_id;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_finished_bench_counts"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_guest_players"("p_include_archived" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'guests', coalesce(jsonb_agg(
      jsonb_build_object(
        'guest_player_id', guest.id,
        'first_name', guest.first_name,
        'last_name', guest.last_name,
        'display_name',
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)',
        'photo_url', guest.photo_url,
        'is_goalkeeper', guest.is_goalkeeper,
        'is_reusable', guest.is_reusable,
        'archived_at', guest.archived_at,
        'created_at', guest.created_at,
        'updated_at', guest.updated_at
      )
      order by
        guest.is_reusable desc,
        lower(guest.first_name),
        lower(coalesce(guest.last_name, '')),
        guest.created_at
    ), '[]'::jsonb)
  )
  into v_result
  from public.guest_players guest
  where p_include_archived or guest.is_reusable;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_guest_players"("p_include_archived" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_historical_match_detail"("p_match_id" "uuid") RETURNS TABLE("formation" "text", "field_players" "jsonb", "bench_players" "jsonb", "present_names" "jsonb", "scorers" "jsonb", "motm_names" "jsonb", "photo_urls" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select
    d.formation, d.field_players, d.bench_players, d.present_names,
    d.scorers, d.motm_names,
    coalesce(
      (
        select jsonb_object_agg(
          hmp.source_name,
          coalesce(pr.photo_url, sp.photo_url)
        )
        from public.historical_match_players hmp
        left join public.profiles pr on pr.player_id = hmp.player_id
        left join lateral (
          select season_players.photo_url
          from public.season_players
          where season_players.player_id = hmp.player_id
            and season_players.photo_url is not null
          order by season_players.joined_at desc
          limit 1
        ) sp on true
        where hmp.match_id = d.match_id
          and coalesce(pr.photo_url, sp.photo_url) is not null
      ),
      '{}'::jsonb
    ) as photo_urls
  from public.historical_match_details d
  where d.match_id = p_match_id;
end;
$$;


ALTER FUNCTION "private"."get_historical_match_detail"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."get_historical_match_detail"("p_match_id" "uuid") IS 'Read-only historical match detail (composition/buteurs/HDM) for one match_id, with a source-name -> photo_url map falling back from the account photo to the season-roster photo, same as the live composition snapshot.';



CREATE OR REPLACE FUNCTION "private"."get_historical_match_results"("p_season_name" "text") RETURNS TABLE("id" "uuid", "match_date" "date", "opponent_name" "text", "score_as_grinta" smallint, "score_adverse" smallint, "is_home" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_start_year integer;
  v_end_year integer;
  v_start_date date;
  v_end_date date;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if p_season_name is null or p_season_name !~ '^[0-9]{4}-[0-9]{4}$' then
    raise exception 'Invalid season name' using errcode = '22023';
  end if;

  v_start_year := substring(p_season_name from 1 for 4)::integer;
  v_end_year := substring(p_season_name from 6 for 4)::integer;
  if v_end_year <> v_start_year + 1 then
    raise exception 'Invalid season range' using errcode = '22023';
  end if;

  v_start_date := make_date(v_start_year, 7, 1);
  v_end_date := make_date(v_end_year, 7, 1);

  return query
  select h.id, h.match_date, o.name, h.score_as_grinta, h.score_adverse, h.is_home
  from public.historical_match_scores h
  join public.opponents o on o.id = h.opponent_id
  where h.match_date >= v_start_date
    and h.match_date < v_end_date
  order by h.match_date desc, h.id desc;
end;
$_$;


ALTER FUNCTION "private"."get_historical_match_results"("p_season_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_match_availability_board"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
          else coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), btrim(player.first_name))
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
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null)
            then waitlist.position
        end desc nulls last,
        case
          when participant.convocation_status = 'not_convoked'
            and participant.availability_status = 'available'
            then waitlist.position
        end asc nulls last,
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


ALTER FUNCTION "private"."get_match_availability_board"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_match_convocations"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    'opponent_name', coalesce(opponent.name, 'Match entre nous'),
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'published_squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'has_unpublished_changes', false,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', coalesce(players.available_count, 0),
    'convoked_count', coalesce(players.convoked_count, 0),
    'not_convoked_count', coalesce(players.not_convoked_count, 0),
    'players', coalesce(players.items, '[]'::jsonb)
  )
  into v_result
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join lateral (
    select
      count(*) filter (
        where row.is_eligible
          and (
            (row.season_player_id is not null and row.availability_status = 'available')
            or row.guest_player_id is not null
          )
      )::integer as available_count,
      count(*) filter (
        where row.is_eligible
          and row.convocation_status = 'convoked'
          and (
            row.availability_status = 'available'
            or row.guest_player_id is not null
          )
      )::integer as convoked_count,
      count(*) filter (
        where row.is_eligible
          and row.season_player_id is not null
          and row.availability_status = 'available'
          and row.convocation_status = 'not_convoked'
      )::integer as not_convoked_count,
      jsonb_agg(
        jsonb_build_object(
          'participant_id', row.participant_id,
          'season_player_id', row.season_player_id,
          'guest_player_id', row.guest_player_id,
          'first_name', row.first_name,
          'last_name', row.last_name,
          'display_name', row.display_name,
          'is_guest', row.guest_player_id is not null,
          'is_goalkeeper', row.is_goalkeeper,
          'availability_status', row.availability_status,
          'availability_updated_at', row.availability_updated_at,
          'convocation_status', row.convocation_status,
          'published_convocation_status', row.convocation_status,
          'manual_override', row.convocation_manual_override,
          'waitlist_position', row.waitlist_position,
          'waitlist_position_snapshot', row.waitlist_position_snapshot,
          'current_season_waitlist_count', row.current_season_waitlist_count,
          'recommended_not_convoked', row.waitlist_recommended_not_convoked,
          'turn_should_consume', row.waitlist_turn_should_consume,
          'turn_state', row.waitlist_turn_state,
          'promoted_after_withdrawal_at', row.promoted_after_withdrawal_at
        )
        order by row.availability_order, row.waitlist_position,
          lower(row.first_name), lower(coalesce(row.last_name, ''))
      ) filter (where row.participant_id is not null and row.is_eligible) as items
    from (
      select
        participant.id as participant_id,
        participant.season_player_id,
        participant.guest_player_id,
        participant.is_eligible,
        coalesce(player.first_name, guest.first_name) as first_name,
        coalesce(player.last_name, guest.last_name) as last_name,
        case
          when guest.id is not null then btrim(guest.first_name) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''),
            nullif(btrim(profile.first_name), ''),
            btrim(player.first_name)
          )
        end as display_name,
        coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
        participant.availability_status,
        participant.availability_updated_at,
        participant.convocation_status,
        participant.convocation_manual_override,
        waitlist.position as waitlist_position,
        participant.waitlist_position_snapshot,
        coalesce(waitlist.manual_waitlist_count, 0) as current_season_waitlist_count,
        participant.waitlist_recommended_not_convoked,
        participant.waitlist_turn_should_consume,
        participant.waitlist_turn_state,
        participant.promoted_after_withdrawal_at,
        case
          when participant.guest_player_id is not null then 0
          when participant.availability_status = 'available' then 0
          when participant.availability_status = 'no_response' then 1
          when participant.availability_status = 'absent' then 2
          else 3
        end as availability_order
      from public.match_sport_participants participant
      left join public.season_players player
        on player.id = participant.season_player_id
      left join public.profiles profile on profile.id = player.profile_id
      left join public.guest_players guest
        on guest.id = participant.guest_player_id
      left join public.sport_waitlist_entries waitlist
        on waitlist.season_player_id = participant.season_player_id
       and waitlist.season_id = match.season_id
      where participant.match_id = match.id
    ) row
  ) players on true
  where match.id = p_match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_match_convocations"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_match_guests"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
  ) then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'match_id', p_match_id,
    'guests', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'guest_player_id', guest.id,
        'first_name', guest.first_name,
        'last_name', guest.last_name,
        'display_name',
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)',
        'is_goalkeeper', guest.is_goalkeeper,
        'is_reusable', guest.is_reusable,
        'archived_at', guest.archived_at,
        'selection_status', participant.selection_status,
        'created_at', participant.created_at
      )
      order by lower(guest.first_name), lower(coalesce(guest.last_name, ''))
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.match_sport_participants participant
  join public.guest_players guest on guest.id = participant.guest_player_id
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_match_guests"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_match_live_add_player_options"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."get_match_live_add_player_options"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_match_live_timeline"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."get_match_live_timeline"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_match_motm_vote"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_election public.match_sport_motm_elections%rowtype;
  v_voter_participant_id uuid;
  v_has_voted boolean := false;
  v_can_vote boolean := false;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  perform private.ensure_match_motm_election(p_match_id);
  perform private.transition_match_motm_election(p_match_id);

  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;

  if not found then
    return null;
  end if;

  select participant.id into v_voter_participant_id
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where profile.id = v_actor
    and profile.status = 'active'
  order by participant.id
  limit 1;

  v_has_voted := exists (
    select 1 from public.match_sport_motm_votes vote
    where vote.match_id = p_match_id
      and vote.voter_profile_id = v_actor
  );

  v_can_vote := v_election.state = 'open'
    and v_election.opens_at is not null
    and now() >= v_election.opens_at
    and now() < v_election.closes_at
    and v_voter_participant_id is not null
    and not v_has_voted
    and exists (
      select 1
      from private.match_motm_candidate_participants(p_match_id) candidate
      join public.match_sport_participants participant
        on participant.id = candidate.participant_id
      left join public.season_players candidate_player
        on candidate_player.id = participant.season_player_id
      where participant.id <> v_voter_participant_id
        and (
          participant.guest_player_id is not null
          or candidate_player.profile_id is distinct from v_actor
        )
    );

  select jsonb_build_object(
    'match_id', election.match_id,
    'opponent_name', opponent.name,
    'is_home', match.location = 'domicile',
    'score_as_grinta', finalization.score_as_grinta,
    'score_adverse', finalization.score_adverse,
    'state', election.state,
    'opens_at', election.opens_at,
    'closes_at', election.closes_at,
    'closed_at', election.closed_at,
    'finalization_version', election.finalization_version,
    'has_voted', v_has_voted,
    'can_vote', v_can_vote,
    'is_eligible_voter', v_voter_participant_id is not null,
    'total_votes', case when election.state = 'closed' then election.total_votes else null end,
    'max_votes', case when election.state = 'closed' then election.max_votes else null end,
    'candidates', coalesce((
      select jsonb_agg(candidate_json order by candidate_order desc, candidate_name, candidate_pid)
      from (
        select
          jsonb_build_object(
            'participant_id', participant.id,
            'season_player_id', participant.season_player_id,
            'guest_player_id', participant.guest_player_id,
            'display_name', case
              when guest.id is not null then
                btrim(guest.first_name) || ' (Invité)'
              else coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), btrim(player.first_name))
            end,
            'is_guest', guest.id is not null,
            'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
            'is_self', player.profile_id = v_actor,
            'can_choose', guest.id is not null or player.profile_id is distinct from v_actor,
            'goals', coalesce(participant.final_goals, 0),
            'clean_sheet', case
              when coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
                   and finalization.score_adverse is not null
                then finalization.score_adverse = 0
              else null
            end,
            'votes_count', case when election.state = 'closed' then coalesce(result.votes_count, 0) else null end,
            'is_winner', case when election.state = 'closed' then coalesce(result.is_winner, false) else null end
          ) as candidate_json,
          case when election.state = 'closed' then coalesce(result.votes_count, 0) else 0 end as candidate_order,
          coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), player.first_name, guest.first_name) as candidate_name,
          participant.id as candidate_pid
        from private.match_motm_candidate_participants(p_match_id) candidate
        join public.match_sport_participants participant
          on participant.id = candidate.participant_id
        left join public.season_players player on player.id = participant.season_player_id
        left join public.profiles profile on profile.id = player.profile_id
        left join public.guest_players guest on guest.id = participant.guest_player_id
        left join public.match_sport_motm_results result
          on result.match_id = participant.match_id
         and result.participant_id = participant.id
      ) candidates
    ), '[]'::jsonb)
  ) into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  left join public.match_sport_finalizations finalization
    on finalization.match_id = election.match_id
  where election.match_id = p_match_id;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_match_motm_vote"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."get_match_motm_vote"("p_match_id" "uuid") IS 'MOTM vote opening 1h45 after kickoff (or at validation) from the published lineup, closing 24h after kickoff, revealing every ballot.';



CREATE OR REPLACE FUNCTION "private"."get_match_sport_statistics_integrity"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', finalization.match_id,
    'finalization_version', finalization.version,
    'permanent_present_expected', expected.present_count,
    'attendance_rows', actual.attendance_count,
    'goals_expected', expected.goals_count,
    'goals_in_statistics', actual.goals_count,
    'clean_sheets_expected', expected.clean_sheet_count,
    'clean_sheets_in_statistics', actual.clean_sheet_count,
    'permanent_motm_expected', expected.motm_count,
    'motm_rows', actual.motm_count,
    'attendance_ok', expected.present_count = actual.attendance_count,
    'goals_ok', expected.goals_count = actual.goals_count,
    'clean_sheets_ok', expected.clean_sheet_count = actual.clean_sheet_count,
    'motm_ok', expected.motm_count = actual.motm_count,
    'all_ok', expected.present_count = actual.attendance_count
      and expected.goals_count = actual.goals_count
      and expected.clean_sheet_count = actual.clean_sheet_count
      and expected.motm_count = actual.motm_count
  ) into v_result
  from public.match_sport_finalizations finalization
  cross join lateral (
    select
      count(*) filter (
        where participant.final_presence_status = 'present'
          and participant.season_player_id is not null
      )::integer as present_count,
      coalesce(sum(participant.final_goals) filter (
        where participant.season_player_id is not null
      ), 0)::integer as goals_count,
      count(*) filter (
        where participant.season_player_id is not null
          and participant.final_clean_sheet
      )::integer as clean_sheet_count,
      (
        select count(*)::integer
        from public.match_sport_motm_results result
        join public.match_sport_participants winner
          on winner.id = result.participant_id and winner.match_id = result.match_id
        where result.match_id = finalization.match_id
          and result.is_winner
          and winner.season_player_id is not null
      ) as motm_count
    from public.match_sport_participants participant
    where participant.match_id = finalization.match_id
  ) expected
  cross join lateral (
    select
      (select count(*)::integer from public.match_attendance attendance
       where attendance.match_id = finalization.match_id) as attendance_count,
      (select coalesce(sum(stats.goals), 0)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id) as goals_count,
      (select count(*)::integer from public.match_player_stats stats
       where stats.match_id = finalization.match_id and stats.clean_sheet) as clean_sheet_count,
      (select count(*)::integer from public.match_man_of_match motm
       where motm.match_id = finalization.match_id) as motm_count
  ) actual
  where finalization.match_id = p_match_id;

  if v_result is null then
    raise exception 'Final attendance must be validated first' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_match_sport_statistics_integrity"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_my_match_availability"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', participant.match_id,
    'participant_id', participant.id,
    'season_player_id', participant.season_player_id,
    'is_eligible', participant.is_eligible,
    'availability_status', participant.availability_status,
    'private_comment', participant.availability_comment_private,
    'availability_updated_at', participant.availability_updated_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'kickoff_at', match.kickoff_at,
    'can_respond', (participant.is_eligible or player.is_coach)
      and now() >= workflow.availability_opens_at
      and now() < match.kickoff_at
      and workflow.availability_state <> 'closed',
    'composition_state', workflow.composition_state,
    'convocation_state', workflow.convocation_state,
    'convocation_status', case
      when workflow.convocation_state = 'published' and participant.is_eligible
        then participant.convocation_status::text
      else null
    end
  ) into v_result
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and player.profile_id = v_actor;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_my_match_availability"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_notifications_paused"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object(
    'notifications_paused',
    jsonb_build_object('enabled', f.enabled, 'updated_at', f.updated_at)
  )
  from private.app_feature_flags f
  where f.key = 'notifications_paused';
$$;


ALTER FUNCTION "private"."get_notifications_paused"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_player_position_history"("p_since" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'player_id', identity.player_id,
        'x', entry.x,
        'y', entry.y,
        'kickoff_at', match.kickoff_at
      )
    ),
    '[]'::jsonb
  )
  into v_result
  from public.match_composition_entries entry
  join public.matches match on match.id = entry.match_id
  join public.match_sport_participants participant
    on participant.id = entry.participant_id
  left join public.season_players season_player
    on season_player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  cross join lateral (
    select coalesce(season_player.player_id, guest.player_id) as player_id
  ) identity
  where match.status in ('termine', 'archive')
    and match.kickoff_at >= p_since
    and entry.zone = 'field'::public.sport_composition_zone
    and entry.x is not null
    and entry.y is not null
    and identity.player_id is not null;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_player_position_history"("p_since" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_public_feature_flags"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object(
    'sports_management',
    jsonb_build_object(
      'enabled', f.enabled,
      'config', f.config,
      'updated_at', f.updated_at
    )
  )
  from private.app_feature_flags f
  where f.key = 'sports_management';
$$;


ALTER FUNCTION "private"."get_public_feature_flags"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_published_match_composition"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
  v_kickoff_at timestamptz;
  v_before_kickoff boolean;
  v_entries jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_participant record;
  v_field_count integer := 0;
  v_bench_count integer := 0;
  v_available_count integer := 0;
  v_not_selected_count integer := 0;
  v_latest_motm_version integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select publication.snapshot, match.kickoff_at
  into v_result, v_kickoff_at
  from public.match_composition_publications publication
  join public.matches match on match.id = publication.match_id
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_result is null then
    return null;
  end if;

  v_before_kickoff := now() < v_kickoff_at;

  select max(finalization_version) into v_latest_motm_version
  from public.match_sport_motm_results
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(v_result -> 'entries', '[]'::jsonb))
    order by coalesce((value ->> 'sort_order')::integer, 0)
  loop
    select
      participant.availability_status::text as availability_status,
      participant.convocation_status::text as convocation_status,
      participant.final_presence_status::text as final_presence_status,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      coalesce(
        nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
      exists (
        select 1 from public.match_sport_motm_results result
        where result.match_id = p_match_id
          and result.participant_id = participant.id
          and result.is_winner
          and result.finalization_version = v_latest_motm_version
      ) as is_motm
    into v_participant
    from public.match_sport_participants participant
    left join public.season_players player on player.id = participant.season_player_id
    left join public.profiles profile on profile.id = player.profile_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and participant.id = (v_entry ->> 'participant_id')::uuid;

    if found then
      v_entry := v_entry || jsonb_build_object(
        'availability_status', v_participant.availability_status,
        'convocation_status', v_participant.convocation_status,
        'photo_url', v_participant.photo_url,
        'goals', v_participant.goals,
        'is_motm', v_participant.is_motm,
        'display_name', coalesce(v_participant.display_name, v_entry ->> 'display_name')
      );
      if v_before_kickoff then
        -- La composition publiée montre ce que l'admin a décidé : un convoqué
        -- reste affiché à son poste même si sa disponibilité dit le contraire.
        if v_participant.convocation_status <> 'convoked'
           and (v_entry ->> 'zone') in ('field', 'bench', 'available') then
          v_entry := v_entry || jsonb_build_object(
            'zone', 'not_selected', 'x', null, 'y', null,
            'selection_status', 'not_selected'
          );
        end if;
      elsif v_participant.final_presence_status = 'present'
            and (v_entry ->> 'zone') in ('available', 'not_selected') then
        v_entry := v_entry || jsonb_build_object(
          'zone', 'bench', 'selection_status', 'substitute'
        );
      end if;
    end if;

    case v_entry ->> 'zone'
      when 'field' then v_field_count := v_field_count + 1;
      when 'bench' then v_bench_count := v_bench_count + 1;
      when 'available' then v_available_count := v_available_count + 1;
      else v_not_selected_count := v_not_selected_count + 1;
    end case;

    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  for v_participant in
    select
      participant.id,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      coalesce(
        nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
      coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
      exists (
        select 1 from public.match_sport_motm_results result
        where result.match_id = p_match_id
          and result.participant_id = participant.id
          and result.is_winner
          and result.finalization_version = v_latest_motm_version
      ) as is_motm
    from public.match_sport_participants participant
    left join public.season_players player on player.id = participant.season_player_id
    left join public.profiles profile on profile.id = player.profile_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and participant.final_presence_status = 'present'
      and not exists (
        select 1 from jsonb_array_elements(v_entries)
        where (value ->> 'participant_id')::uuid = participant.id
      )
  loop
    v_entry := jsonb_build_object(
      'participant_id', v_participant.id,
      'season_player_id', v_participant.season_player_id,
      'guest_player_id', v_participant.guest_player_id,
      'display_name', v_participant.display_name,
      'photo_url', v_participant.photo_url,
      'goals', v_participant.goals,
      'is_motm', v_participant.is_motm,
      'is_goalkeeper', v_participant.is_goalkeeper,
      'is_guest', v_participant.guest_player_id is not null,
      'zone', 'bench',
      'selection_status', 'substitute',
      'availability_status', 'available',
      'convocation_status', 'convoked',
      'x', null, 'y', null,
      'sort_order', 999
    );
    v_bench_count := v_bench_count + 1;
    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  return v_result || jsonb_build_object(
    'entries', v_entries,
    'field_count', v_field_count,
    'bench_count', v_bench_count,
    'available_count', v_available_count,
    'not_selected_count', v_not_selected_count
  );
end;
$$;


ALTER FUNCTION "private"."get_published_match_composition"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_published_match_sport_result"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.match_sport_finalizations finalization
    where finalization.match_id = p_match_id
  ) then
    return null;
  end if;
  return private.match_sport_finalization_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."get_published_match_sport_result"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_sport_availability_reminder_summary"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', workflow.match_id,
    'availability_state', workflow.availability_state,
    'no_response_count', (
      select count(*)
      from public.match_sport_participants participant
      where participant.match_id = workflow.match_id
        and participant.is_eligible
        and participant.availability_status = 'no_response'
    ),
    'open_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_open'
    ),
    'j3_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_j3'
    ),
    'j1_sent_count', (
      select count(*)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_j1'
    ),
    'last_manual_at', (
      select max(event.requested_at)
      from public.sport_availability_notification_events event
      where event.match_id = workflow.match_id
        and event.kind = 'availability_manual'
    ),
    'can_remind', workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > now(),
    'players', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'season_player_id', participant.season_player_id,
          'last_reminder_at', reminder.last_reminder_at,
          'manual_cooldown_until', reminder.last_manual_at + interval '10 minutes'
        ) order by participant.season_player_id
      )
      from public.match_sport_participants participant
      left join lateral (
        select
          max(event.requested_at) as last_reminder_at,
          max(event.requested_at) filter (
            where event.kind = 'availability_manual'
          ) as last_manual_at
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
      ) reminder on true
      where participant.match_id = workflow.match_id
        and participant.is_eligible
    ), '[]'::jsonb)
  )
  into v_result
  from public.match_sport_workflows workflow
  join public.matches match on match.id = workflow.match_id
  where workflow.match_id = p_match_id;

  if v_result is null then
    raise exception 'Sports workflow not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."get_sport_availability_reminder_summary"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_sport_waitlist"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
        'display_name', coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), btrim(player.first_name)),
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
$$;


ALTER FUNCTION "private"."get_sport_waitlist"("p_season_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."get_sport_waitlist_readonly"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);

  select jsonb_build_object(
    'season_id', season.id,
    'season_name', season.name,
    'entries', coalesce(jsonb_agg(
      jsonb_build_object(
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'display_name', coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), btrim(player.first_name)),
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
$$;


ALTER FUNCTION "private"."get_sport_waitlist_readonly"("p_season_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."guard_finished_match_composition_write"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match_id uuid;
  v_status text;
  v_is_cascade_delete boolean := tg_op = 'DELETE' and pg_trigger_depth() > 1;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select match.status::text into v_status
  from public.matches match
  where match.id = v_match_id;

  if v_status in ('termine', 'archive') and not v_is_cascade_delete then
    if coalesce(
      current_setting('as_grinta.allow_postmatch_composition_write', true),
      'off'
    ) <> 'on' then
      raise exception 'Finished match compositions are immutable'
        using errcode = '55000';
    end if;

    perform private.assert_match_postgame_correction_open(v_match_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."guard_finished_match_composition_write"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."guard_finished_match_composition_write"() IS 'Autorise les écritures de composition post-match uniquement via le workflow prévu et jusqu’à la même échéance que le vote HDM.';



CREATE OR REPLACE FUNCTION "private"."guard_match_archive_transition"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.status = 'archive'
     and old.status is distinct from 'archive'
     and old.status <> 'termine' then
    raise exception 'Only a finished match can be archived'
      using errcode = '22023';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."guard_match_archive_transition"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."guard_match_lifecycle_write"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_lock_at timestamptz;
  v_identity_changed boolean := false;
begin
  v_lock_at := case
    when old.kickoff_at is null then null
    else private.match_prediction_closes_at(old.kickoff_at)
  end;

  if tg_op = 'DELETE' then
    if old.status in ('termine', 'archive') then
      raise exception 'Un match passé ne peut pas être supprimé.' using errcode = '22023';
    end if;
    if v_lock_at is not null and now() >= v_lock_at then
      raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
    end if;
    return old;
  end if;

  v_identity_changed :=
    new.season_id is distinct from old.season_id
    or new.opponent_id is distinct from old.opponent_id
    or new.match_date is distinct from old.match_date
    or new.match_time is distinct from old.match_time
    or new.kickoff_at is distinct from old.kickoff_at
    or new.location is distinct from old.location
    or new.planned_duration_minutes is distinct from old.planned_duration_minutes
    or new.address is distinct from old.address
    or new.match_type is distinct from old.match_type
    or new.jersey_note is distinct from old.jersey_note;

  if old.status in ('termine', 'archive') and v_identity_changed then
    raise exception 'Un match passé se corrige via le compte rendu, pas via la fiche match.' using errcode = '22023';
  end if;

  if old.status = 'a_venir' and v_lock_at is not null and now() >= v_lock_at and v_identity_changed then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  if old.status = 'a_venir' and new.status = 'annule'
     and v_lock_at is not null and now() >= v_lock_at then
    raise exception 'Un match ne peut plus être annulé après l’ouverture du Live.' using errcode = '22023';
  end if;

  if old.status in ('termine', 'archive') and new.status = 'annule' then
    raise exception 'Un match passé ne peut pas être annulé.' using errcode = '22023';
  end if;

  if old.status = 'a_venir'
     and new.status = 'termine'
     and old.match_type is distinct from 'entre_nous' then
    if old.kickoff_at is null
       or (
         now() < old.kickoff_at
           + make_interval(mins => coalesce(old.planned_duration_minutes, 90) + 15)
         and not exists (
           select 1
           from public.match_live_sessions live_session
           where live_session.match_id = old.id
             and live_session.state = 'finished'
         )
       ) then
      raise exception 'Le match ne peut pas être validé avant sa fin.' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."guard_match_lifecycle_write"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."guard_match_status_chronology"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_kickoff timestamptz;
begin
  if new.match_date is null or new.match_time is null then
    return new;
  end if;

  v_kickoff := (new.match_date + new.match_time) at time zone 'Europe/Paris';

  if new.status = 'termine' and v_kickoff > now() then
    raise exception 'Un match futur ne peut pas être marqué terminé.'
      using errcode = '22023';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."guard_match_status_chronology"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."guard_postgame_correction_window"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if old.status = 'termine'
     and (
       new.score_as_grinta is distinct from old.score_as_grinta
       or new.score_adverse is distinct from old.score_adverse
       or new.result_validated_at is distinct from old.result_validated_at
     ) then
    perform private.assert_match_postgame_correction_open(old.id);

    -- Le RPC historique réécrit result_validated_at à chaque correction.
    -- On conserve ici l'instant de validation initiale afin qu'une correction
    -- ne puisse jamais repousser la fenêtre de 24 heures.
    if old.result_validated_at is not null then
      new.result_validated_at := old.result_validated_at;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."guard_postgame_correction_window"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."handle_convoked_withdrawal"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_cutoff timestamptz;
  v_convocation_state public.sport_convocation_state;
  v_old_convocation public.sport_convocation_status;
  v_candidate_id uuid;
  v_candidate_season_player_id uuid;
  v_late boolean;
begin
  select workflow.late_withdrawal_cutoff_at,
    workflow.convocation_state,
    participant.convocation_status
  into v_cutoff, v_convocation_state, v_old_convocation
  from public.match_sport_workflows workflow
  join public.match_sport_participants participant
    on participant.match_id = workflow.match_id
  where workflow.match_id = p_match_id
    and participant.id = p_participant_id
  for update of workflow, participant;

  if not found
     or v_convocation_state <> 'published'
     or v_old_convocation <> 'convoked' then
    return null;
  end if;

  v_late := v_cutoff is not null and now() > v_cutoff;
  if v_late then
    perform private.finalize_match_waitlist_turns_internal(p_match_id, false);
  end if;

  update public.match_sport_participants
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      updated_at = now()
  where id = p_participant_id;

  select candidate.id, candidate.season_player_id
  into v_candidate_id, v_candidate_season_player_id
  from public.match_sport_participants candidate
  join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = candidate.season_player_id
  where candidate.match_id = p_match_id
    and candidate.is_eligible
    and candidate.availability_status = 'available'
    and candidate.convocation_status = 'not_convoked'
  order by waitlist.position, candidate.id
  limit 1
  for update of candidate;

  if v_candidate_id is null then
    return null;
  end if;

  update public.match_sport_participants
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      promoted_after_withdrawal_at = now(),
      promoted_from_participant_id = p_participant_id,
      waitlist_turn_should_consume = case
        when v_late then waitlist_turn_should_consume
        else false
      end,
      waitlist_turn_state = case
        when v_late then waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where id = v_candidate_id;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = coalesce(p_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values
  (
    p_participant_id, p_match_id, 'convoked_player_withdrew',
    jsonb_build_object('convocation_status', 'convoked'),
    jsonb_build_object('convocation_status', 'not_applicable'),
    p_actor, p_actor_kind
  ),
  (
    v_candidate_id, p_match_id, 'waitlisted_player_promoted',
    jsonb_build_object('convocation_status', 'not_convoked'),
    jsonb_build_object(
      'convocation_status', 'convoked',
      'late_withdrawal', v_late,
      'turn_still_consumed', v_late
    ),
    p_actor, p_actor_kind
  );

  return v_candidate_season_player_id;
end;
$$;


ALTER FUNCTION "private"."handle_convoked_withdrawal"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."handle_match_notification_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_in_old_window boolean := false;
  v_date_changed boolean := false;
  v_new_opens_at timestamptz;
  v_new_state public.sport_availability_state;
begin
  if old.kickoff_at is not null then
    v_in_old_window := now() >= private.match_features_open_at(old.kickoff_at)
      and now() < old.kickoff_at;
  end if;

  if old.status = 'a_venir'
     and new.status = 'annule'
     and v_in_old_window then
    if not private.is_feature_enabled('notifications_paused') then
      perform public.internal_push_notify('match_cancelled', new.id);
    end if;
    return new;
  end if;

  if old.status = 'a_venir'
     and new.status = 'a_venir'
     and old.kickoff_at is distinct from new.kickoff_at
     and new.kickoff_at is not null
     and v_in_old_window then
    v_date_changed := (old.kickoff_at at time zone 'Europe/Paris')::date
      is distinct from (new.kickoff_at at time zone 'Europe/Paris')::date;

    if v_date_changed then
      v_new_opens_at := private.match_features_open_at(new.kickoff_at);
      v_new_state := case
        when now() >= new.kickoff_at then 'closed'::public.sport_availability_state
        when now() >= v_new_opens_at then 'open'::public.sport_availability_state
        else 'pending'::public.sport_availability_state
      end;

      update public.match_sport_participants participant
      set availability_status = 'no_response',
          availability_comment_private = null,
          availability_updated_at = null,
          availability_updated_by = null,
          convocation_status = 'not_applicable',
          convocation_manual_override = false,
          waitlist_recommended_not_convoked = false,
          waitlist_turn_should_consume = false,
          updated_at = now()
      where participant.match_id = new.id
        and participant.season_player_id is not null
        and participant.is_eligible;

      update public.match_sport_workflows workflow
      set availability_opens_at = v_new_opens_at,
          availability_state = v_new_state,
          availability_opened_at = case when v_new_state = 'open' then now() else null end,
          convocation_state = 'draft',
          convocation_published_at = null,
          convocation_version = workflow.convocation_version + 1,
          updated_at = now()
      where workflow.match_id = new.id;

      delete from public.push_notification_log
      where match_id = new.id and kind = 'prediction_j5';

      if not private.is_feature_enabled('notifications_paused') then
        insert into public.push_notification_log(match_id, kind, sent_at)
        values (new.id, 'match_rescheduled_date', now())
        on conflict (match_id, kind) do update set sent_at = excluded.sent_at;
        perform public.internal_push_notify('match_rescheduled_date', new.id);
      end if;
    else
      if not private.is_feature_enabled('notifications_paused') then
        perform public.internal_push_notify('match_rescheduled_time', new.id);
      end if;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."handle_match_notification_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_active_profile"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_active_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_feature_enabled"("p_key" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(
    (
      select f.enabled
      from private.app_feature_flags f
      where f.key = p_key
    ),
    false
  );
$$;


ALTER FUNCTION "private"."is_feature_enabled"("p_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_known_non_player_archive_name"("p_name" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE STRICT
    SET "search_path" TO ''
    AS $$
  select private.normalize_player_name(p_name)
    = private.normalize_player_name('Philippe Couzin');
$$;


ALTER FUNCTION "private"."is_known_non_player_archive_name"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_match_coach_or_admin"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.is_admin()
    or (
      private.is_active_profile()
      and exists (
        select 1
        from public.season_players sp
        join public.matches m on m.season_id = sp.season_id
        where m.id = p_match_id
          and sp.profile_id = (select auth.uid())
          and sp.is_coach = true
          and sp.is_active = true
      )
    );
$$;


ALTER FUNCTION "private"."is_match_coach_or_admin"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_match_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.is_admin();
$$;


ALTER FUNCTION "private"."is_match_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_moderator"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.is_admin(); $$;


ALTER FUNCTION "private"."is_moderator"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."list_admin_match_motm_votes"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'match_id', election.match_id,
      'opponent_name', opponent.name,
      'kickoff_at', match.kickoff_at,
      'score_as_grinta', match.score_as_grinta,
      'score_adverse', match.score_adverse,
      'state', election.state,
      'opens_at', election.opens_at,
      'closes_at', election.closes_at,
      'closed_at', election.closed_at,
      'finalization_version', election.finalization_version,
      'eligible_voter_count', eligible.count,
      'votes_received', votes.count,
      'candidate_count', candidates.count,
      'participation_rate', case
        when eligible.count = 0 then 0
        else round((votes.count::numeric * 100) / eligible.count, 1)
      end,
      'open_notification_sent', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_open'
      ),
      'reminder_notification_sent', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_reminder'
      ),
      'results_notification_sent', exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_results'
      )
    ) order by coalesce(election.closes_at, match.kickoff_at) desc, election.match_id
  ), '[]'::jsonb)
  into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  cross join lateral (
    select count(distinct profile.id)::integer as count
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
      and profile.status = 'active'
  ) eligible
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_motm_votes vote
    where vote.match_id = election.match_id
      and vote.finalization_version = election.finalization_version
  ) votes
  cross join lateral (
    select count(*)::integer as count
    from public.match_sport_participants participant
    where participant.match_id = election.match_id
      and participant.final_presence_status = 'present'
  ) candidates;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."list_admin_match_motm_votes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_features_open_at"("p_kickoff_at" timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE STRICT
    SET "search_path" TO ''
    AS $$
  select (
    (
      (p_kickoff_at at time zone 'Europe/Paris')::date - 6
    ) + time '12:00'
  ) at time zone 'Europe/Paris';
$$;


ALTER FUNCTION "private"."match_features_open_at"("p_kickoff_at" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "private"."match_features_open_at"("p_kickoff_at" timestamp with time zone) IS 'Noon Europe/Paris on the sixth calendar day before kickoff.';



CREATE OR REPLACE FUNCTION "private"."match_has_eligible_motm_ballot"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from private.match_motm_candidate_participants(p_match_id) voter_candidate
    join public.match_sport_participants voter
      on voter.id = voter_candidate.participant_id
    join public.season_players voter_player on voter_player.id = voter.season_player_id
    join public.profiles voter_profile on voter_profile.id = voter_player.profile_id
    join private.match_motm_candidate_participants(p_match_id) other_candidate
      on other_candidate.participant_id <> voter.id
    join public.match_sport_participants candidate
      on candidate.id = other_candidate.participant_id
    left join public.season_players candidate_player
      on candidate_player.id = candidate.season_player_id
    where voter_profile.status = 'active'
      and (
        candidate.guest_player_id is not null
        or candidate_player.profile_id is distinct from voter_profile.id
      )
  );
$$;


ALTER FUNCTION "private"."match_has_eligible_motm_ballot"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_live_snapshot"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."match_live_snapshot"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_motm_anchor_version"("p_match_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(
    (
      select max(pub.version)
      from public.match_composition_publications pub
      where pub.match_id = p_match_id
    ),
    (
      select max(version.version)
      from public.match_sport_finalization_versions version
      where version.match_id = p_match_id
    ),
    1
  );
$$;


ALTER FUNCTION "private"."match_motm_anchor_version"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_motm_candidate_participants"("p_match_id" "uuid") RETURNS TABLE("participant_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.final_presence_status = 'present'
      or exists (
        select 1 from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
    );
$$;


ALTER FUNCTION "private"."match_motm_candidate_participants"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_motm_opens_at"("p_match_id" "uuid") RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select finalization.validated_at
  from public.match_sport_finalizations finalization
  where finalization.match_id = p_match_id;
$$;


ALTER FUNCTION "private"."match_motm_opens_at"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."match_motm_opens_at"("p_match_id" "uuid") IS 'Le vote HDM ouvre à la validation initiale du compte rendu.';



CREATE OR REPLACE FUNCTION "private"."match_motm_result_notification_payloads"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_election_state public.sport_vote_state;
  v_winner_names text;
  v_winner_count integer := 0;
  v_winner_profile_ids uuid[] := array[]::uuid[];
  v_general_profile_ids uuid[] := array[]::uuid[];
  v_general_title text;
  v_general_message text;
  v_winner_title text;
  v_winner_message text;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select election.state
  into v_election_state
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;

  if v_election_state is distinct from 'closed'::public.sport_vote_state then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select
    string_agg(winner.display_name, ', ' order by lower(winner.display_name)),
    count(*)::integer,
    coalesce(
      array_agg(distinct winner.profile_id)
        filter (where winner.profile_id is not null),
      array[]::uuid[]
    )
  into v_winner_names, v_winner_count, v_winner_profile_ids
  from (
    select
      case
        when guest.id is not null then
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
        else coalesce(
          nullif(btrim(profile.surnom), ''),
          nullif(btrim(profile.first_name), ''),
          nullif(btrim(player.first_name), ''),
          btrim(concat_ws(' ', player.first_name, player.last_name)),
          'Joueur'
        )
      end as display_name,
      profile.id as profile_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    left join public.season_players player
      on player.id = participant.season_player_id
    left join public.profiles profile
      on profile.id = player.profile_id
     and profile.status = 'active'
     and profile.notify_motm_vote
    left join public.guest_players guest
      on guest.id = participant.guest_player_id
    where result.match_id = p_match_id
      and result.is_winner
  ) winner;

  -- Aucun gagnant (par exemple aucun vote) : aucun push de résultat.
  if v_winner_count = 0 then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  -- Même population que l'ouverture du vote : joueurs candidats avec compte
  -- actif et préférence HDM activée. Les élus sont retirés du groupe collectif.
  select coalesce(array_agg(distinct profile.id), array[]::uuid[])
  into v_general_profile_ids
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player
    on player.id = participant.season_player_id
  join public.profiles profile
    on profile.id = player.profile_id
  where profile.status = 'active'
    and profile.notify_motm_vote
    and not (profile.id = any(v_winner_profile_ids));

  if v_winner_count = 1 then
    v_general_title := 'Homme du match';
    v_general_message := format('%s a été élu Homme du match !', v_winner_names);
    v_winner_title := 'Homme du match';
    v_winner_message := 'Bravo, tu as été élu Homme du match !';
  else
    v_general_title := 'Co-Hommes du match';
    v_general_message := format(
      '%s ont été élus co-Hommes du match !',
      v_winner_names
    );
    v_winner_title := 'Co-Homme du match';
    v_winner_message := 'Bravo, tu as été élu co-Homme du match !';
  end if;

  return jsonb_build_object(
    'general_profile_ids', to_jsonb(v_general_profile_ids),
    'winner_profile_ids', to_jsonb(v_winner_profile_ids),
    'general_title', v_general_title,
    'general_message', v_general_message,
    'winner_title', v_winner_title,
    'winner_message', v_winner_message
  );
end;
$$;


ALTER FUNCTION "private"."match_motm_result_notification_payloads"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."match_motm_result_notification_payloads"("p_match_id" "uuid") IS 'Prépare les notifications de résultat HDM selon notify_motm_vote, en séparant élus et autres destinataires.';



CREATE OR REPLACE FUNCTION "private"."match_notification_time_label"("p_kickoff_at" timestamp with time zone) RETURNS "text"
    LANGUAGE "sql" STABLE STRICT
    SET "search_path" TO ''
    AS $$
  select case
    when extract(minute from (p_kickoff_at at time zone 'Europe/Paris'))::integer = 0
      then to_char(p_kickoff_at at time zone 'Europe/Paris', 'HH24"h"')
    else to_char(p_kickoff_at at time zone 'Europe/Paris', 'HH24"h"MI')
  end;
$$;


ALTER FUNCTION "private"."match_notification_time_label"("p_kickoff_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_postgame_correction_closes_at"("p_match_id" "uuid") RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(
    (
      select finalization.validated_at + interval '24 hours'
      from public.match_sport_finalizations finalization
      where finalization.match_id = p_match_id
    ),
    (
      select match.result_validated_at + interval '24 hours'
      from public.matches match
      where match.id = p_match_id
    )
  );
$$;


ALTER FUNCTION "private"."match_postgame_correction_closes_at"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."match_postgame_correction_closes_at"("p_match_id" "uuid") IS 'Echéance immuable : première validation du compte rendu + exactement 24 heures.';



CREATE OR REPLACE FUNCTION "private"."match_prediction_closes_at"("p_kickoff_at" timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE STRICT
    SET "search_path" TO ''
    AS $$
  select p_kickoff_at - interval '15 minutes';
$$;


ALTER FUNCTION "private"."match_prediction_closes_at"("p_kickoff_at" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "private"."match_prediction_closes_at"("p_kickoff_at" timestamp with time zone) IS 'Instant commun de fermeture du prono et d ouverture du Live: T-15 minutes.';



CREATE OR REPLACE FUNCTION "private"."match_prediction_notification_at"("p_kickoff_at" timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE STRICT
    SET "search_path" TO ''
    AS $$
  select (
    (((p_kickoff_at at time zone 'Europe/Paris')::date - 5) + time '12:00')
    at time zone 'Europe/Paris'
  );
$$;


ALTER FUNCTION "private"."match_prediction_notification_at"("p_kickoff_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_sport_finalization_snapshot"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  with latest_publication as (
    select publication.version, publication.snapshot
    from public.match_composition_publications publication
    where publication.match_id = p_match_id
    order by publication.version desc
    limit 1
  ), planned_entries as (
    select
      (entry ->> 'participant_id')::uuid as participant_id,
      entry ->> 'zone' as planned_zone
    from latest_publication publication,
      lateral jsonb_array_elements(
        coalesce(publication.snapshot -> 'entries', '[]'::jsonb)
      ) entry
  )
  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'is_home', match.location = 'domicile',
    'kickoff_at', match.kickoff_at,
    'match_status', match.status,
    'is_validated', finalization.match_id is not null,
    'version', coalesce(finalization.version, 0),
    'score_as_grinta', coalesce(finalization.score_as_grinta, match.score_as_grinta, 0),
    'score_adverse', coalesce(finalization.score_adverse, match.score_adverse, 0),
    'composition_version', coalesce(finalization.composition_version, workflow.composition_version, 0),
    'presence_state', workflow.presence_state,
    'vote_state', workflow.vote_state,
    'validated_at', finalization.validated_at,
    'corrected_at', finalization.corrected_at,
    'participants', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'is_guest', participant.guest_player_id is not null,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
            nullif(btrim(player.first_name), ''),
            btrim(concat_ws(' ', player.first_name, player.last_name))
          )
        end,
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'planned_zone', coalesce(planned.planned_zone, case participant.selection_status
          when 'starter' then 'field'
          when 'substitute' then 'bench'
          when 'not_selected' then 'not_selected'
          else 'available'
        end),
        'present', case
          when finalization.match_id is not null then participant.final_presence_status = 'present'
          else coalesce(planned.planned_zone in ('field', 'bench'), false)
        end,
        'final_presence_status', participant.final_presence_status,
        'final_selection_status', case
          when finalization.match_id is not null then participant.final_selection_status
          when planned.planned_zone = 'field' then 'starter'::public.sport_selection_status
          when planned.planned_zone = 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        'goals', participant.final_goals,
        'clean_sheet', participant.final_clean_sheet,
        'is_motm', exists (
          select 1
          from public.match_sport_motm_results result
          where result.match_id = p_match_id
            and result.participant_id = participant.id
            and result.is_winner
            and result.finalization_version = (
              select max(latest.finalization_version)
              from public.match_sport_motm_results latest
              where latest.match_id = p_match_id
            )
        )
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(profile.surnom, profile.first_name, player.first_name, guest.first_name)),
        participant.id
    ) filter (
      where participant.id is not null
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  left join public.match_sport_participants participant on participant.match_id = match.id
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$$;


ALTER FUNCTION "private"."match_sport_finalization_snapshot"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."match_weather_refresh_interval"("p_kickoff_at" timestamp with time zone, "p_now" timestamp with time zone) RETURNS interval
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select case
    when p_kickoff_at - p_now > interval '72 hours' then interval '12 hours'
    when p_kickoff_at - p_now > interval '24 hours' then interval '6 hours'
    when p_kickoff_at - p_now > interval '6 hours' then interval '2 hours'
    else interval '1 hour'
  end;
$$;


ALTER FUNCTION "private"."match_weather_refresh_interval"("p_kickoff_at" timestamp with time zone, "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."merge_player_identities"("p_source_player_id" "uuid", "p_target_player_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if p_source_player_id is null
     or p_target_player_id is null
     or p_source_player_id = p_target_player_id then
    return;
  end if;

  if not exists (
    select 1 from public.players p where p.id = p_source_player_id
  ) or not exists (
    select 1 from public.players p where p.id = p_target_player_id
  ) then
    raise exception 'Canonical player identity not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.profiles p where p.player_id = p_source_player_id
  ) then
    raise exception 'Cannot merge two account-backed player identities'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.historical_match_players source_row
    join public.historical_match_players target_row
      on target_row.match_id = source_row.match_id
     and target_row.player_id = p_target_player_id
    where source_row.player_id = p_source_player_id
  ) then
    raise exception 'Archived match contains both player identities; manual resolution required'
      using errcode = '23514';
  end if;

  delete from public.player_aliases source_alias
  using public.player_aliases target_alias
  where source_alias.player_id = p_source_player_id
    and target_alias.player_id = p_target_player_id
    and private.normalize_player_name(source_alias.alias)
      = private.normalize_player_name(target_alias.alias);

  update public.player_aliases
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_match_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.historical_player_name_links
  set player_id = p_target_player_id, updated_at = now()
  where player_id = p_source_player_id;

  update public.historical_player_statistics
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.guest_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  update public.season_players
  set player_id = p_target_player_id
  where player_id = p_source_player_id;

  delete from public.players
  where id = p_source_player_id;
end;
$$;


ALTER FUNCTION "private"."merge_player_identities"("p_source_player_id" "uuid", "p_target_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."normalize_player_name"("p_name" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    SET "search_path" TO ''
    AS $$
  select lower(regexp_replace(btrim(p_name), '\s+', ' ', 'g'));
$$;


ALTER FUNCTION "private"."normalize_player_name"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."normalize_waitlisted_withdrawal"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."normalize_waitlisted_withdrawal"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."normalize_waitlisted_withdrawal"() IS 'Waives a pending waitlist turn when a non-convoked player becomes absent at or before the cutoff.';



CREATE OR REPLACE FUNCTION "private"."notify_admins_of_pending_signup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
  v_admin_ids uuid[];
  v_display_name text;
begin
  begin
    select array_agg(p.id)
    into v_admin_ids
    from public.profiles p
    where p.role = 'admin' and p.status = 'active';

    if v_admin_ids is null or array_length(v_admin_ids, 1) = 0 then
      return new;
    end if;

    select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name = 'push_internal_token';

    if v_token is null then
      return new;
    end if;

    v_display_name := nullif(
      btrim(concat_ws(' ', new.first_name, new.last_name)),
      ''
    );

    perform net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'admin_pending_signup',
        'profile_ids', to_jsonb(v_admin_ids),
        'display_name', coalesce(v_display_name, 'Un joueur')
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    raise warning 'notify_admins_of_pending_signup failed: %', sqlerrm;
  end;

  return new;
end;
$$;


ALTER FUNCTION "private"."notify_admins_of_pending_signup"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."notify_admins_of_pending_signup"() IS 'Push notification to every active admin when a new account registers and needs validation.';



CREATE OR REPLACE FUNCTION "private"."notify_waitlist_promotion"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile_id uuid;
begin
  if old.convocation_status = 'not_convoked'
     and new.convocation_status = 'convoked'
     and exists (
       select 1 from public.match_sport_workflows workflow
       where workflow.match_id = new.match_id
         and workflow.convocation_state = 'published'
     ) then
    select player.profile_id
    into v_profile_id
    from public.season_players player
    join public.profiles profile on profile.id = player.profile_id
    where player.id = new.season_player_id
      and profile.status = 'active'
      and profile.notify_convocation;

    if v_profile_id is not null then
      perform private.dispatch_convocation_push(new.match_id, v_profile_id);
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."notify_waitlist_promotion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    raise exception 'Coach, administrator or moderator role required'
      using errcode = '42501';
  end if;

  select match.status, match.kickoff_at, match.planned_duration_minutes
  into v_match_status, v_kickoff_at, v_default_duration
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Live tracking is only available for upcoming matches'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select session.state into v_existing_state
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if found and v_existing_state <> 'not_started' then
    return private.match_live_snapshot(p_match_id);
  end if;

  if now() < v_kickoff_at - interval '15 minutes' then
    raise exception 'Le Live ouvre 15 minutes avant le coup d’envoi.'
      using errcode = '22023';
  end if;

  if found then
    update public.match_live_sessions
    set planned_duration_minutes = greatest(
          1,
          least(
            200,
            coalesce(p_planned_duration_minutes, planned_duration_minutes)
          )
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
    match_id,
    state,
    planned_duration_minutes,
    updated_by
  ) values (
    p_match_id,
    'not_started',
    greatest(
      1,
      least(200, coalesce(p_planned_duration_minutes, v_default_duration))
    ),
    v_actor
  )
  on conflict (match_id) do update
  set planned_duration_minutes = greatest(
        1,
        least(
          200,
          coalesce(
            p_planned_duration_minutes,
            match_live_sessions.planned_duration_minutes
          )
        )
      ),
      updated_by = v_actor,
      updated_at = now();

  delete from public.match_composition_entries
  where match_id = p_match_id;

  insert into public.match_composition_entries (
    match_id,
    participant_id,
    zone,
    x,
    y,
    slot_label,
    sort_order
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
$$;


ALTER FUNCTION "private"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text" DEFAULT NULL::"text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_reason text := nullif(btrim(p_reason), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('no_response', 'available', 'absent') then
    raise exception 'Invalid availability override status' using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception 'Override reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Override reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status <> 'absent' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and participant.is_eligible
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'staff'
    );

    if v_convocation_state = 'published'
       and v_old_status = 'available'
       and v_new_status = 'absent' then
      v_promoted_player_id := private.handle_convoked_withdrawal(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    elsif v_convocation_state = 'published'
       and v_old_status = 'absent'
       and v_new_status = 'available' then
      v_promoted_player_id := private.restore_returning_convoked_player(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    else
      perform private.recompute_match_convocations_internal(p_match_id, false);
    end if;

    insert into private.sport_admin_audit_log (
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id, 'override_availability', v_actor, v_reason,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'season_player_id', p_season_player_id,
        'old_status', v_old_status,
        'new_status', v_new_status,
        'promoted_season_player_id', v_promoted_player_id
      )
    );
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id
  );
end;
$$;


ALTER FUNCTION "private"."override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_system_actor constant uuid := '00000000-0000-0000-0000-000000000001'::uuid;
begin
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;
  if p_profile_id = v_system_actor then
    raise exception 'Technical profile cannot be deleted' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = v_system_actor) then
    raise exception 'Technical replacement profile is missing' using errcode = '55000';
  end if;

  delete from public.sport_availability_notification_events
  where profile_id = p_profile_id;

  delete from public.match_sport_motm_votes
  where voter_profile_id = p_profile_id;

  update private.sport_admin_audit_log
  set actor_profile_id = v_system_actor
  where actor_profile_id = p_profile_id;

  update public.guest_players
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.guest_players
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

  update public.match_composition_publications
  set published_by = v_system_actor
  where published_by = p_profile_id;

  update public.match_compositions
  set last_modified_by = v_system_actor
  where last_modified_by = p_profile_id;
  update public.match_compositions
  set published_by = v_system_actor
  where published_by = p_profile_id;

  update public.match_sport_finalization_versions
  set created_by = v_system_actor
  where created_by = p_profile_id;

  update public.match_sport_finalizations
  set validated_by = v_system_actor
  where validated_by = p_profile_id;
  update public.match_sport_finalizations
  set corrected_by = null
  where corrected_by = p_profile_id;

  update public.match_sport_workflows
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.match_sport_workflows
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  update public.sport_waitlist_entries
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.sport_waitlist_entries
  set updated_by = v_system_actor
  where updated_by = p_profile_id;
end;
$$;


ALTER FUNCTION "private"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") IS 'Nettoie ou réattribue les références historiques bloquantes avant la suppression Auth d un profil.';



CREATE OR REPLACE FUNCTION "private"."process_match_motm_jobs"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_transitions integer;
  v_open_notifications integer;
  v_result_notifications integer;
begin
  v_transitions := private.close_due_match_motm_elections();
  v_open_notifications := private.push_due_motm_open_notifications(p_now);
  v_result_notifications := private.push_due_motm_result_notifications(p_now);
  return jsonb_build_object(
    'transitions', v_transitions,
    'open_notifications', v_open_notifications,
    'result_notifications', v_result_notifications
  );
end;
$$;


ALTER FUNCTION "private"."process_match_motm_jobs"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."process_sport_availability_notifications"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row record;
  v_event_id bigint;
  v_opened integer := 0;
  v_closed integer := 0;
  v_created integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'opened_workflows', 0,
      'closed_workflows', 0,
      'notifications_created', 0
    );
  end if;

  with opened as (
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, p_now),
        updated_at = p_now
    from public.matches match
    where match.id = workflow.match_id
      and match.status = 'a_venir'
      and match.kickoff_at > p_now
      and workflow.availability_state = 'pending'
      and workflow.availability_opens_at <= p_now
    returning workflow.match_id
  )
  select count(*)::integer into v_opened from opened;

  with closed as (
    update public.match_sport_workflows workflow
    set availability_state = 'closed', updated_at = p_now
    from public.matches match
    where match.id = workflow.match_id
      and workflow.availability_state <> 'closed'
      and (match.status <> 'a_venir' or match.kickoff_at <= p_now)
    returning workflow.match_id
  )
  select count(*)::integer into v_closed from closed;

  if private.is_feature_enabled('notifications_paused') then
    return jsonb_build_object(
      'opened_workflows', v_opened,
      'closed_workflows', v_closed,
      'notifications_created', 0
    );
  end if;

  for v_row in
    select
      workflow.match_id,
      workflow.availability_opens_at,
      workflow.availability_opened_at,
      participant.id as participant_id,
      player.profile_id
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    join public.match_sport_participants participant on participant.match_id = workflow.match_id
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > p_now
      and participant.is_eligible
      and profile.status = 'active'
      and not exists (
        select 1
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
          and event.kind = 'availability_open'
          and event.source = 'automatic'
          and event.scheduled_for = workflow.availability_opens_at
      )
      and not exists (
        select 1
        from public.push_notification_log log
        where log.match_id = workflow.match_id
          and log.kind = 'match_rescheduled_date'
          and workflow.availability_opened_at is not null
          and log.sent_at >= workflow.availability_opened_at
      )
    order by match.kickoff_at, participant.id
  loop
    v_event_id := private.create_sport_availability_notification(
      v_row.match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_open',
      'automatic',
      v_row.availability_opens_at,
      null,
      null
    );
    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'opened_workflows', v_opened,
    'closed_workflows', v_closed,
    'notifications_created', v_created
  );
end;
$$;


ALTER FUNCTION "private"."process_sport_availability_notifications"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_match_status text;
  v_squad_limit integer;
  v_convocation_state public.sport_convocation_state;
  v_current_version integer;
  v_has_unpublished_changes boolean;
  v_field_count integer;
  v_bench_count integer;
  v_available_count integer;
  v_selected_count integer;
  v_exception_used boolean;
  v_publication_kind text;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.status, workflow.squad_size_limit,
    workflow.convocation_state, composition.version,
    composition.has_unpublished_changes
  into v_match_status, v_squad_limit,
    v_convocation_state, v_current_version, v_has_unpublished_changes
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  join public.match_compositions composition on composition.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow, composition;

  if not found then
    raise exception 'Composition not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be published for this match state'
      using errcode = '22023';
  end if;
  if v_match_status = 'a_venir' and v_convocation_state <> 'published' then
    raise exception 'Convocations must be available before the composition'
      using errcode = '22023';
  end if;

  if v_current_version > 0 and not coalesce(v_has_unpublished_changes, false) then
    return private.composition_snapshot(p_match_id);
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone = 'bench'),
    count(*) filter (where zone = 'available')
  into v_field_count, v_bench_count, v_available_count
  from public.match_composition_entries
  where match_id = p_match_id;

  v_selected_count := v_field_count + v_bench_count;
  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_available_count > 0 then
    raise exception 'Every selected player must be placed on the field or bench before publication'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;

  v_exception_used := v_selected_count > v_squad_limit;
  v_publication_kind := case
    when v_match_status in ('termine', 'archive') then 'postmatch'
    when v_current_version = 0 then 'initial'
    else 'update'
  end;

  update public.match_compositions composition
  set status = case
        when v_current_version = 0
          then 'published'::public.sport_composition_state
        else 'updated'::public.sport_composition_state
      end,
      version = v_current_version + 1,
      has_unpublished_changes = false,
      squad_size_exception_approved = v_exception_used,
      published_at = now(),
      published_by = v_actor,
      last_modified_at = now(),
      last_modified_by = v_actor
  where composition.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = case
        when v_current_version = 0
          then 'published'::public.sport_composition_state
        else 'updated'::public.sport_composition_state
      end,
      composition_version = v_current_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', v_publication_kind
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot, publication_kind, published_by
  ) values (
    p_match_id,
    v_current_version + 1,
    (select formation_code from public.match_compositions where match_id = p_match_id),
    v_snapshot,
    v_publication_kind,
    v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_match_status in ('termine', 'archive')
      then 'publish_postmatch_composition'
      else 'update_composition'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_current_version + 1,
      'publication_kind', v_publication_kind,
      'field_count', v_field_count,
      'bench_count', v_bench_count,
      'match_status', v_match_status
    )
  );

  return v_snapshot;
end;
$$;


ALTER FUNCTION "private"."publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."publish_match_convocations"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_summary jsonb;
  v_unresolved integer;
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_summary := private.recompute_match_convocations_internal(p_match_id, false);

  select count(*)::integer into v_unresolved
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and participant.convocation_status = 'not_applicable';

  if v_unresolved > 0 then
    raise exception 'Every available player needs a convocation decision'
      using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set convocation_state = 'published',
      convocation_version = convocation_version + 1,
      convocation_published_at = coalesce(convocation_published_at, now()),
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants
  set waitlist_turn_state = case
        when waitlist_turn_should_consume then
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        else
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'waived'::public.sport_waitlist_turn_state
          end
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where match_id = p_match_id
    and is_eligible
    and availability_status = 'available';

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'publish_convocations', v_actor, v_reason, v_summary
  );

  return private.get_match_convocations(p_match_id);
end;
$$;


ALTER FUNCTION "private"."publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_kickoff_at timestamptz;
  v_match_status text;
  v_payload_count integer;
  v_input_count integer;
  v_missing_count integer;
  v_invalid_count integer;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit is null
     or p_squad_size_limit < 1
     or p_squad_size_limit > 30 then
    raise exception 'Squad size limit must be between 1 and 30'
      using errcode = '22023';
  end if;
  if p_decisions is null or jsonb_typeof(p_decisions) <> 'array' then
    raise exception 'Effectif decisions must be a JSON array'
      using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.kickoff_at, match.status
  into v_kickoff_at, v_match_status
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Effectif can only be edited before kickoff'
      using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.effectif_input (
    season_player_id uuid primary key,
    status public.sport_convocation_status not null
  ) on commit drop;
  truncate table pg_temp.effectif_input;

  begin
    insert into pg_temp.effectif_input(season_player_id, status)
    select
      (item ->> 'season_player_id')::uuid,
      (item ->> 'status')::public.sport_convocation_status
    from jsonb_array_elements(p_decisions) item
    where item ->> 'status' in ('convoked', 'not_convoked');
  exception
    when unique_violation then
      raise exception 'A player can appear only once in effectif decisions'
        using errcode = '22023';
    when invalid_text_representation or not_null_violation then
      raise exception 'Invalid effectif decision' using errcode = '22023';
  end;

  v_payload_count := jsonb_array_length(p_decisions);
  select count(*)::integer into v_input_count
  from pg_temp.effectif_input;

  if v_input_count <> v_payload_count then
    raise exception 'Invalid effectif decision' using errcode = '22023';
  end if;

  select count(*)::integer into v_missing_count
  from public.match_sport_participants participant
  left join pg_temp.effectif_input input
    on input.season_player_id = participant.season_player_id
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status = 'available'
    and input.season_player_id is null;

  if v_missing_count > 0 then
    raise exception 'Every available permanent player needs one effectif decision'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_invalid_count
  from pg_temp.effectif_input input
  left join public.match_sport_participants participant
    on participant.match_id = p_match_id
   and participant.season_player_id = input.season_player_id
   and participant.is_eligible
   and participant.availability_status in (
     'available', 'absent', 'no_response'
   )
  where participant.id is null;

  if v_invalid_count > 0 then
    raise exception 'Effectif contains an ineligible player'
      using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_participants participant
  set convocation_status = input.status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume =
        input.status = 'not_convoked'
        and participant.availability_status = 'available',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when input.status = 'not_convoked'
             and participant.availability_status = 'available'
          then 'pending'::public.sport_waitlist_turn_state
        when input.status = 'convoked'
          then 'waived'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from pg_temp.effectif_input input
  where participant.match_id = p_match_id
    and participant.season_player_id = input.season_player_id
    and participant.is_eligible;

  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status <> 'available'
    and not exists (
      select 1
      from pg_temp.effectif_input input
      where input.season_player_id = participant.season_player_id
    );

  update public.match_sport_participants participant
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'waived',
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.guest_player_id is not null;

  v_result := private.publish_match_convocations(
    p_match_id,
    coalesce(v_reason, 'Mise à jour immédiate de l’effectif')
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'update_match_effectif',
    v_actor,
    v_reason,
    jsonb_build_object(
      'squad_size_limit', p_squad_size_limit,
      'convocation_version', v_result -> 'convocation_version'
    )
  );

  return private.get_match_convocations(p_match_id);
end;
$$;


ALTER FUNCTION "private"."publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") IS 'Publishes admin effectif decisions independently from player availability.';



CREATE OR REPLACE FUNCTION "private"."publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_exported boolean;
  v_finalize_result jsonb;
  v_current_version integer;
  v_next_version integer;
  v_formation_code text;
  v_squad_limit integer;
  v_present_count integer;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported
  into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state <> 'finished' then
    raise exception 'End the match before exporting its recap' using errcode = '22023';
  end if;
  if v_exported then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;

  perform set_config('as_grinta.allow_coach_live_finalize', 'on', true);

  v_finalize_result := private.finalize_match_sport_postgame(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse,
    p_participants,
    p_reason
  );

  select composition.version, composition.formation_code,
         workflow.squad_size_limit
  into v_current_version, v_formation_code, v_squad_limit
  from public.match_compositions composition
  join public.match_sport_workflows workflow
    on workflow.match_id = composition.match_id
  where composition.match_id = p_match_id
  for update of composition, workflow;

  if found then
    perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

    update public.match_composition_entries entry
    set zone = case
          when participant.final_presence_status <> 'present'
            then 'not_selected'::public.sport_composition_zone
          when entry.zone = 'field'
            then 'field'::public.sport_composition_zone
          else 'bench'::public.sport_composition_zone
        end,
        x = case
          when participant.final_presence_status = 'present'
           and entry.zone = 'field' then entry.x
          else null
        end,
        y = case
          when participant.final_presence_status = 'present'
           and entry.zone = 'field' then entry.y
          else null
        end,
        slot_label = case
          when participant.final_presence_status = 'present'
           and entry.zone = 'field' then entry.slot_label
          else null
        end
    from public.match_sport_participants participant
    where entry.match_id = p_match_id
      and participant.match_id = p_match_id
      and participant.id = entry.participant_id;

    insert into public.match_composition_entries(
      match_id, participant_id, zone, x, y, slot_label, sort_order
    )
    select
      p_match_id,
      participant.id,
      case
        when participant.final_presence_status = 'present'
          then 'bench'::public.sport_composition_zone
        else 'not_selected'::public.sport_composition_zone
      end,
      null,
      null,
      null,
      900 + row_number() over (order by participant.id)::integer
    from public.match_sport_participants participant
    where participant.match_id = p_match_id
      and (
        participant.is_eligible
        or participant.final_presence_status <> 'pending'
      )
      and not exists (
        select 1
        from public.match_composition_entries existing
        where existing.match_id = p_match_id
          and existing.participant_id = participant.id
      );

    update public.match_sport_participants participant
    set selection_status = case entry.zone
          when 'field' then 'starter'::public.sport_selection_status
          when 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        final_selection_status = case entry.zone
          when 'field' then 'starter'::public.sport_selection_status
          when 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        selection_updated_at = now(),
        selection_updated_by = v_actor,
        updated_at = now()
    from public.match_composition_entries entry
    where participant.match_id = p_match_id
      and entry.match_id = p_match_id
      and entry.participant_id = participant.id;

    select count(*)::integer
    into v_present_count
    from public.match_sport_participants
    where match_id = p_match_id
      and final_presence_status = 'present';

    v_next_version := v_current_version + 1;

    update public.match_compositions
    set formation_code = v_formation_code,
        status = 'published',
        version = v_next_version,
        has_unpublished_changes = false,
        squad_size_exception_approved = v_present_count > v_squad_limit,
        published_at = now(),
        published_by = v_actor,
        last_modified_at = now(),
        last_modified_by = v_actor
    where match_id = p_match_id;

    update public.match_sport_workflows
    set composition_state = 'published',
        composition_version = v_next_version,
        updated_by = v_actor,
        updated_at = now()
    where match_id = p_match_id;

    update public.match_sport_finalizations
    set composition_version = v_next_version,
        updated_at = now()
    where match_id = p_match_id;

    v_snapshot := private.composition_snapshot(p_match_id)
      || jsonb_build_object(
        'published_at', now(),
        'publication_kind', 'postmatch'
      );

    insert into public.match_composition_publications(
      match_id,
      version,
      formation_code,
      snapshot,
      publication_kind,
      published_by
    ) values (
      p_match_id,
      v_next_version,
      v_formation_code,
      v_snapshot,
      'postmatch',
      v_actor
    );

    insert into private.sport_admin_audit_log(
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id,
      'publish_live_postmatch_composition',
      v_actor,
      p_reason,
      jsonb_build_object(
        'composition_version', v_next_version,
        'present_count', v_present_count,
        'source', 'live_recap'
      )
    );
  end if;

  update public.match_live_sessions
  set exported = true,
      exported_at = now(),
      score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  return v_finalize_result;
end;
$$;


ALTER FUNCTION "private"."publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."push_due_motm_open_notifications"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row record;
  v_sent integer := 0;
begin
  if private.is_feature_enabled('notifications_paused')
     or not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state = 'open'
      and election.opens_at <= p_now
      and election.closes_at > p_now
      and not exists (
        select 1 from public.push_notification_log log
        where log.match_id = election.match_id and log.kind = 'motm_open'
      )
    order by election.opens_at, election.match_id
    for update skip locked
  loop
    insert into public.push_notification_log(match_id, kind, sent_at)
    values (v_row.match_id, 'motm_open', p_now)
    on conflict do nothing;
    if found then
      perform private.dispatch_motm_push('motm_open', v_row.match_id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;


ALTER FUNCTION "private"."push_due_motm_open_notifications"("p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."push_due_motm_result_notifications"("p_now" timestamp with time zone DEFAULT "now"()) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row record;
  v_sent integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state = 'closed'
      and election.closed_at is not null
      and election.closed_at >= p_now - interval '30 days'
      and (
        not exists (
          select 1 from public.push_notification_log log
          where log.match_id = election.match_id
            and log.kind = 'motm_result_general'
        )
        or not exists (
          select 1 from public.push_notification_log log
          where log.match_id = election.match_id
            and log.kind = 'motm_result_winner'
        )
      )
    order by election.closed_at, election.match_id
  loop
    if private.try_motm_result_notification(
      'motm_result_general',
      v_row.match_id,
      p_now
    ) then
      v_sent := v_sent + 1;
    end if;
    if private.try_motm_result_notification(
      'motm_result_winner',
      v_row.match_id,
      p_now
    ) then
      v_sent := v_sent + 1;
    end if;
  end loop;

  return v_sent;
end;
$$;


ALTER FUNCTION "private"."push_due_motm_result_notifications"("p_now" timestamp with time zone) OWNER TO "postgres";


COMMENT ON FUNCTION "private"."push_due_motm_result_notifications"("p_now" timestamp with time zone) IS 'Réessaie les notifications de résultat HDM non mises en file à la clôture.';



CREATE OR REPLACE FUNCTION "private"."recompute_match_convocations_internal"("p_match_id" "uuid", "p_reset_overrides" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_limit integer;
  v_available integer;
  v_convoked integer;
  v_not_convoked integer;
  v_over_limit integer;
begin
  perform private.require_sports_management_enabled();

  select match.season_id, workflow.squad_size_limit
  into v_season_id, v_limit
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  perform private.finalize_due_waitlist_turns_for_season(v_season_id);
  perform private.ensure_sport_waitlist(v_season_id, v_actor);

  update public.match_sport_participants participant
  set convocation_manual_override = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and p_reset_overrides;

  -- Les inéligibles et les non-disponibles sans décision manuelle restent
  -- hors effectif. Une décision explicite de l'admin est conservée même si
  -- la disponibilité vaut absent ou no_response.
  update public.match_sport_participants participant
  set convocation_status = 'not_applicable',
      convocation_manual_override = false,
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state in ('consumed', 'waived')
          then participant.waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and (
      not participant.is_eligible
      or (
        participant.availability_status <> 'available'
        and not participant.convocation_manual_override
      )
    );

  -- Les disponibles sans décision manuelle restent convoqués par défaut.
  update public.match_sport_participants participant
  set convocation_status = 'convoked',
      waitlist_position_snapshot = waitlist.position,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = case
        when participant.waitlist_turn_state in ('consumed', 'waived')
          then participant.waitlist_turn_state
        else 'not_applicable'::public.sport_waitlist_turn_state
      end,
      updated_at = now()
  from public.sport_waitlist_entries waitlist
  where participant.match_id = p_match_id
    and participant.season_player_id = waitlist.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
    and not participant.convocation_manual_override;

  -- Une décision prise avant la réponse devient pleinement active dès que le
  -- joueur se déclare disponible. La liste d'attente ne consomme jamais de
  -- tour tant que la disponibilité reste absente ou sans réponse.
  update public.match_sport_participants participant
  set waitlist_turn_should_consume =
        participant.convocation_status = 'not_convoked',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when participant.convocation_status = 'not_convoked'
          then 'pending'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.season_player_id is not null
    and participant.availability_status = 'available'
    and participant.convocation_manual_override
    and participant.convocation_status in ('convoked', 'not_convoked');

  update public.match_sport_workflows
  set convocation_generated_at = now(),
      updated_by = coalesce(v_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  select count(*)::integer into v_available
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available';

  select
    count(*) filter (
      where participant.convocation_status = 'convoked'
    )::integer,
    count(*) filter (
      where participant.convocation_status = 'not_convoked'
    )::integer
  into v_convoked, v_not_convoked
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.availability_status = 'available';

  v_over_limit := greatest(0, v_convoked - v_limit);

  return jsonb_build_object(
    'match_id', p_match_id,
    'squad_size_limit', v_limit,
    'available_count', v_available,
    'convoked_count', v_convoked,
    'not_convoked_count', v_not_convoked,
    'over_limit_count', v_over_limit
  );
end;
$$;


ALTER FUNCTION "private"."recompute_match_convocations_internal"("p_match_id" "uuid", "p_reset_overrides" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "private"."recompute_match_convocations_internal"("p_match_id" "uuid", "p_reset_overrides" boolean) IS 'Convokes every available player by default. Squad-limit overflow is advisory; only explicit admin overrides create waitlisted players.';



CREATE OR REPLACE FUNCTION "private"."refresh_historical_match_players"("p_match_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  delete from public.historical_match_players hmp
  where hmp.match_id = p_match_id;

  with field_row as (
    select
      h.match_id,
      btrim(e ->> 'name') as source_name,
      private.normalize_player_name(e ->> 'name') as normalized_name,
      true as is_present,
      true as is_starter,
      false as is_bench,
      false as is_motm,
      0::integer as goals,
      (e ->> 'is_gk')::boolean as is_goalkeeper,
      (e ->> 'x_pct')::numeric as x_pct,
      (e ->> 'y_pct')::numeric as y_pct,
      e ->> 'position_code' as position_code,
      e ->> 'position_label' as position_label
    from public.historical_match_details h
    cross join lateral jsonb_array_elements(coalesce(h.field_players, '[]'::jsonb)) e
    where h.match_id = p_match_id
      and btrim(coalesce(e ->> 'name', '')) <> ''
      and private.normalize_player_name(e ->> 'name')
        <> private.normalize_player_name('Poste laissé vide')
  ),
  bench_row as (
    select
      h.match_id,
      btrim(n.player_name) as source_name,
      private.normalize_player_name(n.player_name) as normalized_name,
      true, false, true, false, 0::integer,
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements_text(coalesce(h.bench_players, '[]'::jsonb)) n(player_name)
    where h.match_id = p_match_id
      and btrim(coalesce(n.player_name, '')) <> ''
  ),
  present_row as (
    select
      h.match_id,
      btrim(n.player_name) as source_name,
      private.normalize_player_name(n.player_name) as normalized_name,
      true, false, false, false, 0::integer,
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements_text(coalesce(h.present_names, '[]'::jsonb)) n(player_name)
    where h.match_id = p_match_id
      and btrim(coalesce(n.player_name, '')) <> ''
  ),
  scorer_row as (
    select
      h.match_id,
      btrim(e ->> 'name') as source_name,
      private.normalize_player_name(e ->> 'name') as normalized_name,
      true, false, false, false,
      coalesce((e ->> 'goals')::integer, 0),
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements(coalesce(h.scorers, '[]'::jsonb)) e
    where h.match_id = p_match_id
      and btrim(coalesce(e ->> 'name', '')) <> ''
  ),
  motm_row as (
    select
      h.match_id,
      btrim(n.player_name) as source_name,
      private.normalize_player_name(n.player_name) as normalized_name,
      true, false, false, true, 0::integer,
      null::boolean, null::numeric, null::numeric, null::text, null::text
    from public.historical_match_details h
    cross join lateral jsonb_array_elements_text(coalesce(h.motm_names, '[]'::jsonb)) n(player_name)
    where h.match_id = p_match_id
      and btrim(coalesce(n.player_name, '')) <> ''
  ),
  all_row as (
    select * from field_row
    union all select * from bench_row
    union all select * from present_row
    union all select * from scorer_row
    union all select * from motm_row
  ),
  aggregated as (
    select
      row.match_id,
      row.normalized_name,
      min(row.source_name) as source_name,
      bool_or(row.is_present) as is_present,
      bool_or(row.is_starter) as is_starter,
      bool_or(row.is_bench) as is_bench,
      bool_or(row.is_motm) as is_motm,
      sum(row.goals)::integer as goals,
      bool_or(row.is_goalkeeper) filter (where row.is_goalkeeper is not null) as is_goalkeeper,
      max(row.x_pct) as x_pct,
      max(row.y_pct) as y_pct,
      max(row.position_code) as position_code,
      max(row.position_label) as position_label
    from all_row row
    where row.normalized_name <> private.normalize_player_name('Poste laissé vide')
    group by row.match_id, row.normalized_name
  ),
  resolved as materialized (
    select
      aggregated.*,
      private.resolve_historical_player_name(aggregated.source_name) as player_id
    from aggregated
  )
  insert into public.historical_match_players(
    match_id,
    player_id,
    source_name,
    is_present,
    is_starter,
    is_bench,
    is_motm,
    goals,
    is_goalkeeper,
    x_pct,
    y_pct,
    position_code,
    position_label
  )
  select
    resolved.match_id,
    resolved.player_id,
    resolved.source_name,
    resolved.is_present,
    resolved.is_starter,
    resolved.is_bench,
    resolved.is_motm,
    resolved.goals,
    resolved.is_goalkeeper,
    resolved.x_pct,
    resolved.y_pct,
    resolved.position_code,
    resolved.position_label
  from resolved
  where resolved.player_id is not null
  on conflict (match_id, player_id) do update
  set
    source_name = excluded.source_name,
    is_present = excluded.is_present,
    is_starter = excluded.is_starter,
    is_bench = excluded.is_bench,
    is_motm = excluded.is_motm,
    goals = excluded.goals,
    is_goalkeeper = excluded.is_goalkeeper,
    x_pct = excluded.x_pct,
    y_pct = excluded.y_pct,
    position_code = excluded.position_code,
    position_label = excluded.position_label;
end;
$$;


ALTER FUNCTION "private"."refresh_historical_match_players"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_guest_player_id uuid;
  v_match_status text;
  v_kickoff_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at
  into v_match_status, v_kickoff_at
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' or now() >= v_kickoff_at then
    raise exception 'Guests can only be managed before kickoff' using errcode = '22023';
  end if;

  select participant.guest_player_id into v_guest_player_id
  from public.match_sport_participants participant
  where participant.id = p_participant_id
    and participant.match_id = p_match_id
    and participant.guest_player_id is not null
    and participant.is_eligible
  for update;

  if not found then
    raise exception 'Active match guest not found' using errcode = 'P0002';
  end if;

  delete from public.match_composition_entries entry
  where entry.match_id = p_match_id
    and entry.participant_id = p_participant_id;

  update public.match_sport_participants participant
  set is_eligible = false,
      convocation_status = 'not_applicable',
      selection_status = 'not_selected',
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      final_presence_status = 'pending',
      final_presence_confirmed_at = null,
      final_presence_confirmed_by = null,
      updated_at = now()
  where participant.id = p_participant_id;

  update public.match_compositions composition
  set has_unpublished_changes = true,
      last_modified_at = now(),
      last_modified_by = v_actor
  where composition.match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id,
    match_id,
    event_type,
    old_value,
    new_value,
    actor_profile_id,
    actor_kind
  ) values (
    p_participant_id,
    p_match_id,
    'guest_removed',
    jsonb_build_object('eligible', true, 'guest_player_id', v_guest_player_id),
    jsonb_build_object('eligible', false, 'guest_player_id', v_guest_player_id),
    v_actor,
    'staff'
  );

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'remove_guest',
    v_actor,
    v_reason,
    jsonb_build_object(
      'guest_player_id', v_guest_player_id,
      'participant_id', p_participant_id
    )
  );

  return private.get_match_guests(p_match_id);
end;
$$;


ALTER FUNCTION "private"."remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."reopen_match_live"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_exported boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state <> 'finished' then
    raise exception 'Only a finished (not yet exported) match can be reopened' using errcode = '22023';
  end if;
  if v_exported then
    raise exception 'This match has already been exported and cannot be reopened' using errcode = '22023';
  end if;

  update public.match_live_sessions
  set state = 'paused',
      finished_at = null,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (p_match_id, 'reopen_match_live', v_actor, v_reason, '{}'::jsonb);

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."reopen_match_live"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_expected integer;
  v_given integer;
  v_distinct integer;
  v_old_order uuid[];
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, v_actor);

  select count(*)::integer into v_expected
  from public.sport_waitlist_entries entry
  where entry.season_id = v_season_id;

  v_given := coalesce(cardinality(p_ordered_player_ids), 0);
  select count(distinct item)::integer into v_distinct
  from unnest(coalesce(p_ordered_player_ids, '{}'::uuid[])) item;

  if v_given <> v_expected or v_distinct <> v_expected then
    raise exception 'The complete waitlist must be supplied without duplicates'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_ordered_player_ids) item
    where not exists (
      select 1 from public.sport_waitlist_entries entry
      where entry.season_id = v_season_id
        and entry.season_player_id = item
    )
  ) then
    raise exception 'Waitlist contains an unknown player' using errcode = '22023';
  end if;

  select array_agg(entry.season_player_id order by entry.position)
  into v_old_order
  from public.sport_waitlist_entries entry
  where entry.season_id = v_season_id;

  update public.sport_waitlist_entries
  set position = position + 10000
  where season_id = v_season_id;

  update public.sport_waitlist_entries entry
  set position = ordered.ordinality::integer,
      source = 'manual',
      updated_by = v_actor,
      updated_at = now()
  from unnest(p_ordered_player_ids) with ordinality
    as ordered(season_player_id, ordinality)
  where entry.season_id = v_season_id
    and entry.season_player_id = ordered.season_player_id;

  insert into private.sport_admin_audit_log (
    action, actor_profile_id, reason, metadata
  ) values (
    'reorder_waitlist', v_actor, v_reason,
    jsonb_build_object(
      'season_id', v_season_id,
      'old_order', to_jsonb(v_old_order),
      'new_order', to_jsonb(p_ordered_player_ids)
    )
  );

  return private.get_sport_waitlist(v_season_id);
end;
$$;


ALTER FUNCTION "private"."reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."request_match_weather_refresh"("p_match_id" "uuid" DEFAULT NULL::"uuid") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
  v_request_id bigint;
begin
  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return null;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := case
      when p_match_id is null then jsonb_build_object('kind', 'refresh_match_weather')
      else jsonb_build_object(
        'kind', 'refresh_match_weather',
        'match_id', p_match_id
      )
    end,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 15000
  ) into v_request_id;

  return v_request_id;
exception
  when others then
    return null;
end;
$$;


ALTER FUNCTION "private"."request_match_weather_refresh"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."require_sports_management_enabled"() RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_feature_enabled('sports_management') then
    raise exception 'Sports-management module is disabled' using errcode = '42501';
  end if;
end;
$$;


ALTER FUNCTION "private"."require_sports_management_enabled"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."resequence_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  create temporary table if not exists pg_temp.sport_waitlist_ranked (
    season_player_id uuid primary key,
    new_position integer not null
  ) on commit drop;
  truncate table pg_temp.sport_waitlist_ranked;

  insert into pg_temp.sport_waitlist_ranked(season_player_id, new_position)
  select entry.season_player_id,
    row_number() over (order by entry.position, entry.season_player_id)::integer
  from public.sport_waitlist_entries entry
  where entry.season_id = p_season_id;

  update public.sport_waitlist_entries entry
  set position = entry.position + 10000
  where entry.season_id = p_season_id;

  update public.sport_waitlist_entries entry
  set position = ranked.new_position,
      updated_by = p_actor,
      updated_at = now()
  from pg_temp.sport_waitlist_ranked ranked
  where entry.season_player_id = ranked.season_player_id;
end;
$$;


ALTER FUNCTION "private"."resequence_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."reset_internal_match_composition_on_first_effectif_publish"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if coalesce(old.convocation_version, 0) <> 0
     or coalesce(new.convocation_version, 0) <= 0 then
    return new;
  end if;

  if exists (
    select 1
    from public.matches match
    where match.id = new.match_id
      and match.match_type = 'entre_nous'
  ) then
    delete from public.match_internal_composition_entries
    where match_id = new.match_id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."reset_internal_match_composition_on_first_effectif_publish"() OWNER TO "postgres";


COMMENT ON FUNCTION "private"."reset_internal_match_composition_on_first_effectif_publish"() IS 'Au premier enregistrement de l''effectif d''un match entre nous, repart de deux équipes vides : tous les joueurs commencent dans Non affectés.';



CREATE OR REPLACE FUNCTION "private"."resolve_historical_player_name"("p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_name text := nullif(btrim(p_name), '');
  v_normalized_name text;
  v_player_id uuid;
  v_identity_count integer;
begin
  if v_name is null then
    return null;
  end if;

  v_normalized_name := private.normalize_player_name(v_name);
  if v_normalized_name = private.normalize_player_name('Poste laissé vide')
     or private.is_known_non_player_archive_name(v_name) then
    return null;
  end if;

  select link.player_id
  into v_player_id
  from public.historical_player_name_links link
  where link.normalized_name = v_normalized_name;

  if found then
    return v_player_id;
  end if;

  select
    count(distinct alias.player_id)::integer,
    min(alias.player_id::text)::uuid
  into v_identity_count, v_player_id
  from public.player_aliases alias
  where private.normalize_player_name(alias.alias) = v_normalized_name;

  -- 0 correspondance ou plusieurs homonymes : on ne devine pas. Une
  -- identité d'archive distincte est créée et restera stable pour ce libellé.
  if v_identity_count <> 1 then
    v_player_id := private.create_player_identity(v_name);
  end if;

  insert into public.historical_player_name_links(
    normalized_name,
    source_name,
    player_id
  )
  values (v_normalized_name, v_name, v_player_id)
  on conflict (normalized_name) do update
  set updated_at = now()
  returning player_id into v_player_id;

  return v_player_id;
end;
$$;


ALTER FUNCTION "private"."resolve_historical_player_name"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."resolve_open_sport_season"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
begin
  perform private.require_sports_management_enabled();

  if p_season_id is not null then
    select season.id into v_season_id
    from public.seasons season
    where season.id = p_season_id;
  else
    select season.id into v_season_id
    from public.seasons season
    where season.status = 'open'
    order by season.name desc, season.created_at desc
    limit 1;
  end if;

  if v_season_id is null then
    raise exception 'Sport season not found' using errcode = 'P0002';
  end if;
  return v_season_id;
end;
$$;


ALTER FUNCTION "private"."resolve_open_sport_season"("p_season_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."restart_match_live_session"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_state public.match_live_state;
  v_exported boolean;
  v_events integer;
  v_substitution record;
  v_x numeric(7,6);
  v_y numeric(7,6);
  v_slot_label text;
  v_in_order integer;
  v_out_order integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select session.state, session.exported
  into v_state, v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;
  if v_exported then
    raise exception 'This match has already been exported' using errcode = '22023';
  end if;
  if v_state = 'not_started' then
    raise exception 'The match has not been started yet' using errcode = '22023';
  end if;

  select count(*) into v_events
  from public.match_live_events
  where match_id = p_match_id;

  for v_substitution in
    select event.player_in_participant_id as player_in,
           event.player_out_participant_id as player_out
    from public.match_live_events event
    where event.match_id = p_match_id
      and event.event_type = 'substitution'
    order by event.created_at desc, event.id desc
  loop
    select entry.x, entry.y, entry.slot_label, entry.sort_order
    into v_x, v_y, v_slot_label, v_in_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.participant_id = v_substitution.player_in
      and entry.zone = 'field';

    continue when not found;

    select entry.sort_order into v_out_order
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.participant_id = v_substitution.player_out;

    update public.match_composition_entries
    set zone = 'bench',
        x = null,
        y = null,
        slot_label = null,
        sort_order = coalesce(v_out_order, sort_order)
    where match_id = p_match_id
      and participant_id = v_substitution.player_in;

    update public.match_composition_entries
    set zone = 'field',
        x = v_x,
        y = v_y,
        slot_label = v_slot_label,
        sort_order = v_in_order
    where match_id = p_match_id
      and participant_id = v_substitution.player_out;
  end loop;

  delete from public.match_live_events where match_id = p_match_id;

  update public.match_live_sessions
  set state = 'not_started',
      half = 1,
      elapsed_seconds = 0,
      running_since = null,
      score_as_grinta = 0,
      score_adverse = 0,
      started_at = null,
      finished_at = null,
      starting_composition_version = null,
      starting_lineup_snapshot = null,
      lineup_revision = lineup_revision + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_match_live', v_actor, v_reason,
    jsonb_build_object('deleted_events', v_events, 'previous_state', v_state)
  );

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."restore_returning_convoked_player"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_current_status public.sport_convocation_status;
  v_manual_override boolean;
  v_was_convoked boolean := false;
  v_promoted_id uuid;
  v_promoted_season_player_id uuid;
begin
  select participant.convocation_status,
    participant.convocation_manual_override
  into v_current_status, v_manual_override
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.id = p_participant_id
    and participant.is_eligible
  for update;

  if not found then
    return null;
  end if;

  if v_manual_override
     and v_current_status in ('convoked', 'not_convoked') then
    update public.match_sport_participants participant
    set waitlist_turn_should_consume =
          v_current_status = 'not_convoked',
        waitlist_turn_state = case
          when participant.waitlist_turn_state = 'consumed'
            then 'consumed'::public.sport_waitlist_turn_state
          when v_current_status = 'not_convoked'
            then 'pending'::public.sport_waitlist_turn_state
          else 'waived'::public.sport_waitlist_turn_state
        end,
        waitlist_turn_updated_at = now(),
        updated_at = now()
    where participant.id = p_participant_id;
    return null;
  end if;

  select exists (
    select 1
    from public.match_sport_participant_events event
    where event.match_id = p_match_id
      and event.participant_id = p_participant_id
      and event.event_type = 'convoked_player_withdrew'
  )
  into v_was_convoked;

  select candidate.id, candidate.season_player_id
  into v_promoted_id, v_promoted_season_player_id
  from public.match_sport_participants candidate
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = candidate.season_player_id
  where candidate.match_id = p_match_id
    and candidate.is_eligible
    and candidate.convocation_status = 'convoked'
    and candidate.promoted_from_participant_id = p_participant_id
  order by candidate.promoted_after_withdrawal_at desc nulls last,
    waitlist.position,
    candidate.id
  limit 1
  for update of candidate;

  v_was_convoked := v_was_convoked or v_promoted_id is not null;

  if not v_was_convoked then
    update public.match_sport_participants
    set convocation_status = 'not_convoked',
        convocation_manual_override = false,
        waitlist_turn_should_consume = true,
        waitlist_turn_state = 'pending',
        waitlist_turn_updated_at = now(),
        updated_at = now()
    where id = p_participant_id;
    return null;
  end if;

  update public.match_sport_participants
  set convocation_status = 'convoked',
      convocation_manual_override = true,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'waived',
      waitlist_turn_updated_at = now(),
      promoted_after_withdrawal_at = null,
      promoted_from_participant_id = null,
      updated_at = now()
  where id = p_participant_id;

  if v_promoted_id is not null then
    update public.match_sport_participants
    set convocation_status = 'not_convoked',
        convocation_manual_override = true,
        waitlist_turn_should_consume = true,
        waitlist_turn_state = 'pending',
        waitlist_turn_updated_at = now(),
        promoted_after_withdrawal_at = null,
        promoted_from_participant_id = null,
        updated_at = now()
    where id = v_promoted_id;
  end if;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = coalesce(p_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values (
    p_participant_id,
    p_match_id,
    'convoked_player_returned',
    jsonb_build_object('convocation_status', 'not_applicable'),
    jsonb_build_object('convocation_status', 'convoked'),
    p_actor,
    p_actor_kind
  );

  if v_promoted_id is not null then
    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_promoted_id,
      p_match_id,
      'promoted_player_returned_to_waitlist',
      jsonb_build_object('convocation_status', 'convoked'),
      jsonb_build_object('convocation_status', 'not_convoked'),
      p_actor,
      p_actor_kind
    );
  end if;

  return v_promoted_season_player_id;
end;
$$;


ALTER FUNCTION "private"."restore_returning_convoked_player"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_expected_count integer;
  v_input_count integer;
  v_selected_count integer;
  v_field_count integer;
  v_invalid_identity_count integer;
  v_invalid_zone_count integer;
  v_exception_used boolean := false;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Composition entries must be a JSON array' using errcode = '22023';
  end if;
  if v_formation is not null and char_length(v_formation) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select match.status, match.kickoff_at, workflow.squad_size_limit
  into v_match_status, v_kickoff_at, v_squad_limit
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be edited for this match state' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.composition_input;

  begin
    insert into pg_temp.composition_input (participant_id, zone, x, y, slot_label, sort_order)
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a composition' using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count from pg_temp.composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once' using errcode = '22023';
  end if;

  select count(*) into v_invalid_identity_count
  from pg_temp.composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and participant.is_eligible
  where participant.id is null;
  if v_invalid_identity_count > 0 then
    raise exception 'Composition contains an ineligible participant' using errcode = '22023';
  end if;

  select count(*) into v_invalid_zone_count
  from pg_temp.composition_input input
  join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
  where
    (
      input.zone = 'field'
      and (
        input.x is null or input.y is null
        or input.x < 0 or input.x > 1
        or input.y < 0 or input.y > 1
      )
    )
    or (
      input.zone <> 'field' and (input.x is not null or input.y is not null)
    )
    or (
      -- Avant le coup d'envoi, seule la convocation compte : un joueur noté
      -- absent ou sans réponse reste alignable si l'admin l'a convoqué.
      v_match_status = 'a_venir'
      and input.zone in ('field', 'bench', 'available')
      and participant.convocation_status <> 'convoked'
    )
    or (
      v_match_status in ('termine', 'archive')
      and input.zone in ('field', 'bench')
      and participant.final_presence_status <> 'present'
    );

  if v_invalid_zone_count > 0 then
    raise exception 'Composition zones conflict with presence or convocation decisions' using errcode = '22023';
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.composition_input;

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters' using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
    and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit' using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  insert into public.match_compositions (
    match_id, formation_code, status, version, has_unpublished_changes,
    squad_size_exception_approved, last_modified_by
  ) values (
    p_match_id, v_formation, 'draft', 0, true, v_exception_used, v_actor
  )
  on conflict (match_id) do update
  set formation_code = excluded.formation_code,
      has_unpublished_changes = true,
      squad_size_exception_approved = excluded.squad_size_exception_approved,
      last_modified_at = now(),
      last_modified_by = excluded.last_modified_by;

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        when 'not_selected' then 'not_selected'::public.sport_selection_status
        else 'undecided'::public.sport_selection_status
      end,
      final_selection_status = case
        when v_match_status in ('termine', 'archive') then case input.zone
          when 'field' then 'starter'::public.sport_selection_status
          when 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end
        else participant.final_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = case
        when workflow.composition_state = 'none' then 'draft'::public.sport_composition_state
        else workflow.composition_state
      end,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_match_status in ('termine', 'archive')
      then 'save_postmatch_composition'
      else 'save_composition_draft'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'formation_code', v_formation,
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.composition_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") IS 'Enregistre la composition d''un match. Avant le coup d''envoi, seule la convocation conditionne le droit d''aligner un joueur : la disponibilité déclarée ne bloque plus une décision d''administrateur.';



CREATE OR REPLACE FUNCTION "private"."save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.publish_match_effectif(
    p_match_id, p_squad_size_limit, p_decisions, p_reason
  );
$$;


ALTER FUNCTION "private"."save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_true_elapsed integer;
  v_minute integer;
  v_expected_count integer;
  v_input_count integer;
  v_invalid_count integer;
  v_field_count integer;
  v_bad_boundary_count integer;
  v_subs jsonb;
  v_sub_count integer;
  v_bad_sub_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Lineup entries must be a JSON array' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since, session.half
  into v_state, v_elapsed, v_running_since, v_half
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found or v_state not in ('not_started', 'running', 'paused', 'halftime') then
    raise exception 'The lineup can only be edited while the live session is open' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.live_lineup_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.live_lineup_input;

  begin
    insert into pg_temp.live_lineup_input (participant_id, zone, x, y, slot_label, sort_order)
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once' using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid lineup entry' using errcode = '22023';
  end;

  if exists (select 1 from pg_temp.live_lineup_input where zone = 'available') then
    raise exception 'Live lineup entries cannot use the available zone' using errcode = '22023';
  end if;

  select count(*) into v_input_count from pg_temp.live_lineup_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (participant.is_eligible or participant.final_presence_status <> 'pending');
  if v_input_count <> v_expected_count then
    raise exception 'Every eligible participant must appear exactly once' using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.live_lineup_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id and participant.match_id = p_match_id
  where participant.id is null
     or (input.zone = 'field' and (
       input.x is null or input.y is null
       or input.x < 0 or input.x > 1 or input.y < 0 or input.y > 1
     ))
     or (input.zone <> 'field' and (input.x is not null or input.y is not null));
  if v_invalid_count > 0 then
    raise exception 'Invalid lineup zone or coordinates' using errcode = '22023';
  end if;

  select count(*) into v_field_count from pg_temp.live_lineup_input where zone = 'field';
  if v_field_count > 11 then
    raise exception 'A lineup cannot contain more than 11 starters' using errcode = '22023';
  end if;

  -- Une salve : p_substitution accepte soit un couple {player_in, player_out},
  -- soit un tableau de couples appliques a la meme minute.
  create temporary table if not exists pg_temp.live_sub_input (
    player_in uuid not null,
    player_out uuid not null
  ) on commit drop;
  truncate table pg_temp.live_sub_input;

  if p_substitution is not null then
    if jsonb_typeof(p_substitution) = 'array' then
      v_subs := p_substitution;
    else
      v_subs := jsonb_build_array(p_substitution);
    end if;

    begin
      insert into pg_temp.live_sub_input (player_in, player_out)
      select (item ->> 'player_in')::uuid, (item ->> 'player_out')::uuid
      from jsonb_array_elements(v_subs) item;
    exception
      when invalid_text_representation or not_null_violation then
        raise exception 'Invalid substitution payload' using errcode = '22023';
    end;

    select count(*) into v_sub_count from pg_temp.live_sub_input;

    if exists (select 1 from pg_temp.live_sub_input where player_in = player_out) then
      raise exception 'Invalid substitution payload' using errcode = '22023';
    end if;

    -- Un meme joueur ne peut pas apparaitre deux fois dans la salve.
    if exists (
      select 1
      from (
        select player_in as participant_id from pg_temp.live_sub_input
        union all
        select player_out from pg_temp.live_sub_input
      ) involved
      group by involved.participant_id
      having count(*) > 1
    ) then
      raise exception 'A player cannot appear twice in the same substitution batch'
        using errcode = '22023';
    end if;

    -- Etat avant la salve : l'entrant n'etait pas sur le terrain, le
    -- sortant y etait.
    select count(*) into v_bad_sub_count
    from pg_temp.live_sub_input sub
    left join public.match_composition_entries old_in
      on old_in.match_id = p_match_id and old_in.participant_id = sub.player_in
    left join public.match_composition_entries old_out
      on old_out.match_id = p_match_id and old_out.participant_id = sub.player_out
    where coalesce(old_in.zone, 'not_selected') = 'field'
       or coalesce(old_out.zone, 'not_selected') <> 'field';
    if v_bad_sub_count > 0 then
      raise exception 'Substitution must bring in a non-field player and remove a field player'
        using errcode = '22023';
    end if;

    -- Etat apres la salve : l'entrant finit sur le terrain, le sortant non.
    select count(*) into v_bad_sub_count
    from pg_temp.live_sub_input sub
    left join pg_temp.live_lineup_input new_in
      on new_in.participant_id = sub.player_in
    left join pg_temp.live_lineup_input new_out
      on new_out.participant_id = sub.player_out
    where coalesce(new_in.zone, 'not_selected') <> 'field'
       or coalesce(new_out.zone, 'not_selected') = 'field';
    if v_bad_sub_count > 0 then
      raise exception 'The incoming player must end up on the field' using errcode = '22023';
    end if;
  end if;

  -- Sanity check: any zone crossing the field/bench boundary that wasn't
  -- flagged as the declared substitution is silently corrupting
  -- Remplacements/Faits du match and the times-benched counter — reject it.
  select count(*) into v_bad_boundary_count
  from pg_temp.live_lineup_input input
  join public.match_composition_entries old_entry
    on old_entry.match_id = p_match_id and old_entry.participant_id = input.participant_id
  where (old_entry.zone = 'field') <> (input.zone = 'field')
    and not exists (
      select 1 from pg_temp.live_sub_input sub
      where sub.player_in = input.participant_id
         or sub.player_out = input.participant_id
    );
  if v_bad_boundary_count > 0 then
    raise exception 'A field/bench change was not declared as a substitution' using errcode = '22023';
  end if;

  delete from public.match_composition_entries where match_id = p_match_id;
  insert into public.match_composition_entries (
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.live_lineup_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.live_lineup_input input
  where participant.id = input.participant_id and participant.match_id = p_match_id;

  update public.match_compositions
  set last_modified_at = now(), last_modified_by = v_actor
  where match_id = p_match_id;

  if coalesce(v_sub_count, 0) > 0 then
    v_true_elapsed := v_elapsed + case
      when v_state = 'running'
      then greatest(0, extract(epoch from now() - v_running_since))::integer
      else 0
    end;
    v_minute := v_true_elapsed / 60 + 1;

    -- Toute la salve porte la meme minute et la meme periode.
    insert into public.match_live_events (
      match_id, event_type, minute, half,
      player_in_participant_id, player_out_participant_id, created_by
    )
    select p_match_id, 'substitution', v_minute, v_half,
           sub.player_in, sub.player_out, v_actor
    from pg_temp.live_sub_input sub;
  end if;

  update public.match_live_sessions
  set lineup_revision = lineup_revision + 1, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_locked_at timestamptz;
  v_count integer;
  v_expected integer;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_season_id is null then
    raise exception 'Season is required' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Predictions must be an array' using errcode = '22023';
  end if;

  select season.season_predictions_locked_at
  into v_locked_at
  from public.seasons season
  where season.id = p_season_id
    and season.status = 'open'
  for update;

  if not found then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;
  if v_locked_at is not null then
    raise exception 'Season predictions are locked' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_count
  from jsonb_array_elements(p_items);

  if v_count < 1 or v_count > 100 then
    raise exception 'Invalid prediction item count' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(
      season_player_id uuid,
      category text,
      predicted_value_30 integer
    )
    where item.season_player_id is null
      or item.category not in ('buts', 'clean_sheets')
      or item.predicted_value_30 is null
      or item.predicted_value_30 < 0
      or item.predicted_value_30 > 99
  ) then
    raise exception 'Invalid season prediction value' using errcode = '22023';
  end if;

  if (
    select count(*)
    from (
      select item.season_player_id, item.category
      from jsonb_to_recordset(p_items) as item(
        season_player_id uuid,
        category text,
        predicted_value_30 integer
      )
      group by item.season_player_id, item.category
    ) unique_items
  ) <> v_count then
    raise exception 'Duplicate season prediction item' using errcode = '22023';
  end if;

  select count(*)::integer
  into v_expected
  from public.season_players player
  where player.season_id = p_season_id
    and player.is_active;

  if v_count <> v_expected then
    raise exception 'The complete active roster must be submitted'
      using errcode = '22023';
  end if;

  if (
    select count(*)
    from jsonb_to_recordset(p_items) as item(
      season_player_id uuid,
      category text,
      predicted_value_30 integer
    )
    join public.season_players player
      on player.id = item.season_player_id
     and player.season_id = p_season_id
     and player.is_active
    where (player.is_goalkeeper and item.category = 'clean_sheets')
       or (not player.is_goalkeeper and item.category = 'buts')
  ) <> v_count then
    raise exception 'Prediction items do not match the active roster'
      using errcode = '22023';
  end if;

  insert into public.season_predictions(
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    predicted_value_30,
    is_filled,
    updated_at
  )
  select
    p_season_id,
    v_actor,
    item.season_player_id,
    item.category,
    item.predicted_value_30,
    true,
    now()
  from jsonb_to_recordset(p_items) as item(
    season_player_id uuid,
    category text,
    predicted_value_30 integer
  )
  on conflict (
    season_id,
    predictor_profile_id,
    season_player_id,
    category
  )
  do update set
    predicted_value_30 = excluded.predicted_value_30,
    is_filled = true,
    updated_at = now();

  return jsonb_build_object(
    'season_id', p_season_id,
    'saved', v_count
  );
end;
$$;


ALTER FUNCTION "private"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."send_sport_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_row record;
  v_event_id bigint;
  v_created integer := 0;
  v_skipped_recent integer := 0;
  v_target_count integer := 0;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason is too long' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.match_id = p_match_id
      and workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > now()
  ) then
    raise exception 'Availability reminders are not open for this match'
      using errcode = '22023';
  end if;

  for v_row in
    select
      participant.id as participant_id,
      participant.season_player_id,
      player.profile_id
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = p_match_id
      and participant.is_eligible
      and participant.availability_status = 'no_response'
      and player.profile_id is not null
      and profile.status = 'active'
      and (
        p_season_player_id is null
        or participant.season_player_id = p_season_player_id
      )
    order by participant.id
  loop
    v_target_count := v_target_count + 1;

    if exists (
      select 1
      from public.sport_availability_notification_events event
      where event.participant_id = v_row.participant_id
        and event.kind = 'availability_manual'
        and event.requested_at > now() - interval '10 minutes'
    ) then
      v_skipped_recent := v_skipped_recent + 1;
      continue;
    end if;

    v_event_id := private.create_sport_availability_notification(
      p_match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_manual',
      'manual',
      now(),
      v_actor,
      v_reason
    );

    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  if p_season_player_id is not null and v_target_count = 0 then
    raise exception 'Player is not waiting for an availability response'
      using errcode = '22023';
  end if;

  insert into private.sport_admin_audit_log (
    match_id,
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    p_match_id,
    'send_availability_reminder',
    v_actor,
    v_reason,
    jsonb_build_object(
      'season_player_id', p_season_player_id,
      'target_count', v_target_count,
      'created_count', v_created,
      'skipped_recent_count', v_skipped_recent
    )
  );

  return jsonb_build_object(
    'target_count', v_target_count,
    'created_count', v_created,
    'skipped_recent_count', v_skipped_recent
  );
end;
$$;


ALTER FUNCTION "private"."send_sport_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_old_reusable boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_archived is null then
    raise exception 'Archived state is required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select guest.is_reusable into v_old_reusable
  from public.guest_players guest
  where guest.id = p_guest_player_id
  for update;

  if not found then
    raise exception 'Guest player not found' using errcode = 'P0002';
  end if;

  update public.guest_players guest
  set is_reusable = not p_archived,
      archived_at = case when p_archived then now() else null end,
      updated_by = v_actor,
      updated_at = now()
  where guest.id = p_guest_player_id;

  insert into private.sport_admin_audit_log (
    action,
    actor_profile_id,
    reason,
    metadata
  ) values (
    case when p_archived then 'archive_guest' else 'restore_guest' end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'guest_player_id', p_guest_player_id,
      'old_is_reusable', v_old_reusable,
      'new_is_reusable', not p_archived
    )
  );

  return private.get_guest_players(true);
end;
$$;


ALTER FUNCTION "private"."set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_convocation_status;
  v_old_consume boolean;
  v_new_status public.sport_convocation_status;
  v_reason text := nullif(btrim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status not in ('convoked', 'not_convoked') then
    raise exception 'Invalid convocation status' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;
  v_new_status := p_status::public.sport_convocation_status;

  select participant.id, participant.convocation_status,
    participant.waitlist_turn_should_consume
  into v_participant_id, v_old_status, v_old_consume
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available'
  for update;

  if not found then
    raise exception 'Available participant not found' using errcode = 'P0002';
  end if;

  update public.match_sport_participants
  set convocation_status = v_new_status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = p_turn_should_consume,
      waitlist_turn_state = case
        when p_turn_should_consume then
          case
            when waitlist_turn_state = 'consumed'
              then 'consumed'::public.sport_waitlist_turn_state
            else 'pending'::public.sport_waitlist_turn_state
          end
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  where id = v_participant_id;

  update public.match_sport_workflows
  set convocation_version = convocation_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where match_id = p_match_id;

  insert into public.match_sport_participant_events (
    participant_id, match_id, event_type, old_value, new_value,
    actor_profile_id, actor_kind
  ) values (
    v_participant_id, p_match_id, 'convocation_overridden',
    jsonb_build_object(
      'status', v_old_status,
      'turn_should_consume', v_old_consume
    ),
    jsonb_build_object(
      'status', v_new_status,
      'turn_should_consume', p_turn_should_consume
    ),
    v_actor, 'staff'
  );

  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'override_convocation', v_actor, v_reason,
    jsonb_build_object(
      'season_player_id', p_season_player_id,
      'old_status', v_old_status,
      'new_status', v_new_status,
      'old_turn_should_consume', v_old_consume,
      'new_turn_should_consume', p_turn_should_consume
    )
  );

  return private.get_match_convocations(p_match_id);
end;
$$;


ALTER FUNCTION "private"."set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_state public.match_live_state;
  v_elapsed integer;
  v_running_since timestamptz;
  v_half smallint;
  v_planned integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;
  if p_action not in ('pause', 'resume', 'halftime', 'resume_second_half') then
    raise exception 'Invalid clock action' using errcode = '22023';
  end if;

  select session.state, session.elapsed_seconds, session.running_since,
         session.half, session.planned_duration_minutes
  into v_state, v_elapsed, v_running_since, v_half, v_planned
  from public.match_live_sessions session
  where session.match_id = p_match_id
  for update;

  if not found then
    raise exception 'No live session for this match' using errcode = 'P0002';
  end if;

  if p_action = 'pause' then
    if v_state <> 'running' then
      raise exception 'The clock is not running' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'paused',
        elapsed_seconds = v_elapsed + greatest(0, extract(epoch from now() - v_running_since))::integer,
        running_since = null,
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'resume' then
    if v_state <> 'paused' then
      raise exception 'The clock is not paused' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'running',
        running_since = now(),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'halftime' then
    if v_state not in ('running', 'paused') or v_half <> 1 then
      raise exception 'Half-time is only available during the first half' using errcode = '22023';
    end if;
    -- La mi-temps cale le chrono sur la moitié du temps de jeu saisi par
    -- le coach, quel que soit le temps réellement écoulé, et met en pause.
    update public.match_live_sessions
    set state = 'halftime',
        elapsed_seconds = greatest(0, coalesce(v_planned, 0)) * 30,
        running_since = null,
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  elsif p_action = 'resume_second_half' then
    if v_state <> 'halftime' then
      raise exception 'The match is not at half-time' using errcode = '22023';
    end if;
    update public.match_live_sessions
    set state = 'running',
        half = 2,
        running_since = now(),
        updated_by = v_actor, updated_at = now()
    where match_id = p_match_id;
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$$;


ALTER FUNCTION "private"."set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid" DEFAULT NULL::"uuid", "p_is_opponent_own_goal" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "private"."set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_is_eligible boolean;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_composition_state public.sport_composition_state;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('available', 'absent') then
    raise exception 'Availability status must be available or absent' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status = 'available' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.is_eligible, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_is_eligible, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_composition_state, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and (participant.is_eligible or player.is_coach)
    and player.profile_id = v_actor
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'player'
    );

    -- Coaches are ineligible: their availability never affects convocations.
    if v_is_eligible then
      if v_convocation_state = 'published'
         and v_old_status = 'available'
         and v_new_status = 'absent' then
        v_promoted_player_id := private.handle_convoked_withdrawal(
          p_match_id, v_participant_id, v_actor, 'player'
        );
      elsif v_convocation_state = 'published'
         and v_old_status = 'absent'
         and v_new_status = 'available' then
        v_promoted_player_id := private.restore_returning_convoked_player(
          p_match_id, v_participant_id, v_actor, 'player'
        );
      else
        perform private.recompute_match_convocations_internal(p_match_id, false);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id,
    'composition_already_published',
      v_composition_state in ('published', 'updated', 'closed')
  );
end;
$$;


ALTER FUNCTION "private"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_notifications_paused"("p_enabled" boolean, "p_justification" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_old_enabled boolean;
  v_updated_at timestamptz;
  v_justification text := nullif(btrim(p_justification), '');
begin
  if p_enabled is null then
    raise exception 'Feature flag value is required' using errcode = '22023';
  end if;

  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if v_justification is not null and char_length(v_justification) > 500 then
    raise exception 'Justification cannot exceed 500 characters'
      using errcode = '22023';
  end if;

  select f.enabled
  into v_old_enabled
  from private.app_feature_flags f
  where f.key = 'notifications_paused'
  for update;

  if not found then
    raise exception 'Notifications kill switch flag is missing'
      using errcode = 'P0002';
  end if;

  if v_old_enabled is distinct from p_enabled then
    update private.app_feature_flags f
    set enabled = p_enabled,
        updated_at = now(),
        updated_by = (select auth.uid())
    where f.key = 'notifications_paused'
    returning f.updated_at into v_updated_at;

    insert into private.app_feature_flag_audit (
      feature_key, old_enabled, new_enabled, actor_profile_id, justification
    )
    values (
      'notifications_paused', v_old_enabled, p_enabled,
      (select auth.uid()), v_justification
    );
  else
    select f.updated_at into v_updated_at
    from private.app_feature_flags f
    where f.key = 'notifications_paused';
  end if;

  return jsonb_build_object(
    'notifications_paused',
    jsonb_build_object(
      'enabled', p_enabled,
      'updated_at', v_updated_at,
      'changed', v_old_enabled is distinct from p_enabled
    )
  );
end;
$$;


ALTER FUNCTION "private"."set_notifications_paused"("p_enabled" boolean, "p_justification" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_old_enabled boolean;
  v_config jsonb;
  v_updated_at timestamptz;
  v_justification text := nullif(btrim(p_justification), '');
begin
  if p_enabled is null then
    raise exception 'Feature flag value is required' using errcode = '22023';
  end if;

  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if v_justification is not null and char_length(v_justification) > 500 then
    raise exception 'Justification cannot exceed 500 characters'
      using errcode = '22023';
  end if;

  select f.enabled, f.config
  into v_old_enabled, v_config
  from private.app_feature_flags f
  where f.key = 'sports_management'
  for update;

  if not found then
    raise exception 'Sports-management feature flag is missing'
      using errcode = 'P0002';
  end if;

  if v_old_enabled is distinct from p_enabled then
    update private.app_feature_flags f
    set enabled = p_enabled,
        updated_at = now(),
        updated_by = (select auth.uid())
    where f.key = 'sports_management'
    returning f.updated_at into v_updated_at;

    insert into private.app_feature_flag_audit (
      feature_key,
      old_enabled,
      new_enabled,
      actor_profile_id,
      justification
    )
    values (
      'sports_management',
      v_old_enabled,
      p_enabled,
      (select auth.uid()),
      v_justification
    );
  else
    select f.updated_at
    into v_updated_at
    from private.app_feature_flags f
    where f.key = 'sports_management';
  end if;

  return jsonb_build_object(
    'sports_management',
    jsonb_build_object(
      'enabled', p_enabled,
      'config', v_config,
      'updated_at', v_updated_at,
      'changed', v_old_enabled is distinct from p_enabled
    )
  );
end;
$$;


ALTER FUNCTION "private"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."signal_feature_flag_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.feature_flag_change_signals(key, revision, updated_at)
  values (new.key, 1, new.updated_at)
  on conflict (key) do update
  set revision = public.feature_flag_change_signals.revision + 1,
      updated_at = excluded.updated_at;

  return new;
end;
$$;


ALTER FUNCTION "private"."signal_feature_flag_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."signal_shared_data_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile_increment bigint := 0;
  v_sports_increment bigint := 0;
begin
  if tg_table_schema = 'public' and tg_table_name = 'season_predictions' then
    return null;
  end if;

  if tg_table_schema = 'public' and tg_table_name = 'profiles' then
    v_profile_increment := 1;
  end if;

  if tg_table_schema = 'public' and tg_table_name = any (array[
    'guest_players',
    'match_compositions',
    'match_composition_entries',
    'match_composition_publications',
    'sport_waitlist_entries',
    'match_sport_participants',
    'match_sport_workflows'
  ]) then
    v_sports_increment := 1;
  end if;

  insert into public.shared_data_change_signals(
    key,
    revision,
    profile_revision,
    sports_revision,
    updated_at
  )
  values ('global', 1, 1, 1, now())
  on conflict (key) do update
  set revision = public.shared_data_change_signals.revision + 1,
      profile_revision =
        public.shared_data_change_signals.profile_revision
        + v_profile_increment,
      sports_revision =
        public.shared_data_change_signals.sports_revision
        + v_sports_increment,
      updated_at = excluded.updated_at;
  return null;
end;
$$;


ALTER FUNCTION "private"."signal_shared_data_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."sync_historical_match_players"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    perform private.refresh_historical_match_players(old.match_id);
    return old;
  end if;

  perform private.refresh_historical_match_players(new.match_id);
  return new;
end;
$$;


ALTER FUNCTION "private"."sync_historical_match_players"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."sync_match_sport_workflow"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_config jsonb;
  v_default_squad_size integer := 14;
  v_opens_at timestamptz;
  v_computed_state public.sport_availability_state;
  v_saved_state public.sport_availability_state;
  v_opened_at timestamptz;
  v_eligible_count integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.season_id, match.kickoff_at, match.status
  into v_season_id, v_kickoff_at, v_match_status
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_status <> 'a_venir' then
    raise exception 'Only upcoming matches can be synchronized' using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  select flag.config into v_config
  from private.app_feature_flags flag
  where flag.key = 'sports_management';

  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_default_squad_size := greatest(
      1,
      least(30, (v_config ->> 'usual_squad_size')::integer)
    );
  end if;

  v_opens_at := private.match_features_open_at(v_kickoff_at);
  v_computed_state := case
    when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
    when now() >= v_opens_at then 'open'::public.sport_availability_state
    else 'pending'::public.sport_availability_state
  end;

  insert into public.match_sport_workflows as workflow (
    match_id,
    availability_state,
    availability_opens_at,
    availability_opened_at,
    squad_size_limit,
    created_by,
    updated_by
  ) values (
    p_match_id,
    v_computed_state,
    v_opens_at,
    case when v_computed_state = 'open' then now() else null end,
    v_default_squad_size,
    v_actor,
    v_actor
  )
  on conflict (match_id) do update
  set availability_opens_at = excluded.availability_opens_at,
      availability_state = v_computed_state,
      availability_opened_at = case
        when v_computed_state = 'open'
          then coalesce(workflow.availability_opened_at, now())
        else null
      end,
      updated_by = v_actor,
      updated_at = now()
  returning availability_state, availability_opened_at
  into v_saved_state, v_opened_at;

  update public.match_sport_participants participant
  set is_eligible = false,
      updated_at = now()
  where participant.match_id = p_match_id
    and participant.season_player_id is not null
    and participant.is_eligible
    and not exists (
      select 1
      from public.season_players player
      where player.id = participant.season_player_id
        and player.season_id = v_season_id
        and player.is_active
        and not player.is_coach
    );

  insert into public.match_sport_participants as participant (
    match_id,
    season_player_id,
    is_eligible
  )
  select p_match_id, player.id, not player.is_coach
  from public.season_players player
  where player.season_id = v_season_id
    and player.is_active
  on conflict (match_id, season_player_id) do update
  set is_eligible = excluded.is_eligible,
      updated_at = case
        when participant.is_eligible = excluded.is_eligible
          then participant.updated_at
        else now()
      end;

  select count(*)::integer into v_eligible_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return jsonb_build_object(
    'match_id', p_match_id,
    'availability_state', v_saved_state,
    'availability_opens_at', v_opens_at,
    'availability_opened_at', v_opened_at,
    'kickoff_at', v_kickoff_at,
    'squad_size_limit', (
      select workflow.squad_size_limit
      from public.match_sport_workflows workflow
      where workflow.match_id = p_match_id
    ),
    'eligible_participant_count', v_eligible_count
  );
end;
$_$;


ALTER FUNCTION "private"."sync_match_sport_workflow"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."transition_match_motm_election"("p_match_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_election public.match_sport_motm_elections%rowtype;
begin
  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;
  if not found then
    return;
  end if;

  if v_election.state = 'draft'
     and v_election.closes_at is not null
     and now() >= v_election.closes_at then
    perform private.close_match_motm_election(p_match_id, false);
    return;
  end if;

  if v_election.state = 'draft'
     and v_election.opens_at is not null
     and now() >= v_election.opens_at
     and now() < v_election.closes_at then
    update public.match_sport_motm_elections
    set state = 'open', updated_at = now()
    where match_id = p_match_id;
    update public.match_sport_workflows
    set vote_state = 'open', updated_at = now()
    where match_id = p_match_id;
    return;
  end if;

  if v_election.state = 'open'
     and v_election.closes_at is not null
     and now() >= v_election.closes_at then
    perform private.close_match_motm_election(p_match_id, false);
  end if;
end;
$$;


ALTER FUNCTION "private"."transition_match_motm_election"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."trg_reset_match_motm_after_finalization"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_opens_at timestamptz;
  v_vote_state public.sport_vote_state;
begin
  perform private.ensure_match_motm_election(new.match_id);

  v_opens_at := private.match_motm_opens_at(new.match_id);
  if v_opens_at is null then
    return new;
  end if;

  update public.match_sport_motm_elections election
  set opens_at = v_opens_at,
      closes_at = v_opens_at + interval '24 hours',
      updated_at = now()
  where election.match_id = new.match_id
    and election.state in ('draft', 'open');

  perform private.transition_match_motm_election(new.match_id);

  select election.state
  into v_vote_state
  from public.match_sport_motm_elections election
  where election.match_id = new.match_id;

  if v_vote_state is not null then
    update public.match_sport_workflows workflow
    set vote_state = v_vote_state,
        updated_at = now()
    where workflow.match_id = new.match_id
      and workflow.vote_state is distinct from v_vote_state;
  end if;

  if v_vote_state = 'closed' then
    delete from public.match_man_of_match
    where match_id = new.match_id;

    insert into public.match_man_of_match(match_id, season_player_id)
    select result.match_id, participant.season_player_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    where result.match_id = new.match_id
      and result.is_winner
      and participant.season_player_id is not null
    on conflict do nothing;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."trg_reset_match_motm_after_finalization"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."try_motm_result_notification"("p_kind" "text", "p_match_id" "uuid", "p_sent_at" timestamp with time zone DEFAULT "now"()) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if p_kind not in ('motm_result_general', 'motm_result_winner') then
    raise exception 'Unknown MOTM result notification kind' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_match_id::text || ':' || p_kind, 0)
  );

  if exists (
    select 1
    from public.push_notification_log log
    where log.match_id = p_match_id
      and log.kind = p_kind
  ) then
    return false;
  end if;

  if not private.dispatch_motm_result_notification(p_kind, p_match_id) then
    return false;
  end if;

  insert into public.push_notification_log(match_id, kind, sent_at)
  values (p_match_id, p_kind, p_sent_at)
  on conflict do nothing;

  return found;
end;
$$;


ALTER FUNCTION "private"."try_motm_result_notification"("p_kind" "text", "p_match_id" "uuid", "p_sent_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."update_match_with_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  perform public.update_match_with_odds(
    p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_status, p_win, p_draw, p_loss
  );
  if p_status = 'a_venir' then
    perform private.configure_match_sport_workflow(p_match_id, p_squad_size_limit);
  else
    update public.match_sport_workflows
    set availability_state = 'closed',
        convocation_state = 'closed',
        updated_by = (select auth.uid()),
        updated_at = now()
    where match_id = p_match_id;
    perform private.finalize_match_waitlist_turns_internal(p_match_id, true);
  end if;
  return true;
end;
$$;


ALTER FUNCTION "private"."update_match_with_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_formation text := nullif(btrim(p_formation_code), '');
  v_match_status text;
  v_kickoff_at timestamptz;
  v_squad_limit integer;
  v_finalized boolean;
  v_current_version integer;
  v_next_version integer;
  v_expected_count integer;
  v_input_count integer;
  v_field_count integer;
  v_selected_count integer;
  v_present_count integer;
  v_invalid_count integer;
  v_exception_used boolean;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
    raise exception 'Composition entries must be a JSON array' using errcode = '22023';
  end if;
  if v_formation is not null and char_length(v_formation) > 32 then
    raise exception 'Formation code cannot exceed 32 characters' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select
    match.status::text,
    match.kickoff_at,
    workflow.squad_size_limit,
    finalization.match_id is not null
  into v_match_status, v_kickoff_at, v_squad_limit, v_finalized
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow;

  if not found then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('termine', 'archive') or now() < v_kickoff_at then
    raise exception 'Post-match composition requires a finished match'
      using errcode = '22023';
  end if;
  if not v_finalized then
    raise exception 'The match must be finalized before editing its composition'
      using errcode = '22023';
  end if;

  select composition.version into v_current_version
  from public.match_compositions composition
  where composition.match_id = p_match_id
  for update of composition;

  if not found then
    raise exception 'No post-match composition exists yet for this match'
      using errcode = '22023';
  end if;
  v_next_version := v_current_version + 1;

  create temporary table if not exists pg_temp.postmatch_composition_input (
    participant_id uuid primary key,
    zone public.sport_composition_zone not null,
    x numeric(7,6),
    y numeric(7,6),
    slot_label text,
    sort_order integer not null
  ) on commit drop;
  truncate table pg_temp.postmatch_composition_input;

  begin
    insert into pg_temp.postmatch_composition_input(
      participant_id, zone, x, y, slot_label, sort_order
    )
    select
      (item ->> 'participant_id')::uuid,
      (item ->> 'zone')::public.sport_composition_zone,
      case when item ->> 'x' is null then null else (item ->> 'x')::numeric end,
      case when item ->> 'y' is null then null else (item ->> 'y')::numeric end,
      nullif(btrim(item ->> 'slot_label'), ''),
      greatest(0, coalesce((item ->> 'sort_order')::integer, 0))
    from jsonb_array_elements(p_entries) item;
  exception
    when unique_violation then
      raise exception 'A participant can appear only once in a composition'
        using errcode = '22023';
    when invalid_text_representation or check_violation or numeric_value_out_of_range then
      raise exception 'Invalid composition entry' using errcode = '22023';
  end;

  select count(*) into v_input_count
  from pg_temp.postmatch_composition_input;
  select count(*) into v_expected_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and (
      participant.is_eligible
      or participant.final_presence_status <> 'pending'
    );
  if v_input_count <> v_expected_count then
    raise exception 'Every finalized participant must appear exactly once'
      using errcode = '22023';
  end if;

  select count(*) into v_invalid_count
  from pg_temp.postmatch_composition_input input
  left join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and (
     participant.is_eligible
     or participant.final_presence_status <> 'pending'
   )
  where participant.id is null
     or input.zone = 'available'
     or (
       input.zone = 'field'
       and (
         input.x is null or input.y is null
         or input.x < 0 or input.x > 1
         or input.y < 0 or input.y > 1
       )
     )
     or (input.zone <> 'field' and (input.x is not null or input.y is not null))
     or (
       participant.final_presence_status = 'present'
       and input.zone not in ('field', 'bench')
     )
     or (
       participant.final_presence_status <> 'present'
       and input.zone <> 'not_selected'
     );
  if v_invalid_count > 0 then
    raise exception 'Composition must contain only actual present players'
      using errcode = '22023';
  end if;

  select
    count(*) filter (where input.zone = 'field'),
    count(*) filter (where input.zone in ('field', 'bench'))
  into v_field_count, v_selected_count
  from pg_temp.postmatch_composition_input input;
  select count(*) into v_present_count
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present';

  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_selected_count <> v_present_count then
    raise exception 'Every actual present player must be on the field or bench'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;
  v_exception_used := v_selected_count > v_squad_limit;

  perform set_config(
    'as_grinta.allow_postmatch_composition_write',
    'on',
    true
  );

  update public.match_compositions
  set formation_code = v_formation,
      status = 'published',
      version = v_next_version,
      has_unpublished_changes = false,
      squad_size_exception_approved = v_exception_used,
      published_at = now(),
      published_by = v_actor,
      last_modified_at = now(),
      last_modified_by = v_actor
  where match_id = p_match_id;

  delete from public.match_composition_entries
  where match_id = p_match_id;

  insert into public.match_composition_entries(
    match_id, participant_id, zone, x, y, slot_label, sort_order
  )
  select p_match_id, participant_id, zone, x, y, slot_label, sort_order
  from pg_temp.postmatch_composition_input;

  update public.match_sport_participants participant
  set selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      final_selection_status = case input.zone
        when 'field' then 'starter'::public.sport_selection_status
        when 'bench' then 'substitute'::public.sport_selection_status
        else 'not_selected'::public.sport_selection_status
      end,
      selection_updated_at = now(),
      selection_updated_by = v_actor,
      updated_at = now()
  from pg_temp.postmatch_composition_input input
  where participant.id = input.participant_id
    and participant.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = 'published',
      composition_version = v_next_version,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  update public.match_sport_finalizations finalization
  set composition_version = v_next_version,
      updated_at = now()
  where finalization.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', 'postmatch'
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot,
    publication_kind, published_by
  ) values (
    p_match_id, v_next_version, v_formation, v_snapshot, 'postmatch', v_actor
  );

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    'update_postmatch_composition',
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_next_version,
      'publication_kind', 'postmatch',
      'field_count', v_field_count,
      'bench_count', v_selected_count - v_field_count,
      'present_count', v_present_count,
      'match_status', v_match_status,
      'exception_used', v_exception_used
    )
  );

  return private.get_published_match_composition(p_match_id);
end;
$$;


ALTER FUNCTION "private"."update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid" DEFAULT NULL::"uuid", "p_first_name" "text" DEFAULT NULL::"text", "p_last_name" "text" DEFAULT NULL::"text", "p_is_goalkeeper" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  -- Quand on crée/recherche un invité par identité, sérialiser les requêtes
  -- concurrentes portant sur la même personne. La seconde requête attend la
  -- première puis réutilise l'entrée créée au lieu d'échouer sur l'unicité.
  if p_guest_player_id is null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        lower(btrim(coalesce(p_first_name, ''))) || '|' ||
        lower(btrim(coalesce(p_last_name, ''))) || '|' ||
        coalesce(p_is_goalkeeper, false)::text,
        0
      )
    );
  end if;

  return private.add_or_reuse_match_guest(
    p_match_id,
    p_guest_player_id,
    p_first_name,
    p_last_name,
    p_is_goalkeeper,
    p_reason
  );
end;
$$;


ALTER FUNCTION "public"."admin_add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") IS 'Creates or reuses a reusable guest and attaches that identity to an upcoming match.';



CREATE OR REPLACE FUNCTION "public"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.admin_cancel_match_motm_vote(p_match_id, p_reason);
$$;


ALTER FUNCTION "public"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.admin_close_match_motm_vote_early(p_match_id, p_reason); $$;


ALTER FUNCTION "public"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.configure_match_sport_workflow(
    p_match_id, p_squad_size_limit
  );
$$;


ALTER FUNCTION "public"."admin_configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_match_complete"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer DEFAULT NULL::integer, "p_address" "text" DEFAULT NULL::"text", "p_remember_address_as_default" boolean DEFAULT false, "p_match_type" "text" DEFAULT 'championnat'::"text", "p_jersey_note" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match_id uuid;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_squad_size_limit is not null then
    v_match_id := private.create_match_with_sport_limit(
      p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_win, p_draw, p_loss, p_squad_size_limit
    );
  else
    v_match_id := public.create_match_with_odds(
      p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_win, p_draw, p_loss
    );
  end if;

  perform public.admin_set_match_address(
    v_match_id, p_address, p_remember_address_as_default
  );
  perform public.admin_set_match_type(v_match_id, p_match_type);
  perform public.admin_set_match_jersey(v_match_id, p_jersey_note);

  return v_match_id;
end;
$$;


ALTER FUNCTION "public"."admin_create_match_complete"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_create_match_complete"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") IS 'Crée un match, ses cotes, son adresse, son type et son maillot en une seule transaction.';



CREATE OR REPLACE FUNCTION "public"."admin_create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.create_postmatch_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
$$;


ALTER FUNCTION "public"."admin_create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
  v_vote_state public.sport_vote_state;
begin
  v_result := private.finalize_match_sport_postgame(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse,
    p_participants,
    p_reason
  );

  select workflow.vote_state
  into v_vote_state
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  return v_result || jsonb_build_object('vote_state', v_vote_state);
end;
$$;


ALTER FUNCTION "public"."admin_finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") IS 'Atomically validates actual attendance, roles and goals, mirrors permanent-player statistics, and versions corrections.';



CREATE OR REPLACE FUNCTION "public"."admin_finalize_match_waitlist_turns"("p_match_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.finalize_match_waitlist_turns_internal(p_match_id, false);
end;
$$;


ALTER FUNCTION "public"."admin_finalize_match_waitlist_turns"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_finalize_match_waitlist_turns"("p_match_id" "uuid") IS 'Consumes pending turns only strictly after the previous-day noon Europe/Paris cutoff.';



CREATE OR REPLACE FUNCTION "public"."admin_get_finished_bench_counts"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_finished_bench_counts(p_match_id); $$;


ALTER FUNCTION "public"."admin_get_finished_bench_counts"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_guest_players"("p_include_archived" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.get_guest_players(p_include_archived);
$$;


ALTER FUNCTION "public"."admin_get_guest_players"("p_include_archived" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_internal_composition"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match_type text;
  v_team1_name text;
  v_team2_name text;
  v_entries jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select match_type into v_match_type
  from public.matches
  where id = p_match_id;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  select comp.team1_name, comp.team2_name
  into v_team1_name, v_team2_name
  from public.match_internal_compositions comp
  where comp.match_id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'season_player_id', participant.season_player_id,
      'guest_player_id', participant.guest_player_id,
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ),
      'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
      'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
      'is_guest', participant.guest_player_id is not null,
      'team_no', entry.team_no,
      'sort_order', coalesce(entry.sort_order, 999)
    )
    order by coalesce(entry.sort_order, 999),
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      )
  ), '[]'::jsonb)
  into v_entries
  from public.match_sport_participants participant
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join public.match_internal_composition_entries entry
    on entry.match_id = p_match_id and entry.participant_id = participant.id
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  return jsonb_build_object(
    'match_id', p_match_id,
    'team1_name', coalesce(v_team1_name, 'Équipe 1'),
    'team2_name', coalesce(v_team2_name, 'Équipe 2'),
    'entries', v_entries
  );
end;
$$;


ALTER FUNCTION "public"."admin_get_internal_composition"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_match_availability_reminders"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.get_sport_availability_reminder_summary(p_match_id);
$$;


ALTER FUNCTION "public"."admin_get_match_availability_reminders"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_match_composition"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_admin_match_composition(p_match_id); $$;


ALTER FUNCTION "public"."admin_get_match_composition"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_match_convocations"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.enrich_match_convocation_history(
    private.get_match_convocations(p_match_id)
  );
$$;


ALTER FUNCTION "public"."admin_get_match_convocations"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_get_match_convocations"("p_match_id" "uuid") IS 'Returns the live recommendation and every administrator override for one match.';



CREATE OR REPLACE FUNCTION "public"."admin_get_match_guests"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.get_match_guests(p_match_id);
$$;


ALTER FUNCTION "public"."admin_get_match_guests"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_match_motm_dashboard"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.get_admin_match_motm_dashboard(p_match_id); $$;


ALTER FUNCTION "public"."admin_get_match_motm_dashboard"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_match_sport_finalization"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_admin_match_sport_finalization(p_match_id); $$;


ALTER FUNCTION "public"."admin_get_match_sport_finalization"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_match_sport_statistics_integrity"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_match_sport_statistics_integrity(p_match_id); $$;


ALTER FUNCTION "public"."admin_get_match_sport_statistics_integrity"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_notifications_paused"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return private.get_notifications_paused();
end;
$$;


ALTER FUNCTION "public"."admin_get_notifications_paused"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_get_notifications_paused"() IS 'Admin-only read of the global notifications kill switch state.';



CREATE OR REPLACE FUNCTION "public"."admin_get_player_position_history"("p_since" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.get_player_position_history(p_since);
$$;


ALTER FUNCTION "public"."admin_get_player_position_history"("p_since" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_get_sport_waitlist"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.enrich_sport_waitlist_history(
    private.get_sport_waitlist(p_season_id)
  );
$$;


ALTER FUNCTION "public"."admin_get_sport_waitlist"("p_season_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_get_sport_waitlist"("p_season_id" "uuid") IS 'Returns the administrator-managed waitlist initialized from previous-season attendance.';



CREATE OR REPLACE FUNCTION "public"."admin_list_match_motm_votes"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.list_admin_match_motm_votes(); $$;


ALTER FUNCTION "public"."admin_list_match_motm_votes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text" DEFAULT NULL::"text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.override_match_availability(
    p_match_id, p_season_player_id, p_status, p_private_comment, p_reason
  );
$$;


ALTER FUNCTION "public"."admin_override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") IS 'Admin-only availability override with a mandatory audit reason.';



CREATE OR REPLACE FUNCTION "public"."admin_publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.publish_match_composition(
    p_match_id,
    p_allow_squad_size_exception,
    p_reason
  );
end;
$$;


ALTER FUNCTION "public"."admin_publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") IS 'Publishes an immutable composition snapshot and increments the public version atomically.';



CREATE OR REPLACE FUNCTION "public"."admin_publish_match_convocations"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.publish_match_convocations(p_match_id, p_reason);
$$;


ALTER FUNCTION "public"."admin_publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") IS 'Publishes the current convocation list without rotating pending waitlist turns before the cutoff.';



CREATE OR REPLACE FUNCTION "public"."admin_publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.publish_match_effectif(
    p_match_id,
    p_squad_size_limit,
    p_decisions,
    p_reason
  );
end;
$$;


ALTER FUNCTION "public"."admin_publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") IS 'Atomically stores and explicitly publishes the current effectif decisions.';



CREATE OR REPLACE FUNCTION "public"."admin_recompute_match_convocations"("p_match_id" "uuid", "p_reset_overrides" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.recompute_match_convocations_internal(
    p_match_id, p_reset_overrides
  );
$$;


ALTER FUNCTION "public"."admin_recompute_match_convocations"("p_match_id" "uuid", "p_reset_overrides" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'L’effectif est figé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  return private.remove_match_guest(p_match_id, p_participant_id, p_reason);
end;
$$;


ALTER FUNCTION "public"."admin_remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") IS 'Removes a guest from the current match without deleting the reusable catalog identity or past publications.';



CREATE OR REPLACE FUNCTION "public"."admin_reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.enrich_sport_waitlist_history(
    private.reorder_sport_waitlist(
      p_season_id,
      p_ordered_player_ids,
      p_reason
    )
  );
$$;


ALTER FUNCTION "public"."admin_reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") IS 'Atomically replaces the complete waitlist order and writes an administrator audit record.';



CREATE OR REPLACE FUNCTION "public"."admin_require_password_change"("p_profile_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare actor_id uuid := (select auth.uid());
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
  set must_change_password = true, password_set = true, updated_at = now()
  where id = p_profile_id and status = 'active';
  if not found then
    raise exception 'Active profile not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;


ALTER FUNCTION "public"."admin_require_password_change"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.admin_restart_match_motm_vote(p_match_id, p_reason);
$$;


ALTER FUNCTION "public"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_save_internal_composition"("p_match_id" "uuid", "p_team1_name" "text", "p_team2_name" "text", "p_entries" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match_type text;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;

  select match_type into v_match_type from public.matches where id = p_match_id;
  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  insert into public.match_internal_compositions (match_id, team1_name, team2_name, updated_by)
  values (p_match_id, v_team1_name, v_team2_name, (select auth.uid()))
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in select value from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    insert into public.match_internal_composition_entries (
      match_id, participant_id, team_no, sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(v_entry ->> 'team_no', '')::smallint,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  return public.admin_get_internal_composition(p_match_id);
end;
$$;


ALTER FUNCTION "public"."admin_save_internal_composition"("p_match_id" "uuid", "p_team1_name" "text", "p_team2_name" "text", "p_entries" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  select match.status, match.kickoff_at
  into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status = 'a_venir'
     and v_kickoff_at is not null
     and now() >= v_kickoff_at - interval '15 minutes' then
    raise exception 'La composition est figée depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  perform private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
  return private.publish_match_composition(
    p_match_id,
    p_allow_squad_size_exception,
    p_reason
  );
end;
$$;


ALTER FUNCTION "public"."admin_save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") IS 'Saves a complete normalized draft, with at most eleven starters and an explicit squad-size exception.';



CREATE OR REPLACE FUNCTION "public"."admin_save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.publish_match_effectif(
    p_match_id, p_squad_size_limit, p_decisions, p_reason
  );
$$;


ALTER FUNCTION "public"."admin_save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") IS 'Stores a private effectif draft without changing player-visible published convocations.';



CREATE OR REPLACE FUNCTION "public"."admin_send_custom_push"("p_title" "text", "p_body" "text", "p_profile_ids" "uuid"[]) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
  v_title text := nullif(btrim(p_title), '');
  v_body text := nullif(btrim(p_body), '');
  v_recipients uuid[];
  v_count integer;
begin
  if not public.is_admin() then
    raise exception 'Admin required' using errcode = '42501';
  end if;
  if v_title is null or v_body is null then
    raise exception 'Un titre et un message sont requis' using errcode = '22023';
  end if;
  if char_length(v_title) > 80 then
    raise exception 'Le titre ne peut pas dépasser 80 caractères'
      using errcode = '22023';
  end if;
  if char_length(v_body) > 300 then
    raise exception 'Le message ne peut pas dépasser 300 caractères'
      using errcode = '22023';
  end if;
  if p_profile_ids is null or array_length(p_profile_ids, 1) is null then
    raise exception 'Choisis au moins un destinataire' using errcode = '22023';
  end if;

  select coalesce(array_agg(profile.id), '{}'::uuid[])
  into v_recipients
  from public.profiles profile
  where profile.id = any(p_profile_ids)
    and profile.status = 'active';

  v_count := coalesce(array_length(v_recipients, 1), 0);
  if v_count = 0 then
    raise exception 'Aucun destinataire valide' using errcode = '22023';
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    raise exception 'Notifications push non configurées';
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'title', v_title,
      'message', v_body,
      'profile_ids', to_jsonb(v_recipients)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return v_count;
end;
$$;


ALTER FUNCTION "public"."admin_send_custom_push"("p_title" "text", "p_body" "text", "p_profile_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_send_match_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid" DEFAULT NULL::"uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.send_sport_availability_reminder(
    p_match_id,
    p_season_player_id,
    p_reason
  );
$$;


ALTER FUNCTION "public"."admin_send_match_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.set_guest_archived(p_guest_player_id, p_archived, p_reason);
$$;


ALTER FUNCTION "public"."admin_set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") IS 'Archives or restores a reusable guest without changing existing historical match references.';



CREATE OR REPLACE FUNCTION "public"."admin_set_guest_photo"("p_guest_player_id" "uuid", "p_photo_url" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  update public.guest_players
  set photo_url = nullif(btrim(p_photo_url), ''),
      updated_by = (select auth.uid()),
      updated_at = now()
  where id = p_guest_player_id;

  if not found then
    raise exception 'Guest not found' using errcode = 'P0002';
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_set_guest_photo"("p_guest_player_id" "uuid", "p_photo_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_match_address"("p_match_id" "uuid", "p_address" "text", "p_remember_as_default" boolean DEFAULT false) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_address text := nullif(btrim(p_address), '');
  v_opponent uuid;
  v_location text;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'Address cannot exceed 300 characters' using errcode = '22023';
  end if;

  update public.matches
  set address = v_address
  where id = p_match_id
  returning opponent_id, location into v_opponent, v_location;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if coalesce(p_remember_as_default, false) and v_address is not null then
    if v_location = 'domicile' then
      update public.club_settings
      set home_address = v_address
      where id;
    elsif v_opponent is not null then
      update public.opponents
      set address = v_address
      where id = v_opponent;
    end if;
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_set_match_address"("p_match_id" "uuid", "p_address" "text", "p_remember_as_default" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_set_match_address"("p_match_id" "uuid", "p_address" "text", "p_remember_as_default" boolean) IS 'Met à jour l’adresse d’un match et peut la mémoriser comme valeur par défaut. Contrôle administrateur interne.';



CREATE OR REPLACE FUNCTION "public"."admin_set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.set_match_convocation(
    p_match_id, p_season_player_id, p_status,
    p_turn_should_consume, p_reason
  );
$$;


ALTER FUNCTION "public"."admin_set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_match_jersey"("p_match_id" "uuid", "p_jersey_note" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_jersey_note text := nullif(btrim(p_jersey_note), '');
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_jersey_note is not null and char_length(v_jersey_note) > 300 then
    raise exception 'Jersey note cannot exceed 300 characters' using errcode = '22023';
  end if;

  update public.matches
  set jersey_note = v_jersey_note
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_set_match_jersey"("p_match_id" "uuid", "p_jersey_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_match_type"("p_match_id" "uuid", "p_match_type" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_type is null or p_match_type not in ('amical', 'championnat') then
    raise exception 'Invalid match type' using errcode = '22023';
  end if;

  update public.matches
  set match_type = p_match_type
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_set_match_type"("p_match_id" "uuid", "p_match_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_notifications_paused"("p_enabled" boolean, "p_justification" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.set_notifications_paused(p_enabled, p_justification);
$$;


ALTER FUNCTION "public"."admin_set_notifications_paused"("p_enabled" boolean, "p_justification" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_set_notifications_paused"("p_enabled" boolean, "p_justification" "text") IS 'Admin-only toggle to pause every outgoing push notification (including the test channel), with audit.';



CREATE OR REPLACE FUNCTION "public"."admin_set_waitlist_manual_count"("p_season_player_id" "uuid", "p_count" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_count is null or p_count < 0 then
    raise exception 'Invalid count' using errcode = '22023';
  end if;

  update public.sport_waitlist_entries
  set manual_waitlist_count = p_count,
      updated_at = now(),
      updated_by = (select auth.uid())
  where season_player_id = p_season_player_id;

  if not found then
    raise exception 'Waitlist entry not found' using errcode = 'P0002';
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_set_waitlist_manual_count"("p_season_player_id" "uuid", "p_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_sync_match_sport_workflow"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.sync_match_sport_workflow(p_match_id); $$;


ALTER FUNCTION "public"."admin_sync_match_sport_workflow"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_sync_match_sport_workflow"("p_match_id" "uuid") IS 'Admin-only idempotent synchronization of an upcoming match and eligible permanent participants.';



CREATE OR REPLACE FUNCTION "public"."admin_update_match_complete"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer DEFAULT NULL::integer, "p_address" "text" DEFAULT NULL::"text", "p_remember_address_as_default" boolean DEFAULT false, "p_match_type" "text" DEFAULT 'championnat'::"text", "p_jersey_note" "text" DEFAULT NULL::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
  v_kickoff_at timestamptz;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.status, match.kickoff_at into v_status, v_kickoff_at
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'Un match passé ou annulé ne se modifie plus depuis la fiche match.' using errcode = '22023';
  end if;
  if v_kickoff_at is not null and now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'Le match est verrouillé depuis l’ouverture du Live.' using errcode = '22023';
  end if;

  if p_squad_size_limit is not null then
    perform private.update_match_with_sport_limit(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss, p_squad_size_limit
    );
  else
    perform public.update_match_with_odds(
      p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
      p_location, p_status, p_win, p_draw, p_loss
    );
  end if;

  perform public.admin_set_match_address(p_match_id, p_address, p_remember_address_as_default);
  perform public.admin_set_match_type(p_match_id, p_match_type);
  perform public.admin_set_match_jersey(p_match_id, p_jersey_note);

  return true;
end;
$$;


ALTER FUNCTION "public"."admin_update_match_complete"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_update_match_complete"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") IS 'Met à jour un match, ses cotes, son adresse, son type et son maillot en une seule transaction.';



CREATE OR REPLACE FUNCTION "public"."admin_update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.update_postmatch_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    p_allow_squad_size_exception,
    p_reason
  );
$$;


ALTER FUNCTION "public"."admin_update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_profile_fields"("p_profile_id" "uuid", "p_role" "text", "p_status" "text", "p_is_goalkeeper" boolean) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
  current_row public.profiles%rowtype;
  resulting_role text;
  resulting_status text;
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
  if p_role is not null and p_role not in ('pronostiqueur', 'admin') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  if p_status is not null and p_status not in ('pending', 'active', 'archived') then
    raise exception 'Invalid status' using errcode = '22023';
  end if;
  if p_profile_id = actor_id and (p_role is not null or p_status is not null) then
    raise exception 'An administrator cannot change their own role or status here' using errcode = '42501';
  end if;

  resulting_role := coalesce(p_role, current_row.role::text);
  resulting_status := coalesce(p_status, current_row.status::text);

  update public.profiles
  set role = resulting_role,
      status = resulting_status,
      is_goalkeeper = coalesce(p_is_goalkeeper, is_goalkeeper),
      updated_at = now()
  where id = p_profile_id;

  return true;
end;
$$;


ALTER FUNCTION "public"."admin_update_profile_fields"("p_profile_id" "uuid", "p_role" "text", "p_status" "text", "p_is_goalkeeper" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."archive_match"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select m.status
  into v_status
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found or v_status = 'archive' then
    raise exception 'Non-archived match not found' using errcode = 'P0002';
  end if;

  if v_status <> 'termine' then
    raise exception 'Only a finished match can be archived'
      using errcode = '22023';
  end if;

  update public.matches
  set status = 'archive',
      updated_at = now()
  where id = p_match_id;

  return true;
end;
$$;


ALTER FUNCTION "public"."archive_match"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."award_season_titles"("p_season_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.season_awards(season_id, profile_id, award_type)
  with tot as (
    select count(*)::int as c from public.matches
    where season_id = p_season_id and status in ('termine', 'archive')
  ),
  sp_prof as (
    select id, profile_id from public.season_players
    where season_id = p_season_id and profile_id is not null
  ),
  present as (
    select distinct spp.profile_id, u.match_id
    from sp_prof spp
    join lateral (
      select ma.match_id from public.match_attendance ma where ma.season_player_id = spp.id
      union select s.match_id from public.match_player_stats s where s.season_player_id = spp.id
      union select v.match_id from public.match_man_of_match v where v.season_player_id = spp.id
    ) u on true
    join public.matches m on m.id = u.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
  ),
  played as (
    select pr.profile_id, count(*)::int as n,
           count(*) filter (where m.score_as_grinta > m.score_adverse)::int as w
    from present pr join public.matches m on m.id = pr.match_id
    group by pr.profile_id
  ),
  goals as (
    select spp.profile_id, sum(s.goals)::int as g
    from sp_prof spp
    join public.match_player_stats s on s.season_player_id = spp.id
    join public.matches m on m.id = s.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  mvp as (
    select spp.profile_id, count(*)::int as c
    from sp_prof spp
    join public.match_man_of_match v on v.season_player_id = spp.id
    join public.matches m on m.id = v.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by spp.profile_id
  ),
  pmatch_pts as (
    select vp.profile_id, sum(vp.points) as pts
    from public.v_match_prediction_points vp
    join public.matches m on m.id = vp.match_id and m.season_id = p_season_id
    group by vp.profile_id
  ),
  pmatch_cnt as (
    select mp.profile_id, count(*) filter (where mp.is_filled) as cnt
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id
      and m.season_id = p_season_id and m.status in ('termine', 'archive')
    group by mp.profile_id
  ),
  pplayer_pts as (
    select predictor_profile_id as profile_id, sum(points)::numeric as pts
    from public.v_season_prediction_points where season_id = p_season_id
    group by predictor_profile_id
  ),
  poverall as (
    select coalesce(pm.profile_id, pp.profile_id) as profile_id,
           coalesce(pm.pts, 0) + coalesce(pp.pts, 0) as total
    from pmatch_pts pm
    full outer join pplayer_pts pp on pp.profile_id = pm.profile_id
  ),
  w_complete as (
    select p.profile_id, 'season_complete'::text as at
    from played p, tot where tot.c > 0 and p.n = tot.c
  ),
  w_present as (
    select profile_id, 'most_present' from (
      select profile_id, rank() over (order by n desc) rk from played where n > 0
    ) z where rk = 1
  ),
  w_scorer as (
    select profile_id, 'top_scorer' from (
      select profile_id, rank() over (order by g desc) rk from goals where g > 0
    ) z where rk = 1
  ),
  w_mvp as (
    select profile_id, 'mvp_king' from (
      select profile_id, rank() over (order by c desc) rk from mvp where c > 0
    ) z where rk = 1
  ),
  w_winrate as (
    select profile_id, 'best_winrate' from (
      select profile_id, rank() over (order by (w::numeric / n) desc) rk
      from played where n >= 5
    ) z where rk = 1
  ),
  w_pred_match as (
    select profile_id, 'best_pred_match' from (
      select pm.profile_id, rank() over (order by pm.pts desc) rk
      from pmatch_pts pm join pmatch_cnt pc on pc.profile_id = pm.profile_id
      where pc.cnt >= 5 and pm.pts > 0
    ) z where rk = 1
  ),
  w_pred_player as (
    select profile_id, 'best_pred_player' from (
      select profile_id, rank() over (order by pts desc) rk from pplayer_pts where pts > 0
    ) z where rk = 1
  ),
  w_pred_overall as (
    select profile_id, 'best_pred_overall' from (
      select profile_id, rank() over (order by total desc) rk from poverall where total > 0
    ) z where rk = 1
  )
  select p_season_id, profile_id, at from (
    select * from w_complete
    union all select * from w_present
    union all select * from w_scorer
    union all select * from w_mvp
    union all select * from w_winrate
    union all select * from w_pred_match
    union all select * from w_pred_player
    union all select * from w_pred_overall
  ) allw
  where profile_id is not null
  on conflict (season_id, profile_id, award_type) do nothing;

  perform public.recalculate_all_badges();
end;
$$;


ALTER FUNCTION "public"."award_season_titles"("p_season_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_match_odds_v4"("p_opponent_id" "uuid", "p_location" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select public.calculate_match_odds_v5(p_opponent_id, current_date);
$$;


ALTER FUNCTION "public"."calculate_match_odds_v4"("p_opponent_id" "uuid", "p_location" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_match_odds_v5"("p_opponent_id" "uuid", "p_reference_date" "date") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_ref date := coalesce(p_reference_date, current_date);
  v_h_v numeric := 0;
  v_h_d numeric := 0;
  v_form_v numeric := 0;
  v_form_d numeric := 0;
  v_q_forme numeric;
  v_q numeric;
  v_cote_v_prov numeric;
  v_cote_d_prov numeric;
  v_cote_n_prov numeric;
  v_u_v numeric;
  v_u_n numeric;
  v_u_d numeric;
  v_s numeric;
  v_p_v numeric;
  v_p_n numeric;
  v_p_d numeric;
begin
  if not exists (select 1 from public.opponents where id = p_opponent_id) then
    raise exception 'Adversaire introuvable';
  end if;

  with all_results as (
    select m.id, m.opponent_id, m.match_date,
      m.score_as_grinta, m.score_adverse
    from public.matches m
    where m.status = 'termine'
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    union all
    select h.id, h.opponent_id, h.match_date,
      h.score_as_grinta::integer, h.score_adverse::integer
    from public.historical_match_scores h
  ), h2h as (
    select
      case
        when r.score_as_grinta > r.score_adverse then 'V'
        when r.score_as_grinta = r.score_adverse then 'N'
        else 'D'
      end as result,
      row_number() over (
        order by r.match_date desc, r.id desc
      ) as rang,
      greatest(0, (v_ref - r.match_date))::numeric as age
    from all_results r
    where r.opponent_id = p_opponent_id
      and r.match_date < v_ref
  ), weighted as (
    select result,
      case
        when rang <= 5 then
          (array[1.0, 0.95, 0.90, 0.85, 0.80])[rang::int]
            * power(0.5::numeric, age / 900.0)
        else
          0.35 * power(0.75::numeric, (rang - 6)::numeric)
            * power(0.5::numeric, age / 900.0)
      end as poids
    from h2h
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_h_v, v_h_d
  from weighted;

  with all_results as (
    select m.id, m.match_date, m.score_as_grinta, m.score_adverse
    from public.matches m
    where m.status = 'termine'
      and m.score_as_grinta is not null
      and m.score_adverse is not null
    union all
    select h.id, h.match_date,
      h.score_as_grinta::integer, h.score_adverse::integer
    from public.historical_match_scores h
  ), form as (
    select
      case
        when r.score_as_grinta > r.score_adverse then 'V'
        when r.score_as_grinta = r.score_adverse then 'N'
        else 'D'
      end as result,
      power(
        0.5::numeric,
        greatest(0, (v_ref - r.match_date))::numeric / 180.0
      ) as poids
    from all_results r
    where r.match_date < v_ref
  )
  select
    coalesce(sum(poids) filter (where result = 'V'), 0),
    coalesce(sum(poids) filter (where result = 'D'), 0)
  into v_form_v, v_form_d
  from form;

  if (v_form_v + v_form_d) = 0 then
    v_q_forme := 0.50;
  else
    v_q_forme := v_form_v / (v_form_v + v_form_d);
  end if;

  v_q := (1.0 * v_q_forme + v_h_v) / (1.0 + v_h_v + v_h_d);
  v_q := least(0.999999, greatest(0.000001, v_q));

  v_cote_v_prov := 1.0 / v_q;
  v_cote_d_prov := 1.0 / (1.0 - v_q);
  v_cote_n_prov := ((v_cote_v_prov + v_cote_d_prov) / 2.0) * 1.50;

  v_u_v := 1.0 / v_cote_v_prov;
  v_u_n := 1.0 / v_cote_n_prov;
  v_u_d := 1.0 / v_cote_d_prov;
  v_s := v_u_v + v_u_n + v_u_d;
  v_p_v := v_u_v / v_s;
  v_p_n := v_u_n / v_s;
  v_p_d := v_u_d / v_s;

  return jsonb_build_object(
    'win', round(1.0 / v_p_v, 2),
    'draw', round(1.0 / v_p_n, 2),
    'loss', round(1.0 / v_p_d, 2),
    'probability_win', round(v_p_v, 6),
    'probability_draw', round(v_p_n, 6),
    'probability_loss', round(v_p_d, 6),
    'q_decisive', round(v_q, 6),
    'q_form', round(v_q_forme, 6),
    'h2h_win_weight', round(v_h_v, 6),
    'h2h_loss_weight', round(v_h_d, 6),
    'model_version', 'compact_history_v6'
  );
end;
$$;


ALTER FUNCTION "public"."calculate_match_odds_v5"("p_opponent_id" "uuid", "p_reference_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_match"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  update public.matches
  set status = 'annule'
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;


ALTER FUNCTION "public"."cancel_match"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.cast_match_motm_vote(p_match_id, p_candidate_participant_id);
$$;


ALTER FUNCTION "public"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_replaced_photo"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_prefix text;
  v_keep text;
begin
  if new.photo_url is not distinct from old.photo_url then
    return new;
  end if;

  v_prefix := case tg_table_name
    when 'profiles' then new.id::text
    when 'season_players' then 'season/' || new.id::text
    when 'guest_players' then 'guest/' || new.id::text
  end;
  if v_prefix is null then
    return new;
  end if;

  v_keep := substring(coalesce(new.photo_url, '') from '/profile-photos/(.*)$');

  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects
    where bucket_id = 'profile-photos'
      and name like v_prefix || '/%'
      and name is distinct from v_keep;
  exception when others then
    null;
  end;

  return new;
end;
$_$;


ALTER FUNCTION "public"."cleanup_replaced_photo"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cleanup_replaced_photo"() IS 'Fonction de trigger interne : supprime les anciennes photos remplacées.';



CREATE OR REPLACE FUNCTION "public"."close_match_predictions"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  update public.matches
  set predictions_closed_at = now(), updated_at = now()
  where id = p_match_id
    and status = 'a_venir'
    and predictions_closed_at is null;
  if not found then
    raise exception 'Open upcoming match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;


ALTER FUNCTION "public"."close_match_predictions"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.add_match_live_players(p_match_id, p_players, p_reason);
$$;


ALTER FUNCTION "public"."coach_add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.adjust_match_live_score(p_match_id, p_team, p_delta, p_scorer_participant_id); $$;


ALTER FUNCTION "public"."coach_adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.delete_match_live_event(p_match_id, p_event_id); $$;


ALTER FUNCTION "public"."coach_delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_end_match_live"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.end_match_live(p_match_id, p_reason); $$;


ALTER FUNCTION "public"."coach_end_match_live"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.publish_match_live_recap(
    p_match_id, p_score_as_grinta, p_score_adverse, p_participants, p_reason
  );
$$;


ALTER FUNCTION "public"."coach_publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_reopen_match_live"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.reopen_match_live(p_match_id, p_reason); $$;


ALTER FUNCTION "public"."coach_reopen_match_live"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_restart_match_live_session"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.restart_match_live_session(p_match_id, p_reason); $$;


ALTER FUNCTION "public"."coach_restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."coach_restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") IS 'Wipes a non-exported live session (events, clock, score) and restores the kickoff lineup.';



CREATE OR REPLACE FUNCTION "public"."coach_save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.save_match_live_lineup(p_match_id, p_entries, p_substitution); $$;


ALTER FUNCTION "public"."coach_save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.set_match_live_clock_state(p_match_id, p_action, p_reason); $$;


ALTER FUNCTION "public"."coach_set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."coach_set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid" DEFAULT NULL::"uuid", "p_is_opponent_own_goal" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.set_match_live_event_scorer(
    p_match_id, p_event_id, p_scorer_participant_id, p_is_opponent_own_goal
  );
$$;


ALTER FUNCTION "public"."coach_set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_password_change"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set must_change_password = false,
      password_set = true,
      updated_at = now()
  where id = actor_id
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return true;
end;
$$;


ALTER FUNCTION "public"."complete_password_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.confirm_start_match_live(p_match_id, p_reason); $$;


ALTER FUNCTION "public"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consume_registration_rate_limit"("p_origin_hash" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_origin_hour integer;
  v_origin_day integer;
begin
  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid origin hash' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_origin_hash, 0)
  );

  delete from private.registration_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer
  into v_origin_hour
  from private.registration_attempts
  where origin_hash = p_origin_hash
    and attempted_at >= now() - interval '1 hour';

  select count(*)::integer
  into v_origin_day
  from private.registration_attempts
  where origin_hash = p_origin_hash
    and attempted_at >= now() - interval '24 hours';

  -- Le plafond reste strict par origine (5/h, 15/j), mais il n'existe plus
  -- de quota global partagé : une attaque distribuée ne peut donc plus
  -- épuiser un compteur commun et bloquer les inscriptions légitimes.
  if v_origin_hour >= 5 or v_origin_day >= 15 then
    return false;
  end if;

  insert into private.registration_attempts(origin_hash)
  values (p_origin_hash);

  return true;
end;
$_$;


ALTER FUNCTION "public"."consume_registration_rate_limit"("p_origin_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_internal_match"("p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_address" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  new_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Season, date and time are required' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Match date is outside allowed bounds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.seasons s where s.id = p_season_id and s.status = 'open'
  ) then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;

  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, match_type, address, created_by
  ) values (
    p_season_id, null, p_match_date, p_match_time, 'domicile',
    90, 'a_venir', 'entre_nous', nullif(btrim(p_address), ''), (select auth.uid())
  ) returning id into new_id;

  perform private.configure_match_sport_workflow(new_id, 30);

  return new_id;
end;
$$;


ALTER FUNCTION "public"."create_internal_match"("p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_address" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_match_with_odds"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  new_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_opponent_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Season, opponent, date and time are required' using errcode = '22023';
  end if;
  if p_location is null or p_location not in ('domicile', 'exterieur') then
    raise exception 'Invalid location' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Match date is outside allowed bounds' using errcode = '22023';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.seasons s
    where s.id = p_season_id and s.status = 'open'
  ) then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;
  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, created_by
  ) values (
    p_season_id, p_opponent_id, p_match_date, p_match_time, p_location,
    90, 'a_venir', (select auth.uid())
  ) returning id into new_id;
  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul,
    odds_victoire_adverse, computed_at
  ) values (
    new_id, round(p_win, 2), round(p_draw, 2), round(p_loss, 2), now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();
  return new_id;
end;
$$;


ALTER FUNCTION "public"."create_match_with_odds"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_match_with_odds_and_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) RETURNS "uuid"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.create_match_with_sport_limit(
    p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_win, p_draw, p_loss, p_squad_size_limit
  );
$$;


ALTER FUNCTION "public"."create_match_with_odds_and_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_profile_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select role from public.profiles where id=auth.uid() $$;


ALTER FUNCTION "public"."current_profile_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_match"("p_match_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

  delete from public.match_live_events where match_id = p_match_id;
  delete from public.match_live_sessions where match_id = p_match_id;
  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  delete from public.match_sport_motm_elections where match_id = p_match_id;
  delete from public.match_composition_entries where match_id = p_match_id;
  delete from public.match_composition_publications where match_id = p_match_id;
  delete from public.match_compositions where match_id = p_match_id;
  delete from public.match_sport_participant_events where match_id = p_match_id;
  delete from public.sport_availability_notification_events where match_id = p_match_id;
  delete from public.match_sport_finalization_versions where match_id = p_match_id;
  delete from public.match_sport_finalizations where match_id = p_match_id;
  delete from public.match_sport_participants where match_id = p_match_id;
  delete from public.match_sport_workflows where match_id = p_match_id;
  delete from public.match_attendance where match_id = p_match_id;
  delete from public.match_player_stats where match_id = p_match_id;
  delete from public.match_predictions where match_id = p_match_id;
  delete from public.match_odds where match_id = p_match_id;
  delete from public.push_delivery_log where match_id = p_match_id;
  delete from public.push_notification_log where match_id = p_match_id;

  delete from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;


ALTER FUNCTION "public"."delete_match"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."featured_badges"() RETURNS TABLE("profile_id" "uuid", "code" "text", "emoji" "text", "image_url" "text", "color" "text", "metric" "text", "threshold" integer, "has_star" boolean, "stars" integer, "category" "text", "sort_order" integer)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  with starred_featured as materialized (
    select distinct
      profile_badge.profile_id,
      badge.code
    from public.profile_badges profile_badge
    join public.badges badge on badge.id = profile_badge.badge_id
    where profile_badge.featured
      and badge.has_star
  ),
  starred_profiles as materialized (
    select distinct starred_featured.profile_id
    from starred_featured
  ),
  featured_stars as materialized (
    select
      starred_profile.profile_id,
      badge_star.badge_code,
      badge_star.stars
    from starred_profiles starred_profile
    cross join lateral public.profile_badge_stars(
      starred_profile.profile_id
    ) badge_star
    join starred_featured
      on starred_featured.profile_id = starred_profile.profile_id
     and starred_featured.code = badge_star.badge_code
  )
  select
    profile_badge.profile_id,
    badge.code,
    badge.emoji,
    badge.image_url,
    badge.color,
    badge.metric,
    badge.threshold,
    badge.has_star,
    coalesce(featured_star.stars, 1) as stars,
    badge.category,
    badge.sort_order
  from public.profile_badges profile_badge
  join public.badges badge on badge.id = profile_badge.badge_id
  left join featured_stars featured_star
    on featured_star.profile_id = profile_badge.profile_id
   and featured_star.badge_code = badge.code
  where profile_badge.featured
  order by profile_badge.profile_id, badge.sort_order;
$$;


ALTER FUNCTION "public"."featured_badges"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."featured_badges"() IS 'Badges arborés, avec étoiles calculées une seule fois par profil distinct.';



CREATE OR REPLACE FUNCTION "public"."finalize_match_postgame"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid" DEFAULT NULL::"uuid", "p_score_as_grinta" integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  item jsonb;
  match_season_id uuid;
  scorer_id uuid;
  scorer_goals integer;
  total_goals integer := 0;
  scorer_count integer := 0;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta < 0 or p_score_as_grinta > 99
     or p_score_adverse < 0 or p_score_adverse > 99 then
    raise exception 'Scores must be between 0 and 99' using errcode = '22023';
  end if;
  if p_scorers is null or jsonb_typeof(p_scorers) <> 'array' then
    raise exception 'Scorers payload must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_scorers) > 30 then
    raise exception 'Too many scorer entries' using errcode = '22023';
  end if;
  select m.season_id into match_season_id
  from public.matches m
  where m.id = p_match_id and m.status in ('a_venir', 'termine')
  for update;
  if not found then
    raise exception 'Only upcoming or finished matches can be validated' using errcode = 'P0002';
  end if;
  for item in select value from jsonb_array_elements(p_scorers)
  loop
    scorer_count := scorer_count + 1;
    if jsonb_typeof(item) <> 'object' then
      raise exception 'Each scorer entry must be an object' using errcode = '22023';
    end if;
    if not (item ? 'season_player_id') or not (item ? 'goals')
       or exists (
         select 1 from jsonb_object_keys(item) as key
         where key not in ('season_player_id', 'goals')
       ) then
      raise exception 'Invalid scorer entry schema' using errcode = '22023';
    end if;
    if jsonb_typeof(item->'season_player_id') <> 'string'
       or jsonb_typeof(item->'goals') <> 'number'
       or (item->>'goals') !~ '^[0-9]+$' then
      raise exception 'Invalid scorer entry types' using errcode = '22023';
    end if;
    begin
      scorer_id := (item->>'season_player_id')::uuid;
      scorer_goals := (item->>'goals')::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid scorer entry values' using errcode = '22023';
    end;
    if scorer_goals < 1 or scorer_goals > 99 then
      raise exception 'Scorer goals must be between 1 and 99' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = scorer_id and sp.season_id = match_season_id and sp.is_active
    ) then
      raise exception 'Scorer is not an active player in the match season' using errcode = '22023';
    end if;
    total_goals := total_goals + scorer_goals;
    if total_goals > 99 or total_goals > p_score_as_grinta then
      raise exception 'Attributed goals exceed the AS Grinta score' using errcode = '22023';
    end if;
  end loop;
  if p_score_as_grinta = 0 and scorer_count > 0 then
    raise exception 'A score of zero cannot contain scorers' using errcode = '22023';
  end if;
  if p_clean_sheet_player_id is not null then
    if p_score_adverse <> 0 then
      raise exception 'Clean sheet is impossible when the opponent scored' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = p_clean_sheet_player_id
        and sp.season_id = match_season_id
        and sp.is_goalkeeper
        and sp.is_active
    ) then
      raise exception 'Clean sheet must belong to an active goalkeeper in the match season' using errcode = '22023';
    end if;
  end if;
  delete from public.match_player_stats where match_id = p_match_id;
  insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
  select p_match_id,
         (entry->>'season_player_id')::uuid,
         sum((entry->>'goals')::integer),
         false
  from jsonb_array_elements(p_scorers) as entry
  group by (entry->>'season_player_id')::uuid;
  if p_clean_sheet_player_id is not null then
    insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
    values (p_match_id, p_clean_sheet_player_id, 0, true)
    on conflict (match_id, season_player_id) do update set clean_sheet = true;
  end if;
  update public.matches
  set score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      status = 'termine',
      predictions_closed_at = coalesce(predictions_closed_at, now()),
      result_validated_at = now(),
      updated_at = now()
  where id = p_match_id;
  return true;
end;
$_$;


ALTER FUNCTION "public"."finalize_match_postgame"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_match_postgame_with_lineup"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid" DEFAULT NULL::"uuid", "p_score_as_grinta" integer DEFAULT NULL::integer, "p_present" "uuid"[] DEFAULT '{}'::"uuid"[], "p_man_of_match_player_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_scorer jsonb;
  v_scorer_id uuid;
  v_mvp_players uuid[];
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  if p_present is null or cardinality(p_present) = 0 then
    raise exception 'At least one present player is required' using errcode = '22023';
  end if;

  if array_position(p_present, null) is not null then
    raise exception 'Present players cannot contain null values' using errcode = '22023';
  end if;

  if p_scorers is null or jsonb_typeof(p_scorers) <> 'array' then
    raise exception 'Scorers payload must be a JSON array' using errcode = '22023';
  end if;

  for v_scorer in select value from jsonb_array_elements(p_scorers)
  loop
    begin
      v_scorer_id := (v_scorer->>'season_player_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid scorer player id' using errcode = '22023';
    end;

    if not (v_scorer_id = any(p_present)) then
      raise exception 'Every scorer must be marked as present' using errcode = '22023';
    end if;
  end loop;

  if p_clean_sheet_player_id is not null
     and not (p_clean_sheet_player_id = any(p_present)) then
    raise exception 'The clean sheet goalkeeper must be marked as present'
      using errcode = '22023';
  end if;

  if p_man_of_match_player_id is not null
     and not (p_man_of_match_player_id = any(p_present)) then
    raise exception 'The man of the match must be marked as present'
      using errcode = '22023';
  end if;

  perform public.staff_set_match_attendance(p_match_id, p_present);

  v_mvp_players := case
    when p_man_of_match_player_id is null then '{}'::uuid[]
    else array[p_man_of_match_player_id]
  end;
  perform public.staff_set_match_mvp(p_match_id, v_mvp_players);

  return public.finalize_match_postgame(
    p_match_id,
    p_score_adverse,
    p_scorers,
    p_clean_sheet_player_id,
    p_score_as_grinta
  );
end;
$$;


ALTER FUNCTION "public"."finalize_match_postgame_with_lineup"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer, "p_present" "uuid"[], "p_man_of_match_player_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."finalize_match_postgame_with_lineup"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer, "p_present" "uuid"[], "p_man_of_match_player_id" "uuid") IS 'Enregistre atomiquement le résultat, les joueurs présents et le HDM.';



CREATE OR REPLACE FUNCTION "public"."get_all_historical_match_results"() RETURNS TABLE("id" "uuid", "match_date" "date", "opponent_name" "text", "score_as_grinta" smallint, "score_adverse" smallint, "is_home" boolean)
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select * from private.get_all_historical_match_results();
$$;


ALTER FUNCTION "public"."get_all_historical_match_results"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_all_historical_match_results"() IS 'Read-only compact match history across every archived season; authorization is enforced by a private helper.';



CREATE OR REPLACE FUNCTION "public"."get_historical_match_detail"("p_match_id" "uuid") RETURNS TABLE("formation" "text", "field_players" "jsonb", "bench_players" "jsonb", "present_names" "jsonb", "scorers" "jsonb", "motm_names" "jsonb", "photo_urls" "jsonb")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select * from private.get_historical_match_detail(p_match_id);
$$;


ALTER FUNCTION "public"."get_historical_match_detail"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_historical_match_detail"("p_match_id" "uuid") IS 'Read-only historical match detail (composition/buteurs/HDM) for one match_id, with a source-name -> photo_url map for identified players; authorization is enforced by a private helper.';



CREATE OR REPLACE FUNCTION "public"."get_historical_match_results"("p_season_name" "text") RETURNS TABLE("id" "uuid", "match_date" "date", "opponent_name" "text", "score_as_grinta" smallint, "score_adverse" smallint, "is_home" boolean)
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select * from private.get_historical_match_results(p_season_name);
$$;


ALTER FUNCTION "public"."get_historical_match_results"("p_season_name" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_historical_match_results"("p_season_name" "text") IS 'Read-only compact match history for one YYYY-YYYY season; authorization is enforced by a private helper.';



CREATE OR REPLACE FUNCTION "public"."get_last_opponent_encounters"("p_match_id" "uuid") RETURNS TABLE("encounter_date" "date", "grinta_score" integer, "opponent_score" integer)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_opponent_id uuid;
  v_reference_date date;
begin
  if not public.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select m.opponent_id, m.match_date
  into v_opponent_id, v_reference_date
  from public.matches m
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  return query
  with all_results as (
    select
      m.id,
      m.match_date,
      m.score_as_grinta::integer as score_as_grinta,
      m.score_adverse::integer as score_adverse
    from public.matches m
    where m.opponent_id = v_opponent_id
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null

    union all

    select
      h.id,
      h.match_date,
      h.score_as_grinta::integer as score_as_grinta,
      h.score_adverse::integer as score_adverse
    from public.historical_match_scores h
    where h.opponent_id = v_opponent_id
  ), deduplicated as (
    select distinct on (r.id)
      r.id,
      r.match_date,
      r.score_as_grinta,
      r.score_adverse
    from all_results r
    order by r.id, r.match_date desc
  )
  select
    d.match_date,
    d.score_as_grinta,
    d.score_adverse
  from deduplicated d
  where d.match_date < v_reference_date
  order by d.match_date desc, d.id desc
  limit 5;
end;
$$;


ALTER FUNCTION "public"."get_last_opponent_encounters"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_last_opponent_encounters"("p_match_id" "uuid") IS 'Returns the five latest completed matches against the opponent of a match, including compacted history.';



CREATE OR REPLACE FUNCTION "public"."get_match_availability_board"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_match_availability_board(p_match_id); $$;


ALTER FUNCTION "public"."get_match_availability_board"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_match_availability_board"("p_match_id" "uuid") IS 'Present/absent/no-response lists for one match, visible to active profiles until the composition is published.';



CREATE OR REPLACE FUNCTION "public"."get_match_live_add_player_options"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.get_match_live_add_player_options(p_match_id);
$$;


ALTER FUNCTION "public"."get_match_live_add_player_options"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_match_live_state"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.match_live_snapshot(p_match_id); $$;


ALTER FUNCTION "public"."get_match_live_state"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_match_live_timeline"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_match_live_timeline(p_match_id); $$;


ALTER FUNCTION "public"."get_match_live_timeline"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_match_motm_vote"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.get_match_motm_vote(p_match_id);
$$;


ALTER FUNCTION "public"."get_match_motm_vote"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_match_sport_result"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_published_match_sport_result(p_match_id); $$;


ALTER FUNCTION "public"."get_match_sport_result"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_match_sport_result"("p_match_id" "uuid") IS 'Returns the validated result and all permanent/guest participant statistics to active profiles.';



CREATE OR REPLACE FUNCTION "public"."get_my_match_availability"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_my_match_availability(p_match_id); $$;


ALTER FUNCTION "public"."get_my_match_availability"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_my_match_availability"("p_match_id" "uuid") IS 'Returns the signed-in player private availability state and effective response window.';



CREATE OR REPLACE FUNCTION "public"."get_my_profile"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
  result jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select to_jsonb(p)
  into result
  from public.profiles p
  where p.id = actor_id
    and p.status = 'active';

  if result is null then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return result;
end;
$$;


ALTER FUNCTION "public"."get_my_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_opponent"("p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  normalized_name text := btrim(coalesce(p_name, ''));
  opponent_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if length(normalized_name) < 2 or length(normalized_name) > 100 then
    raise exception 'Opponent name must contain between 2 and 100 characters' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(normalized_name), 0));
  select o.id into opponent_id
  from public.opponents o
  where lower(btrim(o.name)) = lower(normalized_name)
  limit 1;
  if opponent_id is null then
    insert into public.opponents(name)
    values (normalized_name)
    returning id into opponent_id;
  end if;
  return opponent_id;
end;
$$;


ALTER FUNCTION "public"."get_or_create_opponent"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_public_feature_flags"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.get_public_feature_flags();
$$;


ALTER FUNCTION "public"."get_public_feature_flags"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_public_feature_flags"() IS 'Returns public-safe server feature flags for authenticated application users.';



CREATE OR REPLACE FUNCTION "public"."get_published_match_composition"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$ select private.get_published_match_composition(p_match_id); $$;


ALTER FUNCTION "public"."get_published_match_composition"("p_match_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_published_match_composition"("p_match_id" "uuid") IS 'Returns only the latest immutable published snapshot while the sports-management module is active.';



CREATE OR REPLACE FUNCTION "public"."get_sport_waitlist"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select private.enrich_sport_waitlist_history(
    private.get_sport_waitlist_readonly(p_season_id)
  );
$$;


ALTER FUNCTION "public"."get_sport_waitlist"("p_season_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_sport_waitlist"("p_season_id" "uuid") IS 'Lecture seule de la liste d''attente de la saison, accessible à tout joueur actif ; aucune modification possible par cette voie.';



CREATE OR REPLACE FUNCTION "public"."guard_match_prediction_window"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_kickoff timestamptz;
  v_match_status text;
  v_closed_at timestamptz;
begin
  if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then
    if tg_op = 'UPDATE' and new.match_id is distinct from old.match_id then
      raise exception 'Le match d’un pronostic ne peut pas être modifié.' using errcode = '22023';
    end if;
    new.profile_id := (select auth.uid());
  end if;

  if new.is_filled then
    select m.kickoff_at, m.status, m.predictions_closed_at
    into v_kickoff, v_match_status, v_closed_at
    from public.matches m
    where m.id = new.match_id;

    if v_kickoff is null
       or v_match_status <> 'a_venir'
       or now() < private.match_features_open_at(v_kickoff)
       or now() >= private.match_prediction_closes_at(v_kickoff)
       or (v_closed_at is not null and now() >= v_closed_at) then
      raise exception 'Pronostic fermé' using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."guard_match_prediction_window"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_sensitive_profile_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
  old_protected jsonb;
  new_protected jsonb;
begin
  if actor_id is null then
    return new;
  end if;
  if public.is_match_staff() then
    return new;
  end if;
  if actor_id is distinct from old.id then
    raise exception 'Un utilisateur ne peut modifier que son propre profil.'
      using errcode = '42501';
  end if;

  old_protected := to_jsonb(old) - array[
    'first_name','last_name','surnom','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation',
    'password_set','must_change_password'
  ];
  new_protected := to_jsonb(new) - array[
    'first_name','last_name','surnom','updated_at',
    'notify_prediction_open','notify_prediction_reminders','notify_match_reminders',
    'notify_motm_vote','notify_convocation',
    'password_set','must_change_password'
  ];

  if new_protected is distinct from old_protected then
    raise exception 'Les champs sensibles du profil ne peuvent pas être modifiés.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."guard_sensitive_profile_fields"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.profiles(
    id, email, first_name, last_name, role, is_goalkeeper, status
  )
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    'pronostiqueur',
    false,
    'pending'
  )
  on conflict (id) do update
  set email = excluded.email,
      first_name = case when public.profiles.first_name = '' then excluded.first_name else public.profiles.first_name end,
      last_name = case when public.profiles.last_name = '' then excluded.last_name else public.profiles.last_name end,
      updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_mark_sport_notification_delivery"("p_event_id" bigint, "p_attempted" integer, "p_sent" integer, "p_failed" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.sport_availability_notification_events
  set attempted_count = greatest(coalesce(p_attempted, 0), 0),
      sent_count = greatest(coalesce(p_sent, 0), 0),
      failed_count = greatest(coalesce(p_failed, 0), 0),
      dispatch_status = case
        when greatest(coalesce(p_attempted, 0), 0) = 0 then 'no_subscription'
        else 'completed'
      end,
      delivery_completed_at = now()
  where id = p_event_id;

  return found;
end;
$$;


ALTER FUNCTION "public"."internal_mark_sport_notification_delivery"("p_event_id" bigint, "p_attempted" integer, "p_sent" integer, "p_failed" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_match_weather_candidates"("p_match_id" "uuid" DEFAULT NULL::"uuid", "p_now" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("match_id" "uuid", "kickoff_at" timestamp with time zone, "planned_duration_minutes" integer, "resolved_address" "text", "cached_latitude" double precision, "cached_longitude" double precision, "cached_geocoded_address" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select
    match.id,
    match.kickoff_at,
    match.planned_duration_minutes,
    address.resolved_address,
    weather.latitude,
    weather.longitude,
    weather.geocoded_address
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  left join public.club_settings club on club.id
  left join public.match_weather weather on weather.match_id = match.id
  cross join lateral (
    select coalesce(
      nullif(btrim(match.address), ''),
      case
        when match.location = 'domicile'
          then nullif(btrim(club.home_address), '')
        else nullif(btrim(opponent.address), '')
      end
    ) as resolved_address
  ) address
  where match.status = 'a_venir'
    and match.kickoff_at is not null
    and match.kickoff_at > p_now
    and private.match_features_open_at(match.kickoff_at) <= p_now
    and address.resolved_address is not null
    and (p_match_id is null or match.id = p_match_id)
    and (
      weather.match_id is null
      or weather.forecast_for is distinct from match.kickoff_at
      or weather.geocoded_address is distinct from address.resolved_address
      or weather.fetched_at is null
      or weather.fetched_at <= p_now - private.match_weather_refresh_interval(
        match.kickoff_at,
        p_now
      )
    )
  order by match.kickoff_at;
$$;


ALTER FUNCTION "public"."internal_match_weather_candidates"("p_match_id" "uuid", "p_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_push_config"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object(
    'vapid_public', max(decrypted_secret) filter (where name = 'push_vapid_public'),
    'vapid_private', max(decrypted_secret) filter (where name = 'push_vapid_private'),
    'token', max(decrypted_secret) filter (where name = 'push_internal_token'),
    'notifications_paused', private.is_feature_enabled('notifications_paused')
  )
  from vault.decrypted_secrets
  where name in ('push_vapid_public', 'push_vapid_private', 'push_internal_token');
$$;


ALTER FUNCTION "public"."internal_push_config"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_push_delivery_health"("p_since" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval)) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select jsonb_build_object(
    'since', p_since,
    'attempted', count(*)::integer,
    'sent', count(*) filter (where delivery.success)::integer,
    'failed', count(*) filter (where not delivery.success)::integer,
    'expired', count(*) filter (
      where not delivery.success and delivery.status_code in (404, 410)
    )::integer,
    'transient_failures', count(*) filter (
      where not delivery.success
        and (
          delivery.status_code is null
          or delivery.status_code in (408, 425, 429)
          or delivery.status_code >= 500
        )
    )::integer,
    'retry_recoveries', count(*) filter (
      where delivery.success and delivery.attempts > 1
    )::integer,
    'retry_exhausted', count(*) filter (
      where not delivery.success
        and delivery.attempts > 1
        and (
          delivery.status_code is null
          or delivery.status_code in (408, 425, 429)
          or delivery.status_code >= 500
        )
    )::integer,
    'latest_delivery_at', max(delivery.created_at),
    'requires_attention', count(*) filter (
      where not delivery.success
        and coalesce(delivery.status_code not in (404, 410), true)
    ) > 0
  )
  from public.push_delivery_log delivery
  where delivery.created_at >= p_since;
$$;


ALTER FUNCTION "public"."internal_push_delivery_health"("p_since" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_push_dispatch"("p_kind" "text", "p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_date text;
  v_time text;
begin
  select
    m.id,
    m.kickoff_at,
    m.status,
    coalesce(o.name, 'Match entre nous') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null then
    raise exception 'Match kickoff is required' using errcode = '22023';
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  if p_kind = 'prediction_j5' then
    v_payload := jsonb_build_object(
      'title', 'Pronostic',
      'body', format(
        'Pense à pronostiquer pour le match du %s contre %s.',
        v_date,
        v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=prediction',
      'tag', 'match-' || p_match_id || '-prediction-j5'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_prediction_reminders
      and not exists (
        select 1
        from public.match_predictions prediction
        where prediction.match_id = p_match_id
          and prediction.profile_id = profile.id
          and prediction.is_filled
      );

  elsif p_kind in ('match_cancelled', 'match_rescheduled_date', 'match_rescheduled_time') then
    v_payload := case p_kind
      when 'match_cancelled' then jsonb_build_object(
        'title', 'Match annulé',
        'body', format(
          'Le match du %s contre %s à %s est annulé.',
          v_date, v_match.opponent_name, v_time
        ),
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-cancelled'
      )
      when 'match_rescheduled_date' then jsonb_build_object(
        'title', 'Match reporté',
        'body', case
          when private.match_features_open_at(v_match.kickoff_at) <= now()
            then format(
              'Le match contre %s est reporté au %s à %s. Es-tu disponible ?',
              v_match.opponent_name, v_date, v_time
            )
          else format(
            'Le match contre %s est reporté au %s à %s.',
            v_match.opponent_name, v_date, v_time
          )
        end,
        'url', 'matches/' || p_match_id || '/lineup?section=effectif',
        'tag', 'match-' || p_match_id || '-rescheduled-date'
      )
      else jsonb_build_object(
        'title', 'Horaire du match modifié',
        'body', format(
          'Le match du %s contre %s aura finalement lieu à %s.',
          v_date, v_match.opponent_name, v_time
        ),
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-rescheduled-time'
      )
    end;

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.is_eligible
          and player.profile_id = profile.id
      );

  elsif p_kind = 'motm_open' then
    if not private.is_feature_enabled('sports_management') then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;
    if not exists (
      select 1
      from public.match_sport_motm_elections election
      where election.match_id = p_match_id
        and election.state = 'open'
        and now() >= election.opens_at
        and now() < election.closes_at
    ) then
      return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
    end if;

    v_payload := jsonb_build_object(
      'title', 'Homme du match',
      'body', 'Pense à voter pour l’homme du match.',
      'url', 'matches/' || p_match_id || '/vote',
      'tag', 'sport-' || p_match_id || '-motm-open'
    );

    select coalesce(jsonb_agg(jsonb_build_object(
      'profile_id', subscription.profile_id,
      'endpoint', subscription.endpoint,
      'p256dh', subscription.p256dh,
      'auth', subscription.auth
    )), '[]'::jsonb)
    into v_subscriptions
    from public.push_subscriptions subscription
    join public.profiles profile on profile.id = subscription.profile_id
    where profile.status = 'active'
      and profile.notify_motm_vote
      and exists (
        select 1
        from private.match_motm_candidate_participants(p_match_id) candidate
        join public.match_sport_participants participant on participant.id = candidate.participant_id
        join public.season_players player on player.id = participant.season_player_id
        where player.profile_id = profile.id
      );

  else
    raise exception 'Unknown notification kind: %', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb)
  );
end;
$$;


ALTER FUNCTION "public"."internal_push_dispatch"("p_kind" "text", "p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_push_notify"("p_kind" "text", "p_match_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'push_internal_token';

  if v_token is null then
    return;
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('kind', p_kind, 'match_id', p_match_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );
exception when others then
  -- L'envoi de notification ne doit jamais faire échouer la transaction métier.
  null;
end;
$$;


ALTER FUNCTION "public"."internal_push_notify"("p_kind" "text", "p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_push_prune"("p_endpoints" "text"[]) RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  with deleted as (
    delete from public.push_subscriptions
    where endpoint = any(p_endpoints)
    returning 1
  )
  select count(*)::integer from deleted;
$$;


ALTER FUNCTION "public"."internal_push_prune"("p_endpoints" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."internal_sport_push_dispatch"("p_kind" "text", "p_match_id" "uuid", "p_profile_ids" "uuid"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_payload jsonb;
  v_subscriptions jsonb;
  v_date text;
  v_time text;
begin
  if p_kind not in ('availability_open', 'availability_manual', 'convocation_promoted') then
    raise exception 'Unknown sports notification kind' using errcode = '22023';
  end if;
  if p_profile_ids is null or cardinality(p_profile_ids) = 0 then
    return jsonb_build_object('payload', '{}'::jsonb, 'subscriptions', '[]'::jsonb);
  end if;

  select m.id, m.kickoff_at, coalesce(o.name, 'Match entre nous') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  v_payload := case p_kind
    when 'availability_open' then jsonb_build_object(
      'title', 'Disponibilité',
      'body', format(
        'Dispo pour le match du %s contre %s à %s ?',
        v_date, v_match.opponent_name, v_time
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-availability-open'
    )
    when 'availability_manual' then jsonb_build_object(
      'title', 'Tu n''as pas répondu 👀',
      'body', format(
        'Pense à indiquer si tu es dispo pour le match contre %s !',
        v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-availability-manual'
    )
    else jsonb_build_object(
      'title', 'Tu es convoqué',
      'body', format(
        'Tu es convoqué pour le match du %s contre %s.',
        v_date, v_match.opponent_name
      ),
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-convocation'
    )
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id', subscription.profile_id,
    'endpoint', subscription.endpoint,
    'p256dh', subscription.p256dh,
    'auth', subscription.auth
  )), '[]'::jsonb)
  into v_subscriptions
  from public.push_subscriptions subscription
  join public.profiles profile on profile.id = subscription.profile_id
  where subscription.profile_id = any(p_profile_ids)
    and profile.status = 'active'
    and (
      (p_kind = 'availability_open' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.is_eligible
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and participant.is_eligible
          and participant.availability_status = 'no_response'
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'convocation_promoted'
          and profile.notify_convocation
          and exists (
            select 1
            from public.match_sport_participants participant
            join public.season_players player on player.id = participant.season_player_id
            join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
            where participant.match_id = p_match_id
              and participant.is_eligible
              and participant.convocation_status = 'convoked'
              and workflow.convocation_state = 'published'
              and player.profile_id = subscription.profile_id
          ))
    );

  return jsonb_build_object('payload', v_payload, 'subscriptions', v_subscriptions);
end;
$$;


ALTER FUNCTION "public"."internal_sport_push_dispatch"("p_kind" "text", "p_match_id" "uuid", "p_profile_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_active_profile"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.is_active_profile(); $$;


ALTER FUNCTION "public"."is_active_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.is_admin(); $$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_match_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select private.is_match_staff(); $$;


ALTER FUNCTION "public"."is_match_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_moderator"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'active'
  );
$$;


ALTER FUNCTION "public"."is_moderator"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."is_moderator"() IS 'Deprecated compatibility alias. Returns true for an active admin.';



CREATE OR REPLACE FUNCTION "public"."is_valid_person_name"("txt" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $_$
  select case
    when txt is null then true
    when btrim(txt) = '' then true
    else btrim(txt) ~ '^[[:alpha:] ''’-]+$' and btrim(txt) ~ '[[:alpha:]]'
  end;
$_$;


ALTER FUNCTION "public"."is_valid_person_name"("txt" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_prediction_participant_count"("p_match_id" "uuid") RETURNS integer
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.matches m where m.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return (
    select count(*)::integer
    from public.match_predictions mp
    where mp.match_id = p_match_id and mp.is_filled
  );
end;
$$;


ALTER FUNCTION "public"."match_prediction_participant_count"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$ select private.open_match_live_workspace(p_match_id, p_planned_duration_minutes); $$;


ALTER FUNCTION "public"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."open_or_create_season"("p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
    raise exception 'Le nom doit respecter le format 2026-2027' using errcode = '22023';
  end if;
  start_year := substring(season_name from 1 for 4)::integer;
  end_year := substring(season_name from 6 for 4)::integer;
  if end_year <> start_year + 1 then
    raise exception 'La saison doit couvrir deux années consécutives' using errcode = '22023';
  end if;
  if start_year < 2000 or start_year > 2100 then
    raise exception 'Année de saison hors limites' using errcode = '22023';
  end if;
  select s.id into season_id from public.seasons s where s.name = season_name for update;
  update public.seasons
  set status = 'archived'
  where status = 'open' and (season_id is null or id <> season_id);
  if season_id is null then
    insert into public.seasons(name, status) values (season_name, 'open') returning id into season_id;
  else
    update public.seasons set status = 'open', season_predictions_locked_at = null where id = season_id;
  end if;
  return season_id;
end;
$_$;


ALTER FUNCTION "public"."open_or_create_season"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.prepare_profile_for_hard_deletion(p_profile_id);
end;
$$;


ALTER FUNCTION "public"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."preview_match_odds"("p_opponent_id" "uuid", "p_location" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_opponent_id is null then
    raise exception 'Opponent id is required' using errcode = '22023';
  end if;
  if p_location is null or p_location not in ('domicile', 'exterieur') then
    raise exception 'Invalid location' using errcode = '22023';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;
  return public.calculate_match_odds_v4(p_opponent_id, p_location);
end;
$$;


ALTER FUNCTION "public"."preview_match_odds"("p_opponent_id" "uuid", "p_location" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") RETURNS TABLE("matches_played_season" integer, "wins_season" integer, "goals_season" integer, "clean_sheets_season" integer, "matches_played" integer, "wins" integer, "goals" integer, "doubles" integer, "max_match_goals" integer, "mvp" integer, "clean_sheets" integer, "pred_good_result" integer, "pred_exact_score" integer, "bet_against_grinta" integer, "perfect_own_goals_prediction" integer, "seasons_complete" integer, "title_most_present" integer, "title_top_scorer" integer, "title_mvp_king" integer, "title_best_winrate" integer, "title_best_pred_player" integer, "title_best_pred_match" integer, "title_best_pred_overall" integer)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  with pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.clean_sheet, false) as cs,
           (mv.season_player_id is not null) as is_mvp
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id and att.match_id = m.id
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (st.match_id is not null or att.match_id is not null or mv.match_id is not null)
  ), ps as (
    select season_id,
           count(*) as mp,
           count(*) filter (where win) as w,
           sum(g) as gg,
           count(*) filter (where cs) as csn,
           count(*) filter (where is_mvp) as mvpn,
           count(*) filter (where g = 2) as dbl
    from pm group by season_id
  ), player as (
    select
      coalesce(max(ps.mp) filter (where s.status = 'open'), 0)::int as matches_played_season,
      coalesce(max(ps.w) filter (where s.status = 'open'), 0)::int as wins_season,
      coalesce(max(ps.gg) filter (where s.status = 'open'), 0)::int as goals_season,
      coalesce(max(ps.csn) filter (where s.status = 'open'), 0)::int as clean_sheets_season,
      coalesce(sum(ps.mp), 0)::int as matches_played,
      coalesce(sum(ps.w), 0)::int as wins,
      coalesce(sum(ps.gg), 0)::int as goals,
      coalesce(sum(ps.dbl), 0)::int as doubles,
      coalesce(sum(ps.mvpn), 0)::int as mvp,
      coalesce(sum(ps.csn), 0)::int as clean_sheets
    from ps
    left join public.seasons s on s.id = ps.season_id
  ), hist as (
    select
      coalesce(sum(h.matches_played), 0)::int as h_mp,
      coalesce(sum(h.wins), 0)::int as h_w,
      coalesce(sum(h.goals), 0)::int as h_g,
      coalesce(sum(h.clean_sheets), 0)::int as h_cs,
      coalesce(sum(h.hdm), 0)::int as h_mvp
    from public.historical_player_statistics h
    where h.scope = 'all_time'
      and (
        h.profile_id = p_profile_id
        or (
          h.profile_id is null
          and lower(btrim(h.player_name)) in (
            select distinct lower(btrim(concat_ws(' ', sp.first_name, nullif(sp.last_name, ''))))
            from public.season_players sp
            where sp.profile_id = p_profile_id
              and coalesce(btrim(sp.first_name), '') <> ''
          )
        )
      )
  ), pmax as (
    select coalesce(max(g), 0)::int as max_match_goals from pm
  ), mpred as (
    select
      (mp.is_filled and sign((mp.predicted_score_as_grinta - mp.predicted_score_adverse)::numeric)
        = sign((m.score_as_grinta - m.score_adverse)::numeric))::int as bon,
      (mp.is_filled and mp.predicted_score_as_grinta = m.score_as_grinta
        and mp.predicted_score_adverse = m.score_adverse)::int as ex,
      (mp.is_filled and mp.predicted_score_as_grinta < mp.predicted_score_adverse)::int as against
    from public.match_predictions mp
    join public.matches m on m.id = mp.match_id and m.status in ('termine', 'archive')
    where mp.profile_id = p_profile_id
  ), mpred_a as (
    select coalesce(sum(bon), 0)::int as pred_good_result,
           coalesce(sum(ex), 0)::int as pred_exact_score,
           coalesce(sum(against), 0)::int as bet_against_grinta
    from mpred
  ), own_goal_pred as (
    select coalesce(count(*), 0)::int as perfect_own_goals_prediction
    from public.season_predictions sp
    join public.season_players spl on spl.id = sp.season_player_id
    join public.seasons se on se.id = sp.season_id and se.status = 'archived'
    join lateral (
      select coalesce(sum(s.goals), 0)::int as g
      from public.match_player_stats s
      join public.matches m on m.id = s.match_id
        and m.season_id = sp.season_id and m.status in ('termine', 'archive')
      where s.season_player_id = sp.season_player_id
    ) tot on true
    where sp.predictor_profile_id = p_profile_id
      and spl.profile_id = p_profile_id
      and sp.category = 'buts'
      and sp.is_filled
      and sp.predicted_value_30 >= 1
      and sp.predicted_value_30 = tot.g
  ), aw as (
    select
      count(*) filter (where award_type = 'season_complete')::int as seasons_complete,
      count(*) filter (where award_type = 'most_present')::int as title_most_present,
      count(*) filter (where award_type = 'top_scorer')::int as title_top_scorer,
      count(*) filter (where award_type = 'mvp_king')::int as title_mvp_king,
      count(*) filter (where award_type = 'best_winrate')::int as title_best_winrate,
      count(*) filter (where award_type = 'best_pred_player')::int as title_best_pred_player,
      count(*) filter (where award_type = 'best_pred_match')::int as title_best_pred_match,
      count(*) filter (where award_type = 'best_pred_overall')::int as title_best_pred_overall
    from public.season_awards where profile_id = p_profile_id
  )
  select
    player.matches_played_season, player.wins_season, player.goals_season,
    player.clean_sheets_season,
    (player.matches_played + hist.h_mp)::int as matches_played,
    (player.wins + hist.h_w)::int as wins,
    (player.goals + hist.h_g)::int as goals,
    player.doubles, pmax.max_match_goals,
    (player.mvp + hist.h_mvp)::int as mvp,
    (player.clean_sheets + hist.h_cs)::int as clean_sheets,
    mpred_a.pred_good_result, mpred_a.pred_exact_score,
    mpred_a.bet_against_grinta, own_goal_pred.perfect_own_goals_prediction,
    aw.seasons_complete, aw.title_most_present, aw.title_top_scorer,
    aw.title_mvp_king, aw.title_best_winrate,
    aw.title_best_pred_player, aw.title_best_pred_match, aw.title_best_pred_overall
  from player, hist, pmax, mpred_a, own_goal_pred, aw;
$$;


ALTER FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") RETURNS TABLE("badge_code" "text", "stars" integer)
    LANGUAGE "sql"
    SET "search_path" TO 'public'
    AS $$
  with metrics as (
    select to_jsonb(t) as v from public.profile_badge_metrics(p_profile_id) t
  ), pm as (
    select m.season_id,
           (m.score_as_grinta > m.score_adverse) as win,
           coalesce(st.goals, 0) as g,
           coalesce(st.clean_sheet, false) as cs
    from public.season_players sp
    join public.matches m
      on m.season_id = sp.season_id and m.status in ('termine', 'archive')
    left join public.match_player_stats st
      on st.season_player_id = sp.id and st.match_id = m.id
    left join public.match_attendance att
      on att.season_player_id = sp.id and att.match_id = m.id
    left join public.match_man_of_match mv
      on mv.season_player_id = sp.id and mv.match_id = m.id
    where sp.profile_id = p_profile_id
      and (st.match_id is not null or att.match_id is not null or mv.match_id is not null)
  ), ps as (
    select season_id,
           count(*) as mp,
           count(*) filter (where win) as w,
           sum(g) as gg,
           count(*) filter (where cs) as csn
    from pm group by season_id
  ), seasonal as (
    select b.code as badge_code, count(*)::int as stars
    from public.badges b
    join ps on (
         (b.metric = 'goals_season' and ps.gg >= b.threshold)
      or (b.metric = 'wins_season' and ps.w >= b.threshold)
      or (b.metric = 'matches_played_season' and ps.mp >= b.threshold)
      or (b.metric = 'clean_sheets_season' and ps.csn >= b.threshold)
    )
    where b.has_star and b.category = 'joueur_saison'
    group by b.code
  ), palmares as (
    select b.code as badge_code, count(sa.*)::int as stars
    from public.badges b
    join public.season_awards sa
      on sa.profile_id = p_profile_id
     and sa.award_type = case
           when b.metric = 'seasons_complete' then 'season_complete'
           else substring(b.metric from 7)
         end
    where b.has_star and b.category = 'palmares'
    group by b.code
  ), career as (
    select b.code as badge_code,
           (coalesce((m.v ->> b.metric)::int, 0) / b.threshold)::int as stars
    from public.badges b
    cross join metrics m
    where b.has_star
      and b.category in ('joueur_all_time', 'pronos_all_time')
      and b.metric is not null
      and b.threshold is not null and b.threshold > 0
      and coalesce((m.v ->> b.metric)::int, 0) >= b.threshold
  )
  select badge_code, stars from seasonal
  union all
  select badge_code, stars from palmares
  union all
  select badge_code, stars from career;
$$;


ALTER FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_mvp_count"("p_profile_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(count(*), 0)::integer
  from public.match_man_of_match mvp
  join public.season_players sp on sp.id = mvp.season_player_id
  join public.matches m on m.id = mvp.match_id
    and m.status in ('termine', 'archive')
  where sp.profile_id = p_profile_id;
$$;


ALTER FUNCTION "public"."profile_mvp_count"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_closing_reminders"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_sent integer := 0;
begin
  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and m.kickoff_at is not null
      and now() >= m.kickoff_at - interval '2 hours'
      and now() < m.kickoff_at - interval '5 minutes'
      and (
        m.predictions_closed_at is null
        or now() < m.predictions_closed_at
      )
  loop
    insert into public.push_notification_log (match_id, kind)
    values (v_match.id, 'closing_soon')
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('closing_soon', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;


ALTER FUNCTION "public"."push_closing_reminders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_on_match_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.status = 'a_venir' then
    insert into public.push_notification_log (match_id, kind)
    values (new.id, 'new_match')
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('new_match', new.id);
    end if;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."push_on_match_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_on_motm_election_closed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if private.is_feature_enabled('sports_management')
     and new.state = 'closed'
     and old.state is distinct from 'closed' then
    perform private.try_motm_result_notification(
      'motm_result_general',
      new.match_id,
      now()
    );
    perform private.try_motm_result_notification(
      'motm_result_winner',
      new.match_id,
      now()
    );
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."push_on_motm_election_closed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_on_motm_election_opened"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_is_new_window boolean := false;
begin
  if not private.is_feature_enabled('sports_management') then
    return new;
  end if;

  if new.state = 'open' then
    if tg_op = 'INSERT' then
      v_is_new_window := true;
    else
      v_is_new_window := old.state is distinct from 'open'
        or old.opens_at is distinct from new.opens_at
        or old.closes_at is distinct from new.closes_at
        or old.finalization_version is distinct from new.finalization_version;
    end if;
  end if;

  if v_is_new_window then
    delete from public.push_notification_log
    where match_id = new.match_id
      and kind in (
        'motm_open',
        'motm_result_general',
        'motm_result_winner'
      );

    if not private.is_feature_enabled('notifications_paused') then
      insert into public.push_notification_log(match_id, kind, sent_at)
      values (new.match_id, 'motm_open', now())
      on conflict do nothing;
      if found then
        perform private.dispatch_motm_push('motm_open', new.match_id);
      end if;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."push_on_motm_election_opened"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."push_prediction_j5_notifications"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_sent integer := 0;
begin
  if private.is_feature_enabled('notifications_paused') then
    return 0;
  end if;

  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and m.kickoff_at is not null
      and now() >= private.match_prediction_notification_at(m.kickoff_at)
      and now() < private.match_prediction_closes_at(m.kickoff_at)
      and (m.predictions_closed_at is null or now() < m.predictions_closed_at)
    order by m.kickoff_at
  loop
    insert into public.push_notification_log(match_id, kind, sent_at)
    values (v_match.id, 'prediction_j5', now())
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('prediction_j5', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;


ALTER FUNCTION "public"."push_prediction_j5_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalculate_all_badges"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  r record;
begin
  for r in select id from public.profiles loop
    perform public.recalculate_profile_badges(r.id);
  end loop;
end;
$$;


ALTER FUNCTION "public"."recalculate_all_badges"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalculate_profile_badges"("p_profile_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v jsonb;
  b record;
  val integer;
begin
  if p_profile_id is null then
    return;
  end if;
  select to_jsonb(t) into v from public.profile_badge_metrics(p_profile_id) t;
  if v is null then
    return;
  end if;
  for b in
    select id, metric, threshold from public.badges
    where auto and kind = 'tier' and metric is not null and threshold is not null
  loop
    val := coalesce((v ->> b.metric)::int, 0);
    if val >= b.threshold then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    else
      delete from public.profile_badges
      where profile_id = p_profile_id and badge_id = b.id and source = 'auto';
    end if;
  end loop;
end;
$$;


ALTER FUNCTION "public"."recalculate_profile_badges"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalculate_upcoming_match_odds_v4"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_count integer := 0;
begin
  for v_match in
    select id from public.matches where status = 'a_venir'
  loop
    perform public.upsert_match_odds_v4(v_match.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;


ALTER FUNCTION "public"."recalculate_upcoming_match_odds_v4"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_push_subscription"("p_endpoint" "text", "p_p256dh" "text", "p_auth" "text", "p_user_agent" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = actor_id
      and p.status = 'active'
  ) then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  if btrim(coalesce(p_endpoint, '')) = ''
     or btrim(coalesce(p_p256dh, '')) = ''
     or btrim(coalesce(p_auth, '')) = '' then
    raise exception 'Invalid push subscription' using errcode = '22023';
  end if;

  if length(p_endpoint) > 2048
     or length(p_p256dh) > 512
     or length(p_auth) > 512
     or length(coalesce(p_user_agent, '')) > 512 then
    raise exception 'Push subscription fields are too long' using errcode = '22001';
  end if;

  insert into public.push_subscriptions(
    profile_id,
    endpoint,
    p256dh,
    auth,
    user_agent
  )
  values (
    actor_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    p_user_agent
  )
  on conflict (endpoint) do update
  set profile_id = excluded.profile_id,
      p256dh = excluded.p256dh,
      auth = excluded.auth,
      user_agent = excluded.user_agent,
      updated_at = now();

  delete from public.push_subscriptions ps
  using (
    select id
    from (
      select
        id,
        row_number() over (order by updated_at desc, created_at desc, id desc) as rn
      from public.push_subscriptions
      where profile_id = actor_id
    ) ranked
    where rn > 5
  ) old
  where ps.id = old.id;
end;
$$;


ALTER FUNCTION "public"."register_push_subscription"("p_endpoint" "text", "p_p256dh" "text", "p_auth" "text", "p_user_agent" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor_id uuid := (select auth.uid());
  v_match public.matches%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Utilisateur non authentifié.' using errcode = '42501';
  end if;
  if not private.is_active_profile() then
    raise exception 'Compte inactif.' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match requis.' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta not between 0 and 99
     or p_score_adverse not between 0 and 99 then
    raise exception 'Les scores doivent être compris entre 0 et 99.' using errcode = '22023';
  end if;

  select * into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_features_open_at(v_match.kickoff_at)
     or now() >= private.match_prediction_closes_at(v_match.kickoff_at)
     or (v_match.predictions_closed_at is not null and now() >= v_match.predictions_closed_at) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.' using errcode = '22023';
  end if;

  insert into public.match_predictions (
    match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse,
    is_filled, updated_at
  ) values (
    p_match_id, v_actor_id, p_score_as_grinta, p_score_adverse, true, now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      updated_at = now();

  return true;
end;
$$;


ALTER FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_use_x2" boolean) RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select public.save_match_prediction(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse
  );
$$;


ALTER FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_use_x2" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.save_my_season_predictions(p_season_id, p_items);
$$;


ALTER FUNCTION "public"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seed_match_predictions"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.opponent_id is null then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select new.id, p.id, 0, 0, false
  from public.profiles p
  where p.status = 'active'
  on conflict (match_id, profile_id) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."seed_match_predictions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seed_predictions_for_active_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.status <> 'active' then
    return new;
  end if;

  insert into public.match_predictions (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled
  )
  select m.id, new.id, 0, 0, false
  from public.matches m
  where m.status = 'a_venir'
  on conflict (match_id, profile_id) do nothing;

  insert into public.season_predictions (
    season_id,
    predictor_profile_id,
    season_player_id,
    category,
    predicted_value_30,
    is_filled
  )
  select
    sp.season_id,
    new.id,
    sp.id,
    case when sp.is_goalkeeper then 'clean_sheets' else 'buts' end,
    0,
    false
  from public.season_players sp
  join public.seasons s
    on s.id = sp.season_id
   and s.status = 'open'
  where sp.is_active
  on conflict (
    season_id,
    predictor_profile_id,
    season_player_id,
    category
  ) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."seed_predictions_for_active_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."seed_season_predictions_for_player"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.season_predictions(
    season_id, predictor_profile_id, season_player_id, category,
    predicted_value_30, is_filled
  )
  select new.season_id, p.id, new.id,
    case when new.is_goalkeeper then 'clean_sheets' else 'buts' end, 0, false
  from public.profiles p
  where p.status = 'active'
  on conflict(season_id, predictor_profile_id, season_player_id, category)
    do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."seed_season_predictions_for_player"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_test_push"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'push_internal_token';

  if v_token is null then
    raise exception 'Notifications push non configurées';
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'test',
      'profile_ids', jsonb_build_array(v_actor)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );
end;
$$;


ALTER FUNCTION "public"."send_test_push"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."send_test_push"() IS 'Sends a test push notification to the calling user only; open to every authenticated player.';



CREATE OR REPLACE FUNCTION "public"."set_badge_featured"("p_badge_code" "text", "p_featured" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_badge uuid;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Connexion requise.' using errcode = '42501';
  end if;
  select id into v_badge from public.badges where code = p_badge_code;
  if v_badge is null then
    raise exception 'Badge introuvable.' using errcode = '22023';
  end if;
  if p_featured then
    select count(*) into v_count from public.profile_badges
    where profile_id = v_uid and featured and badge_id <> v_badge;
    if v_count >= 2 then
      raise exception 'Tu peux arborer 2 badges maximum.' using errcode = '23514';
    end if;
  end if;
  update public.profile_badges set featured = p_featured
  where profile_id = v_uid and badge_id = v_badge;
  if not found then
    raise exception 'Tu ne possèdes pas ce badge.' using errcode = '42501';
  end if;
end;
$$;


ALTER FUNCTION "public"."set_badge_featured"("p_badge_code" "text", "p_featured" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_match_odds"("p_match_id" "uuid", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.status = 'a_venir'
  ) then
    raise exception 'Upcoming match not found' using errcode = 'P0002';
  end if;
  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul,
    odds_victoire_adverse, computed_at
  ) values (
    p_match_id, round(p_win, 2), round(p_draw, 2), round(p_loss, 2), now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();
  return true;
end;
$$;


ALTER FUNCTION "public"."set_match_odds"("p_match_id" "uuid", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.set_my_match_availability(p_match_id, p_status, p_private_comment);
$$;


ALTER FUNCTION "public"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") IS 'Records the signed-in eligible player availability during the server-enforced window.';



CREATE OR REPLACE FUNCTION "public"."set_season_predictions_lock"("p_season_id" "uuid", "p_locked" boolean) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_locked is null then
    raise exception 'Season id and lock value are required' using errcode = '22023';
  end if;
  update public.seasons
  set season_predictions_locked_at = case when p_locked then now() else null end
  where id = p_season_id and status = 'open';
  if not found then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;


ALTER FUNCTION "public"."set_season_predictions_lock"("p_season_id" "uuid", "p_locked" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_season_status"("p_season_id" "uuid", "p_status" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null then
    raise exception 'Season id is required' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('open', 'terminee', 'archived') then
    raise exception 'Statut de saison invalide' using errcode = '22023';
  end if;
  perform 1 from public.seasons where id = p_season_id for update;
  if not found then
    raise exception 'Season not found' using errcode = 'P0002';
  end if;
  if p_status = 'open' then
    update public.seasons set status = 'archived' where status = 'open' and id <> p_season_id;
  end if;
  update public.seasons set status = p_status where id = p_season_id;
  return true;
end;
$$;


ALTER FUNCTION "public"."set_season_status"("p_season_id" "uuid", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.set_sports_management_enabled(p_enabled, p_justification);
$$;


ALTER FUNCTION "public"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") IS 'Admin-only toggle for the optional sports-management module, with audit.';



CREATE OR REPLACE FUNCTION "public"."staff_app_integrity_report"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_checks jsonb;
  v_total bigint;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  with checks as (
    select 'matches_without_odds'::text as check_name, count(*)::bigint as issue_count
    from public.matches m
    left join public.match_odds mo on mo.match_id = m.id
    where m.match_type <> 'entre_nous'
      and mo.match_id is null

    union all

    select 'finished_without_scores', count(*)::bigint
    from public.matches
    where status in ('termine', 'archive')
      and (score_as_grinta is null or score_adverse is null)

    union all

    select 'upcoming_with_scores', count(*)::bigint
    from public.matches
    where status = 'a_venir'
      and (score_as_grinta is not null or score_adverse is not null)

    union all

    select 'duplicate_match_datetime', count(*)::bigint
    from (
      select match_date, match_time
      from public.matches
      group by match_date, match_time
      having count(*) > 1
    ) duplicates

    union all

    select 'multiple_open_seasons', greatest(count(*) - 1, 0)::bigint
    from public.seasons
    where status = 'open'

    union all

    select 'orphan_match_predictions', count(*)::bigint
    from public.match_predictions mp
    left join public.matches m on m.id = mp.match_id
    left join public.profiles p on p.id = mp.profile_id
    where m.id is null or p.id is null

    union all

    select 'filled_predictions_missing_scores', count(*)::bigint
    from public.match_predictions
    where is_filled
      and (
        predicted_score_as_grinta is null
        or predicted_score_adverse is null
      )

    union all

    select 'missing_upcoming_prediction_seeds', count(*)::bigint
    from public.matches m
    cross join public.profiles p
    left join public.match_predictions mp
      on mp.match_id = m.id
     and mp.profile_id = p.id
    where m.status = 'a_venir'
      and m.match_type <> 'entre_nous'
      and p.status = 'active'
      and mp.id is null

    union all

    select 'missing_open_season_prediction_seeds', count(*)::bigint
    from public.seasons s
    join public.season_players sp
      on sp.season_id = s.id
     and sp.is_active
    cross join public.profiles p
    left join public.season_predictions prediction
      on prediction.season_id = s.id
     and prediction.predictor_profile_id = p.id
     and prediction.season_player_id = sp.id
     and prediction.category = case
       when sp.is_goalkeeper then 'clean_sheets'
       else 'buts'
     end
    where s.status = 'open'
      and p.status = 'active'
      and prediction.id is null

    union all

    select 'kickoff_mismatch', count(*)::bigint
    from public.matches m
    where m.match_time is not null
      and m.kickoff_at is distinct from
        ((m.match_date + m.match_time) at time zone 'Europe/Paris')
  ), aggregated as (
    select
      coalesce(sum(issue_count), 0)::bigint as total_issues,
      jsonb_agg(
        jsonb_build_object(
          'check', check_name,
          'issues', issue_count
        )
        order by check_name
      ) as checks
    from checks
  )
  select total_issues, checks
  into v_total, v_checks
  from aggregated;

  return jsonb_build_object(
    'healthy', v_total = 0,
    'total_issues', v_total,
    'checked_at', now(),
    'checks', coalesce(v_checks, '[]'::jsonb)
  );
end;
$$;


ALTER FUNCTION "public"."staff_app_integrity_report"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_award_badge"("p_profile_id" "uuid", "p_badge_code" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_badge_id uuid;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;
  select id into v_badge_id from public.badges where code = p_badge_code;
  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id) then
    raise exception 'Unknown profile' using errcode = '22023';
  end if;
  insert into public.profile_badges(profile_id, badge_id, source, awarded_by)
  values (p_profile_id, v_badge_id, 'manual', auth.uid())
  on conflict (profile_id, badge_id)
  do update set source = 'manual', awarded_by = auth.uid(), awarded_at = now();
  return true;
end;
$$;


ALTER FUNCTION "public"."staff_award_badge"("p_profile_id" "uuid", "p_badge_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_create_badge"("p_code" "text", "p_name" "text", "p_emoji" "text" DEFAULT '🏅'::"text", "p_description" "text" DEFAULT ''::"text", "p_image_url" "text" DEFAULT NULL::"text", "p_color" "text" DEFAULT '#C0455B'::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;
  if p_code is null or p_code = '' or p_name is null or p_name = '' then
    raise exception 'code and name are required' using errcode = '22023';
  end if;
  insert into public.badges(code, name, description, emoji, image_url, color,
                            family, auto, kind, category, metric, threshold, sort_order)
  values (p_code, p_name, coalesce(p_description, ''),
          coalesce(nullif(p_emoji, ''), '🏅'), p_image_url,
          coalesce(nullif(p_color, ''), '#C0455B'),
          'joueur', false, 'custom', 'faits_de_jeu', null, null, 900)
  on conflict (code) do update
    set name = excluded.name, emoji = excluded.emoji,
        description = excluded.description, image_url = excluded.image_url,
        color = excluded.color;
  return true;
end;
$$;


ALTER FUNCTION "public"."staff_create_badge"("p_code" "text", "p_name" "text", "p_emoji" "text", "p_description" "text", "p_image_url" "text", "p_color" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_list_historical_players"() RETURNS TABLE("id" bigint, "player_name" "text", "is_goalkeeper" boolean, "matches_played" integer, "goals" integer, "profile_id" "uuid")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select h.id, h.player_name, h.is_goalkeeper,
         h.matches_played, h.goals, h.profile_id
  from public.historical_player_statistics h
  where h.scope = 'all_time'
    and public.is_match_staff()
  order by lower(btrim(h.player_name));
$$;


ALTER FUNCTION "public"."staff_list_historical_players"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_list_profiles"() RETURNS TABLE("id" "uuid", "first_name" "text", "last_name" "text", "surnom" "text", "username" "text", "password_set" boolean, "photo_url" "text", "role" "text", "is_goalkeeper" boolean, "status" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  return query
  select p.id, p.first_name, p.last_name, p.surnom, p.username,
         p.password_set, p.photo_url, p.role, p.is_goalkeeper,
         p.status, p.created_at, p.updated_at
  from public.profiles p
  where p.id <> '00000000-0000-0000-0000-000000000001'::uuid
  order by p.first_name, p.last_name;
end;
$$;


ALTER FUNCTION "public"."staff_list_profiles"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_profile_username"("p_profile_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare result text;
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
  select p.username into result from public.profiles p where p.id = p_profile_id;
  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;
  return result;
end;
$$;


ALTER FUNCTION "public"."staff_profile_username"("p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_revoke_badge"("p_profile_id" "uuid", "p_badge_code" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_badge_id uuid;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;
  select id into v_badge_id from public.badges where code = p_badge_code;
  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;
  delete from public.profile_badges
  where profile_id = p_profile_id and badge_id = v_badge_id;
  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$$;


ALTER FUNCTION "public"."staff_revoke_badge"("p_profile_id" "uuid", "p_badge_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_set_historical_profile"("p_profile_id" "uuid", "p_historical_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_name text;
  v_source_player_id uuid;
  v_target_player_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;

  select p.player_id
  into v_target_player_id
  from public.profiles p
  where p.id = p_profile_id
    and coalesce(p.email, '') <> 'historique@as-grinta.invalid'
  for update;

  if not found or v_target_player_id is null then
    raise exception 'Profile not found or protected technical account'
      using errcode = 'P0002';
  end if;

  update public.historical_player_statistics
  set profile_id = null, updated_at = now()
  where profile_id = p_profile_id;

  if p_historical_id is not null then
    select h.player_name, h.player_id
    into v_name, v_source_player_id
    from public.historical_player_statistics h
    where h.id = p_historical_id
    for update;

    if not found then
      raise exception 'Historical record not found' using errcode = 'P0002';
    end if;

    perform private.merge_player_identities(
      v_source_player_id,
      v_target_player_id
    );

    update public.historical_player_statistics h
    set profile_id = p_profile_id,
        player_id = v_target_player_id,
        updated_at = now()
    where h.player_id = v_target_player_id
      and private.normalize_player_name(h.player_name)
        = private.normalize_player_name(v_name);
  end if;

  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$$;


ALTER FUNCTION "public"."staff_set_historical_profile"("p_profile_id" "uuid", "p_historical_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_set_match_attendance"("p_match_id" "uuid", "p_present" "uuid"[]) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_player uuid;
  v_profiles uuid[];
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select season_id into v_season_id from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select array_agg(distinct sp.profile_id)
  into v_profiles
  from public.match_attendance ma
  join public.season_players sp on sp.id = ma.season_player_id
  where ma.match_id = p_match_id and sp.profile_id is not null;

  delete from public.match_attendance where match_id = p_match_id;

  if p_present is not null then
    foreach v_player in array p_present loop
      if not exists (
        select 1 from public.season_players sp
        where sp.id = v_player and sp.season_id = v_season_id and sp.is_active
      ) then
        raise exception 'Player is not active in the match season' using errcode = '22023';
      end if;
      insert into public.match_attendance(match_id, season_player_id)
      values (p_match_id, v_player)
      on conflict do nothing;
    end loop;
  end if;

  select array_cat(coalesce(v_profiles, '{}'), coalesce(array_agg(distinct sp.profile_id), '{}'))
  into v_profiles
  from public.season_players sp
  where sp.id = any (coalesce(p_present, '{}')) and sp.profile_id is not null;

  if v_profiles is not null then
    foreach v_player in array v_profiles loop
      perform public.recalculate_profile_badges(v_player);
    end loop;
  end if;

  return true;
end;
$$;


ALTER FUNCTION "public"."staff_set_match_attendance"("p_match_id" "uuid", "p_present" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_set_match_mvp"("p_match_id" "uuid", "p_players" "uuid"[]) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_player uuid;
  v_profiles uuid[];
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select season_id into v_season_id from public.matches where id = p_match_id;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  select array_agg(distinct sp.profile_id)
  into v_profiles
  from public.match_man_of_match mvp
  join public.season_players sp on sp.id = mvp.season_player_id
  where mvp.match_id = p_match_id and sp.profile_id is not null;

  delete from public.match_man_of_match where match_id = p_match_id;

  if p_players is not null then
    foreach v_player in array p_players loop
      if not exists (
        select 1 from public.season_players sp
        where sp.id = v_player and sp.season_id = v_season_id and sp.is_active
      ) then
        raise exception 'Player is not active in the match season' using errcode = '22023';
      end if;
      insert into public.match_man_of_match(match_id, season_player_id)
      values (p_match_id, v_player)
      on conflict do nothing;
    end loop;
  end if;

  select array_cat(coalesce(v_profiles, '{}'), coalesce(array_agg(distinct sp.profile_id), '{}'))
  into v_profiles
  from public.season_players sp
  where sp.id = any (coalesce(p_players, '{}')) and sp.profile_id is not null;

  if v_profiles is not null then
    foreach v_player in array v_profiles loop
      perform public.recalculate_profile_badges(v_player);
    end loop;
  end if;

  return true;
end;
$$;


ALTER FUNCTION "public"."staff_set_match_mvp"("p_match_id" "uuid", "p_players" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_set_season_player_profile"("p_season_player_id" "uuid", "p_profile_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_source_player_id uuid;
  v_target_player_id uuid;
  v_profile_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_season_player_id is null then
    raise exception 'Season player id is required' using errcode = '22023';
  end if;

  select sp.season_id, sp.player_id
  into v_season_id, v_source_player_id
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

  select p.status, p.player_id
  into v_profile_status, v_target_player_id
  from public.profiles p
  where p.id = p_profile_id
    and coalesce(p.email, '') <> 'historique@as-grinta.invalid'
  for update;

  if not found then
    raise exception 'Profile not found or protected technical account'
      using errcode = 'P0002';
  end if;

  if v_profile_status <> 'active' then
    raise exception 'Only an active profile can be linked' using errcode = '23514';
  end if;

  if v_target_player_id is null then
    raise exception 'Profile has no canonical player identity' using errcode = '23514';
  end if;

  update public.season_players
  set profile_id = null
  where season_id = v_season_id
    and profile_id = p_profile_id
    and id <> p_season_player_id;

  perform private.merge_player_identities(
    v_source_player_id,
    v_target_player_id
  );

  update public.season_players
  set profile_id = p_profile_id,
      player_id = v_target_player_id
  where id = p_season_player_id;

  return true;
end;
$$;


ALTER FUNCTION "public"."staff_set_season_player_profile"("p_season_player_id" "uuid", "p_profile_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."staff_validate_profile"("p_profile_id" "uuid", "p_season_player_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."staff_validate_profile"("p_profile_id" "uuid", "p_season_player_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_match_kickoff_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.kickoff_at := case
    when new.match_time is null then null
    else (new.match_date + new.match_time) at time zone 'Europe/Paris'
  end;
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_match_kickoff_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_award_titles_on_season_close"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.status = 'archived' and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    perform public.award_season_titles(new.id);
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_award_titles_on_season_close"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_attendance"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_profile uuid;
begin
  select sp.profile_id into v_profile
  from public.season_players sp
  where sp.id = coalesce(new.season_player_id, old.season_player_id);
  if v_profile is not null then
    perform public.recalculate_profile_badges(v_profile);
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_attendance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_historical_link"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;
  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_historical_link"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_match_result"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.status in ('termine', 'archive')
     and (tg_op = 'INSERT' or new.status is distinct from old.status
          or new.score_as_grinta is distinct from old.score_as_grinta
          or new.score_adverse is distinct from old.score_adverse) then
    perform public.recalculate_all_badges();
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_match_result"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_mvp"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_profile uuid;
begin
  select sp.profile_id into v_profile
  from public.season_players sp
  where sp.id = coalesce(new.season_player_id, old.season_player_id);
  if v_profile is not null then
    perform public.recalculate_profile_badges(v_profile);
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_mvp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_player_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_profile uuid;
begin
  select sp.profile_id into v_profile
  from public.season_players sp
  where sp.id = coalesce(new.season_player_id, old.season_player_id);
  if v_profile is not null then
    perform public.recalculate_profile_badges(v_profile);
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_player_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_prediction"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.recalculate_profile_badges(new.profile_id);
  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_prediction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_badges_on_roster_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;

  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id
     and pg_trigger_depth() <= 1 then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;

  return null;
end;
$$;


ALTER FUNCTION "public"."trg_badges_on_roster_change"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."trg_badges_on_roster_change"() IS 'Recalcule les badges lors des modifications directes de l effectif, mais ignore le profil source pendant une mise a null declenchee en cascade par la suppression du compte.';



CREATE OR REPLACE FUNCTION "public"."trigger_match_odds_v4"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'a_venir' then
      perform public.upsert_match_odds_v4(new.id);
    end if;
  elsif new.status = 'a_venir' and (
    old.opponent_id is distinct from new.opponent_id
    or old.location is distinct from new.location
    or old.status is distinct from new.status
  ) then
    perform public.upsert_match_odds_v4(new.id);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."trigger_match_odds_v4"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_recalculate_upcoming_odds_v3"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if new.status in ('termine', 'archive')
     and new.score_as_grinta is not null
     and new.score_adverse is not null
     and (
       old.status is distinct from new.status
       or old.score_as_grinta is distinct from new.score_as_grinta
       or old.score_adverse is distinct from new.score_adverse
     ) then
    perform public.recalculate_upcoming_match_odds_v4();
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."trigger_recalculate_upcoming_odds_v3"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_internal_match"("p_match_id" "uuid", "p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, date et heure requis.' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;

  select m.status
  into v_status
  from public.matches m
  where m.id = p_match_id
    and m.match_type = 'entre_nous'
  for update;

  if v_status is null then
    raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      match_date = p_match_date,
      match_time = p_match_time,
      updated_at = now()
  where id = p_match_id;

  if v_status = 'a_venir' then
    perform private.configure_match_sport_workflow(p_match_id, 30);
  end if;

  return true;
end;
$$;


ALTER FUNCTION "public"."update_internal_match"("p_match_id" "uuid", "p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_match_with_odds"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_opponent_id is null
     or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, adversaire, date et heure requis.'
      using errcode = '22023';
  end if;
  if p_location not in ('domicile', 'exterieur') then
    raise exception 'Lieu invalide.' using errcode = '22023';
  end if;
  if p_status is distinct from 'a_venir' then
    raise exception 'Le statut se modifie via le workflow dédié du match.'
      using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Adversaire introuvable.' using errcode = 'P0002';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Cotes invalides.' using errcode = '22023';
  end if;

  select m.id into v_match_id
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_id is null then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      opponent_id = p_opponent_id,
      match_date = p_match_date,
      match_time = p_match_time,
      location = p_location,
      status = 'a_venir',
      updated_at = now()
  where id = p_match_id;

  insert into public.match_odds (
    match_id,
    odds_victoire_as_grinta,
    odds_nul,
    odds_victoire_adverse,
    computed_at
  ) values (
    p_match_id,
    round(p_win, 2),
    round(p_draw, 2),
    round(p_loss, 2),
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();

  return true;
end;
$$;


ALTER FUNCTION "public"."update_match_with_odds"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_match_with_odds"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) IS 'Legacy edit RPC: edits upcoming match identity and odds only; lifecycle status transitions use dedicated workflows.';



CREATE OR REPLACE FUNCTION "public"."update_match_with_odds_and_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) RETURNS boolean
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  select private.update_match_with_sport_limit(
    p_match_id, p_season_id, p_opponent_id, p_match_date, p_match_time,
    p_location, p_status, p_win, p_draw, p_loss, p_squad_size_limit
  );
$$;


ALTER FUNCTION "public"."update_match_with_odds_and_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_app_preferences"("p_notify_prediction_open" boolean, "p_notify_prediction_reminders" boolean, "p_notify_match_reminders" boolean) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set notify_prediction_open =
        coalesce(p_notify_prediction_open, notify_prediction_open),
      notify_prediction_reminders =
        coalesce(p_notify_prediction_reminders, notify_prediction_reminders),
      notify_match_reminders =
        coalesce(p_notify_match_reminders, notify_match_reminders),
      updated_at = now()
  where id = actor_id
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;

  return true;
end;
$$;


ALTER FUNCTION "public"."update_my_app_preferences"("p_notify_prediction_open" boolean, "p_notify_prediction_reminders" boolean, "p_notify_match_reminders" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_my_notification_preferences"("p_notify_prediction" boolean, "p_notify_motm_vote" boolean, "p_notify_convocation" boolean) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set notify_prediction_reminders = coalesce(p_notify_prediction, notify_prediction_reminders),
      notify_motm_vote = coalesce(p_notify_motm_vote, notify_motm_vote),
      notify_convocation = coalesce(p_notify_convocation, notify_convocation),
      updated_at = now()
  where id = v_actor
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;
  return true;
end;
$$;


ALTER FUNCTION "public"."update_my_notification_preferences"("p_notify_prediction" boolean, "p_notify_motm_vote" boolean, "p_notify_convocation" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_match_odds_v4"("p_match_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_match record;
  v_result jsonb;
begin
  select id, opponent_id, match_date, status
  into v_match
  from public.matches
  where id = p_match_id;

  if not found or v_match.status <> 'a_venir' or v_match.opponent_id is null then
    return;
  end if;

  v_result := public.calculate_match_odds_v5(v_match.opponent_id, v_match.match_date);

  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul, odds_victoire_adverse,
    probability_win, probability_draw, probability_loss,
    model_version, computed_at
  ) values (
    v_match.id,
    (v_result->>'win')::numeric,
    (v_result->>'draw')::numeric,
    (v_result->>'loss')::numeric,
    (v_result->>'probability_win')::numeric,
    (v_result->>'probability_draw')::numeric,
    (v_result->>'probability_loss')::numeric,
    v_result->>'model_version',
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      probability_win = excluded.probability_win,
      probability_draw = excluded.probability_draw,
      probability_loss = excluded.probability_loss,
      expected_goals_as_grinta = null,
      expected_goals_adverse = null,
      confidence = null,
      model_version = excluded.model_version,
      computed_at = excluded.computed_at;
end;
$$;


ALTER FUNCTION "public"."upsert_match_odds_v4"("p_match_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_profile_names"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_valid_person_name(new.first_name) then
    raise exception 'Le prénom ne doit contenir que des lettres (ni emoji, ni chiffre, ni symbole).'
      using errcode = '23514';
  end if;
  if not public.is_valid_person_name(new.last_name) then
    raise exception 'Le nom ne doit contenir que des lettres (ni emoji, ni chiffre, ni symbole).'
      using errcode = '23514';
  end if;
  if not public.is_valid_person_name(new.surnom) then
    raise exception 'Le surnom ne doit contenir que des lettres (ni emoji, ni chiffre, ni symbole).'
      using errcode = '23514';
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."validate_profile_names"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_season_prediction_row"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_player_season_id uuid;
  v_is_goalkeeper boolean;
  v_is_active boolean;
  v_max_value integer;
begin
  select sp.season_id, sp.is_goalkeeper, sp.is_active
  into v_player_season_id, v_is_goalkeeper, v_is_active
  from public.season_players sp
  where sp.id = new.season_player_id;

  if not found then
    raise exception 'Joueur de saison introuvable.' using errcode = '23503';
  end if;

  if v_player_season_id <> new.season_id then
    raise exception 'Le joueur n’appartient pas à cette saison.' using errcode = '23514';
  end if;

  if not v_is_active then
    raise exception 'Ce joueur n’est plus actif pour cette saison.' using errcode = '23514';
  end if;

  if v_is_goalkeeper and new.category <> 'clean_sheets' then
    raise exception 'Un gardien doit être pronostiqué en clean sheets.' using errcode = '23514';
  end if;

  if not v_is_goalkeeper and new.category <> 'buts' then
    raise exception 'Un joueur de champ doit être pronostiqué en buts.' using errcode = '23514';
  end if;

  v_max_value := case when v_is_goalkeeper then 30 else 99 end;
  if new.predicted_value_30 < 0 or new.predicted_value_30 > v_max_value then
    raise exception 'Valeur de pronostic hors limites.' using errcode = '22003';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."validate_season_prediction_row"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "private"."app_feature_flag_audit" (
    "id" bigint NOT NULL,
    "feature_key" "text" NOT NULL,
    "old_enabled" boolean NOT NULL,
    "new_enabled" boolean NOT NULL,
    "actor_profile_id" "uuid",
    "justification" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "app_feature_flag_audit_justification_length" CHECK ((("justification" IS NULL) OR ("char_length"("justification") <= 500))),
    CONSTRAINT "app_feature_flag_audit_real_transition" CHECK (("old_enabled" IS DISTINCT FROM "new_enabled"))
);


ALTER TABLE "private"."app_feature_flag_audit" OWNER TO "postgres";


COMMENT ON TABLE "private"."app_feature_flag_audit" IS 'Append-only audit trail for feature-flag state transitions.';



ALTER TABLE "private"."app_feature_flag_audit" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "private"."app_feature_flag_audit_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "private"."app_feature_flags" (
    "key" "text" NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    "config" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    CONSTRAINT "app_feature_flags_config_object" CHECK (("jsonb_typeof"("config") = 'object'::"text")),
    CONSTRAINT "app_feature_flags_key_format" CHECK (("key" ~ '^[a-z][a-z0-9_]*$'::"text"))
);


ALTER TABLE "private"."app_feature_flags" OWNER TO "postgres";


COMMENT ON TABLE "private"."app_feature_flags" IS 'Server-side feature flags. This schema is not exposed through the Data API.';



COMMENT ON COLUMN "private"."app_feature_flags"."enabled" IS 'Authoritative server value. Flutter caches this value for presentation only.';



CREATE TABLE IF NOT EXISTS "private"."prediction_reminder_cron_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "secret_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prediction_reminder_cron_config_singleton_check" CHECK ("singleton")
);


ALTER TABLE "private"."prediction_reminder_cron_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."registration_attempts" (
    "id" bigint NOT NULL,
    "origin_hash" "text" NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "registration_attempts_origin_hash_check" CHECK (("origin_hash" ~ '^[0-9a-f]{64}$'::"text"))
);


ALTER TABLE "private"."registration_attempts" OWNER TO "postgres";


ALTER TABLE "private"."registration_attempts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "private"."registration_attempts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "private"."sport_admin_audit_log" (
    "id" bigint NOT NULL,
    "match_id" "uuid",
    "action" "text" NOT NULL,
    "actor_profile_id" "uuid" NOT NULL,
    "reason" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sport_admin_audit_log_action_check" CHECK ((("action" ~ '^[a-z][a-z0-9_]*$'::"text") AND ("char_length"("action") <= 96))),
    CONSTRAINT "sport_admin_audit_log_metadata_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "sport_admin_audit_log_reason_check" CHECK ((("reason" IS NULL) OR ("char_length"("reason") <= 500)))
);


ALTER TABLE "private"."sport_admin_audit_log" OWNER TO "postgres";


COMMENT ON TABLE "private"."sport_admin_audit_log" IS 'Private append-only audit trail for privileged sports-management actions.';



ALTER TABLE "private"."sport_admin_audit_log" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "private"."sport_admin_audit_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."badge_inbox_state" (
    "profile_id" "uuid" NOT NULL,
    "seen_through" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."badge_inbox_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."badges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "emoji" "text" NOT NULL,
    "family" "text" NOT NULL,
    "auto" boolean DEFAULT true NOT NULL,
    "metric" "text",
    "threshold" integer,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "kind" "text" DEFAULT 'tier'::"text" NOT NULL,
    "category" "text" DEFAULT 'all_time'::"text" NOT NULL,
    "image_url" "text",
    "color" "text",
    "has_star" boolean DEFAULT false NOT NULL,
    "standalone" boolean DEFAULT false NOT NULL,
    "secret" boolean DEFAULT false NOT NULL,
    CONSTRAINT "badges_family_check" CHECK (("family" = ANY (ARRAY['joueur'::"text", 'pronostiqueur'::"text"])))
);


ALTER TABLE "public"."badges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."club_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "location" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "club_events_location_length" CHECK ((("char_length"("btrim"("location")) >= 1) AND ("char_length"("btrim"("location")) <= 300))),
    CONSTRAINT "club_events_title_length" CHECK ((("char_length"("btrim"("title")) >= 1) AND ("char_length"("btrim"("title")) <= 120)))
);


ALTER TABLE "public"."club_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."club_settings" (
    "id" boolean DEFAULT true NOT NULL,
    "home_address" "text",
    CONSTRAINT "club_settings_singleton" CHECK ("id")
);


ALTER TABLE "public"."club_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feature_flag_change_signals" (
    "key" "text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "feature_flag_change_signals_key_format" CHECK (("key" ~ '^[a-z][a-z0-9_]*$'::"text")),
    CONSTRAINT "feature_flag_change_signals_revision_positive" CHECK (("revision" > 0))
);


ALTER TABLE "public"."feature_flag_change_signals" OWNER TO "postgres";


COMMENT ON TABLE "public"."feature_flag_change_signals" IS 'Public-safe Realtime signal. Clients refresh authoritative feature flags through RPC.';



CREATE TABLE IF NOT EXISTS "public"."guest_players" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text",
    "is_goalkeeper" boolean DEFAULT false NOT NULL,
    "is_reusable" boolean DEFAULT true NOT NULL,
    "archived_at" timestamp with time zone,
    "created_by" "uuid" NOT NULL,
    "updated_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "photo_url" "text",
    "player_id" "uuid" NOT NULL,
    CONSTRAINT "guest_players_check" CHECK ((("is_reusable" AND ("archived_at" IS NULL)) OR ((NOT "is_reusable") AND ("archived_at" IS NOT NULL)))),
    CONSTRAINT "guest_players_first_name_check" CHECK ((("char_length"("btrim"("first_name")) >= 1) AND ("char_length"("btrim"("first_name")) <= 80))),
    CONSTRAINT "guest_players_last_name_check" CHECK ((("last_name" IS NULL) OR (("char_length"("btrim"("last_name")) >= 1) AND ("char_length"("btrim"("last_name")) <= 80))))
);


ALTER TABLE "public"."guest_players" OWNER TO "postgres";


COMMENT ON TABLE "public"."guest_players" IS 'Reusable guest catalog. Archiving never removes historical match references.';



COMMENT ON COLUMN "public"."guest_players"."is_goalkeeper" IS 'Used by composition warnings and later final attendance/statistics workflows.';



CREATE TABLE IF NOT EXISTS "public"."historical_match_details" (
    "match_id" "uuid" NOT NULL,
    "formation" "text",
    "field_players" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "bench_players" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "present_names" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "scorers" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "motm_names" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL
);


ALTER TABLE "public"."historical_match_details" OWNER TO "postgres";


COMMENT ON TABLE "public"."historical_match_details" IS 'Composition (facultative), buteurs et HDM importés par match historique ; lecture uniquement via get_historical_match_detail.';



CREATE TABLE IF NOT EXISTS "public"."historical_match_players" (
    "match_id" "uuid" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "source_name" "text" NOT NULL,
    "is_present" boolean DEFAULT false NOT NULL,
    "is_starter" boolean DEFAULT false NOT NULL,
    "is_bench" boolean DEFAULT false NOT NULL,
    "is_motm" boolean DEFAULT false NOT NULL,
    "goals" integer DEFAULT 0 NOT NULL,
    "is_goalkeeper" boolean,
    "x_pct" numeric,
    "y_pct" numeric,
    "position_code" "text",
    "position_label" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "historical_match_players_goals_check" CHECK (("goals" >= 0))
);


ALTER TABLE "public"."historical_match_players" OWNER TO "postgres";


COMMENT ON TABLE "public"."historical_match_players" IS 'Projection normalisée des joueurs des matchs importés, reliée à l''identité canonique. Les JSON historiques restent conservés pour compatibilité.';



CREATE TABLE IF NOT EXISTS "public"."historical_match_scores" (
    "id" "uuid" NOT NULL,
    "opponent_id" "uuid" NOT NULL,
    "match_date" "date" NOT NULL,
    "score_as_grinta" smallint NOT NULL,
    "score_adverse" smallint NOT NULL,
    "is_home" boolean DEFAULT true NOT NULL,
    CONSTRAINT "historical_match_scores_score_adverse_check" CHECK ((("score_adverse" >= 0) AND ("score_adverse" <= 99))),
    CONSTRAINT "historical_match_scores_score_as_grinta_check" CHECK ((("score_as_grinta" >= 0) AND ("score_as_grinta" <= 99)))
);


ALTER TABLE "public"."historical_match_scores" OWNER TO "postgres";


COMMENT ON TABLE "public"."historical_match_scores" IS 'Minimal historical results retained only for chronological opponent form and odds calculations.';



COMMENT ON COLUMN "public"."historical_match_scores"."is_home" IS 'true si AS Grinta recevait ; false si le match se jouait à l''extérieur.';



CREATE TABLE IF NOT EXISTS "public"."historical_player_name_links" (
    "normalized_name" "text" NOT NULL,
    "source_name" "text" NOT NULL,
    "player_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "historical_player_name_links_normalized_name_check" CHECK (("btrim"("normalized_name") <> ''::"text")),
    CONSTRAINT "historical_player_name_links_source_name_check" CHECK (("btrim"("source_name") <> ''::"text"))
);


ALTER TABLE "public"."historical_player_name_links" OWNER TO "postgres";


COMMENT ON TABLE "public"."historical_player_name_links" IS 'Résolution durable d''un libellé de joueur des archives vers son identité canonique. Les libellés ambigus peuvent pointer vers une identité d''archive distincte plutôt que d''être fusionnés arbitrairement.';



CREATE TABLE IF NOT EXISTS "public"."historical_player_statistics" (
    "id" bigint NOT NULL,
    "scope" "text" NOT NULL,
    "season_name" "text",
    "display_rank" integer NOT NULL,
    "player_name" "text" NOT NULL,
    "is_goalkeeper" boolean DEFAULT false NOT NULL,
    "matches_played" integer NOT NULL,
    "wins" integer NOT NULL,
    "draws" integer NOT NULL,
    "losses" integer NOT NULL,
    "goals" integer DEFAULT 0 NOT NULL,
    "hdm" integer DEFAULT 0 NOT NULL,
    "clean_sheets" integer,
    "source_label" "text" DEFAULT 'classements_joueurs_et_gardien_corriges'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "profile_id" "uuid",
    "team_clean_sheets" integer DEFAULT 0 NOT NULL,
    "player_id" "uuid" NOT NULL,
    CONSTRAINT "historical_player_statistics_check" CHECK (((("scope" = 'previous'::"text") AND ("season_name" IS NOT NULL)) OR (("scope" = 'all_time'::"text") AND ("season_name" IS NULL)))),
    CONSTRAINT "historical_player_statistics_clean_sheets_check" CHECK ((("clean_sheets" IS NULL) OR ("clean_sheets" >= 0))),
    CONSTRAINT "historical_player_statistics_display_rank_check" CHECK (("display_rank" > 0)),
    CONSTRAINT "historical_player_statistics_draws_check" CHECK (("draws" >= 0)),
    CONSTRAINT "historical_player_statistics_goals_check" CHECK (("goals" >= 0)),
    CONSTRAINT "historical_player_statistics_hdm_check" CHECK (("hdm" >= 0)),
    CONSTRAINT "historical_player_statistics_losses_check" CHECK (("losses" >= 0)),
    CONSTRAINT "historical_player_statistics_matches_played_check" CHECK (("matches_played" >= 0)),
    CONSTRAINT "historical_player_statistics_player_name_check" CHECK ((NULLIF("btrim"("player_name"), ''::"text") IS NOT NULL)),
    CONSTRAINT "historical_player_statistics_scope_check" CHECK (("scope" = ANY (ARRAY['previous'::"text", 'all_time'::"text"]))),
    CONSTRAINT "historical_player_statistics_team_clean_sheets_check" CHECK (("team_clean_sheets" >= 0)),
    CONSTRAINT "historical_player_statistics_wins_check" CHECK (("wins" >= 0))
);


ALTER TABLE "public"."historical_player_statistics" OWNER TO "postgres";


COMMENT ON COLUMN "public"."historical_player_statistics"."team_clean_sheets" IS 'Matchs sans but encaissé auxquels le joueur a participé, tous postes confondus.';



ALTER TABLE "public"."historical_player_statistics" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."historical_player_statistics_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."historical_team_statistics" (
    "scope" "text" NOT NULL,
    "through_season" "text" NOT NULL,
    "matches_played" integer NOT NULL,
    "wins" integer NOT NULL,
    "draws" integer NOT NULL,
    "losses" integer NOT NULL,
    "goals_for" integer NOT NULL,
    "goals_against" integer NOT NULL,
    "best_win_streak" integer NOT NULL,
    "best_win_start" "date",
    "best_win_end" "date",
    "best_unbeaten_streak" integer NOT NULL,
    "best_unbeaten_start" "date",
    "best_unbeaten_end" "date",
    "worst_loss_streak" integer NOT NULL,
    "worst_loss_start" "date",
    "worst_loss_end" "date",
    "worst_winless_streak" integer NOT NULL,
    "worst_winless_start" "date",
    "worst_winless_end" "date",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "recent_results" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "score_margin_distribution" "jsonb",
    CONSTRAINT "historical_team_statistics_best_unbeaten_streak_check" CHECK (("best_unbeaten_streak" >= 0)),
    CONSTRAINT "historical_team_statistics_best_win_streak_check" CHECK (("best_win_streak" >= 0)),
    CONSTRAINT "historical_team_statistics_draws_check" CHECK (("draws" >= 0)),
    CONSTRAINT "historical_team_statistics_goals_against_check" CHECK (("goals_against" >= 0)),
    CONSTRAINT "historical_team_statistics_goals_for_check" CHECK (("goals_for" >= 0)),
    CONSTRAINT "historical_team_statistics_losses_check" CHECK (("losses" >= 0)),
    CONSTRAINT "historical_team_statistics_matches_played_check" CHECK (("matches_played" >= 0)),
    CONSTRAINT "historical_team_statistics_scope_check" CHECK (("scope" = ANY (ARRAY['all_time'::"text", 'previous'::"text"]))),
    CONSTRAINT "historical_team_statistics_wins_check" CHECK (("wins" >= 0)),
    CONSTRAINT "historical_team_statistics_worst_loss_streak_check" CHECK (("worst_loss_streak" >= 0)),
    CONSTRAINT "historical_team_statistics_worst_winless_streak_check" CHECK (("worst_winless_streak" >= 0))
);


ALTER TABLE "public"."historical_team_statistics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_attendance" (
    "match_id" "uuid" NOT NULL,
    "season_player_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."match_attendance" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_composition_entries" (
    "match_id" "uuid" NOT NULL,
    "participant_id" "uuid" NOT NULL,
    "zone" "public"."sport_composition_zone" NOT NULL,
    "x" numeric(7,6),
    "y" numeric(7,6),
    "slot_label" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_composition_entries_check" CHECK (((("zone" = 'field'::"public"."sport_composition_zone") AND (("x" >= (0)::numeric) AND ("x" <= (1)::numeric)) AND (("y" >= (0)::numeric) AND ("y" <= (1)::numeric))) OR (("zone" <> 'field'::"public"."sport_composition_zone") AND ("x" IS NULL) AND ("y" IS NULL)))),
    CONSTRAINT "match_composition_entries_slot_label_check" CHECK ((("slot_label" IS NULL) OR ("char_length"("slot_label") <= 16))),
    CONSTRAINT "match_composition_entries_sort_order_check" CHECK (("sort_order" >= 0))
);


ALTER TABLE "public"."match_composition_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_composition_publications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "version" integer NOT NULL,
    "formation_code" "text",
    "snapshot" "jsonb" NOT NULL,
    "publication_kind" "text" NOT NULL,
    "published_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "published_by" "uuid" NOT NULL,
    CONSTRAINT "match_composition_publications_formation_code_check" CHECK ((("formation_code" IS NULL) OR ("char_length"("formation_code") <= 32))),
    CONSTRAINT "match_composition_publications_publication_kind_check" CHECK (("publication_kind" = ANY (ARRAY['initial'::"text", 'update'::"text", 'postmatch'::"text"]))),
    CONSTRAINT "match_composition_publications_snapshot_check" CHECK (("jsonb_typeof"("snapshot") = 'object'::"text")),
    CONSTRAINT "match_composition_publications_version_check" CHECK (("version" >= 1))
);


ALTER TABLE "public"."match_composition_publications" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_composition_publications" IS 'Immutable public snapshots written atomically for each composition publication.';



CREATE TABLE IF NOT EXISTS "public"."match_compositions" (
    "match_id" "uuid" NOT NULL,
    "formation_code" "text",
    "status" "public"."sport_composition_state" DEFAULT 'draft'::"public"."sport_composition_state" NOT NULL,
    "version" integer DEFAULT 0 NOT NULL,
    "has_unpublished_changes" boolean DEFAULT true NOT NULL,
    "squad_size_exception_approved" boolean DEFAULT false NOT NULL,
    "published_at" timestamp with time zone,
    "published_by" "uuid",
    "last_modified_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_modified_by" "uuid" NOT NULL,
    "closed_at" timestamp with time zone,
    CONSTRAINT "match_compositions_check" CHECK (((("version" = 0) AND ("published_at" IS NULL) AND ("published_by" IS NULL)) OR (("version" > 0) AND ("published_at" IS NOT NULL) AND ("published_by" IS NOT NULL)))),
    CONSTRAINT "match_compositions_formation_code_check" CHECK ((("formation_code" IS NULL) OR ("char_length"("formation_code") <= 32))),
    CONSTRAINT "match_compositions_status_check" CHECK (("status" <> 'none'::"public"."sport_composition_state")),
    CONSTRAINT "match_compositions_version_check" CHECK (("version" >= 0))
);


ALTER TABLE "public"."match_compositions" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_compositions" IS 'Current administrator draft. Published players read immutable publication snapshots instead.';



COMMENT ON COLUMN "public"."match_compositions"."has_unpublished_changes" IS 'True when the current normalized draft differs from the latest immutable publication.';



CREATE TABLE IF NOT EXISTS "public"."match_internal_composition_entries" (
    "match_id" "uuid" NOT NULL,
    "participant_id" "uuid" NOT NULL,
    "team_no" smallint,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_internal_composition_entries_team_no_check" CHECK ((("team_no" IS NULL) OR ("team_no" = ANY (ARRAY[1, 2]))))
);


ALTER TABLE "public"."match_internal_composition_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_internal_compositions" (
    "match_id" "uuid" NOT NULL,
    "team1_name" "text" DEFAULT 'Équipe 1'::"text" NOT NULL,
    "team2_name" "text" DEFAULT 'Équipe 2'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid"
);


ALTER TABLE "public"."match_internal_compositions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_live_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "minute" integer NOT NULL,
    "half" smallint NOT NULL,
    "scorer_participant_id" "uuid",
    "score_as_grinta_after" integer,
    "score_adverse_after" integer,
    "player_in_participant_id" "uuid",
    "player_out_participant_id" "uuid",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_opponent_own_goal" boolean DEFAULT false NOT NULL,
    CONSTRAINT "match_live_events_check" CHECK (((("event_type" = 'goal_us'::"text") AND ("score_as_grinta_after" IS NOT NULL) AND ("score_adverse_after" IS NULL) AND ("player_in_participant_id" IS NULL) AND ("player_out_participant_id" IS NULL) AND (NOT ("is_opponent_own_goal" AND ("scorer_participant_id" IS NOT NULL)))) OR (("event_type" = 'goal_them'::"text") AND ("score_adverse_after" IS NOT NULL) AND ("score_as_grinta_after" IS NULL) AND ("scorer_participant_id" IS NULL) AND ("player_in_participant_id" IS NULL) AND ("player_out_participant_id" IS NULL) AND (NOT "is_opponent_own_goal")) OR (("event_type" = 'substitution'::"text") AND ("player_in_participant_id" IS NOT NULL) AND ("player_out_participant_id" IS NOT NULL) AND ("scorer_participant_id" IS NULL) AND ("score_as_grinta_after" IS NULL) AND ("score_adverse_after" IS NULL) AND (NOT "is_opponent_own_goal")))),
    CONSTRAINT "match_live_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['goal_us'::"text", 'goal_them'::"text", 'substitution'::"text"]))),
    CONSTRAINT "match_live_events_half_check" CHECK (("half" = ANY (ARRAY[1, 2]))),
    CONSTRAINT "match_live_events_minute_check" CHECK (("minute" >= 0))
);

ALTER TABLE ONLY "public"."match_live_events" REPLICA IDENTITY FULL;


ALTER TABLE "public"."match_live_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_live_events" IS 'Append-only timeline of goals and substitutions. Never deleted at export time: it is the permanent source for the "Faits du match" tab.';



CREATE TABLE IF NOT EXISTS "public"."match_live_sessions" (
    "match_id" "uuid" NOT NULL,
    "state" "public"."match_live_state" DEFAULT 'not_started'::"public"."match_live_state" NOT NULL,
    "planned_duration_minutes" integer NOT NULL,
    "half" smallint DEFAULT 1 NOT NULL,
    "elapsed_seconds" integer DEFAULT 0 NOT NULL,
    "running_since" timestamp with time zone,
    "score_as_grinta" integer DEFAULT 0 NOT NULL,
    "score_adverse" integer DEFAULT 0 NOT NULL,
    "starting_composition_version" integer,
    "starting_lineup_snapshot" "jsonb",
    "lineup_revision" integer DEFAULT 0 NOT NULL,
    "started_at" timestamp with time zone,
    "finished_at" timestamp with time zone,
    "exported" boolean DEFAULT false NOT NULL,
    "exported_at" timestamp with time zone,
    "updated_by" "uuid" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_live_sessions_check" CHECK ((("state" <> 'running'::"public"."match_live_state") OR ("running_since" IS NOT NULL))),
    CONSTRAINT "match_live_sessions_check1" CHECK ((("state" = 'running'::"public"."match_live_state") OR ("running_since" IS NULL))),
    CONSTRAINT "match_live_sessions_elapsed_seconds_check" CHECK (("elapsed_seconds" >= 0)),
    CONSTRAINT "match_live_sessions_half_check" CHECK (("half" = ANY (ARRAY[1, 2]))),
    CONSTRAINT "match_live_sessions_planned_duration_minutes_check" CHECK ((("planned_duration_minutes" >= 1) AND ("planned_duration_minutes" <= 200))),
    CONSTRAINT "match_live_sessions_score_adverse_check" CHECK ((("score_adverse" >= 0) AND ("score_adverse" <= 99))),
    CONSTRAINT "match_live_sessions_score_as_grinta_check" CHECK ((("score_as_grinta" >= 0) AND ("score_as_grinta" <= 99)))
);

ALTER TABLE ONLY "public"."match_live_sessions" REPLICA IDENTITY FULL;


ALTER TABLE "public"."match_live_sessions" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_live_sessions" IS 'One row per match tracked live via the Tableau Blanc. Independent of matches.status.';



COMMENT ON COLUMN "public"."match_live_sessions"."exported" IS 'True once publish_match_live_recap successfully called finalize_match_sport_postgame. Immutable afterwards.';



CREATE TABLE IF NOT EXISTS "public"."match_man_of_match" (
    "match_id" "uuid" NOT NULL,
    "season_player_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."match_man_of_match" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_odds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "odds_victoire_as_grinta" numeric NOT NULL,
    "odds_nul" numeric NOT NULL,
    "odds_victoire_adverse" numeric NOT NULL,
    "computed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "probability_win" numeric,
    "probability_draw" numeric,
    "probability_loss" numeric,
    "expected_goals_as_grinta" numeric,
    "expected_goals_adverse" numeric,
    "confidence" numeric,
    "model_version" "text" DEFAULT 'legacy'::"text" NOT NULL,
    CONSTRAINT "match_odds_odds_nul_check" CHECK (("odds_nul" >= (1)::numeric)),
    CONSTRAINT "match_odds_odds_victoire_adverse_check" CHECK (("odds_victoire_adverse" >= (1)::numeric)),
    CONSTRAINT "match_odds_odds_victoire_as_grinta_check" CHECK (("odds_victoire_as_grinta" >= (1)::numeric))
);


ALTER TABLE "public"."match_odds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_player_stats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "goals" integer DEFAULT 0 NOT NULL,
    "clean_sheet" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "season_player_id" "uuid" NOT NULL,
    CONSTRAINT "match_player_stats_goals_check" CHECK (("goals" >= 0))
);


ALTER TABLE "public"."match_player_stats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_predictions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "predicted_score_as_grinta" integer DEFAULT 0 NOT NULL,
    "predicted_score_adverse" integer DEFAULT 0 NOT NULL,
    "is_filled" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_predictions_predicted_score_adverse_check" CHECK ((("predicted_score_adverse" >= 0) AND ("predicted_score_adverse" <= 99))),
    CONSTRAINT "match_predictions_predicted_score_as_grinta_check" CHECK ((("predicted_score_as_grinta" >= 0) AND ("predicted_score_as_grinta" <= 99)))
);


ALTER TABLE "public"."match_predictions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."match_sport_finalization_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "version" integer NOT NULL,
    "snapshot" "jsonb" NOT NULL,
    "validation_kind" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    CONSTRAINT "match_sport_finalization_versions_snapshot_check" CHECK (("jsonb_typeof"("snapshot") = 'object'::"text")),
    CONSTRAINT "match_sport_finalization_versions_validation_kind_check" CHECK (("validation_kind" = ANY (ARRAY['initial'::"text", 'correction'::"text"]))),
    CONSTRAINT "match_sport_finalization_versions_version_check" CHECK (("version" >= 1))
);


ALTER TABLE "public"."match_sport_finalization_versions" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_finalization_versions" IS 'Immutable snapshots of every initial validation and later correction.';



CREATE TABLE IF NOT EXISTS "public"."match_sport_finalizations" (
    "match_id" "uuid" NOT NULL,
    "version" integer DEFAULT 0 NOT NULL,
    "score_as_grinta" smallint NOT NULL,
    "score_adverse" smallint NOT NULL,
    "composition_version" integer DEFAULT 0 NOT NULL,
    "validated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "validated_by" "uuid" NOT NULL,
    "corrected_at" timestamp with time zone,
    "corrected_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_sport_finalizations_composition_version_check" CHECK (("composition_version" >= 0)),
    CONSTRAINT "match_sport_finalizations_score_adverse_check" CHECK ((("score_adverse" >= 0) AND ("score_adverse" <= 99))),
    CONSTRAINT "match_sport_finalizations_score_as_grinta_check" CHECK ((("score_as_grinta" >= 0) AND ("score_as_grinta" <= 99))),
    CONSTRAINT "match_sport_finalizations_version_check" CHECK (("version" >= 0))
);


ALTER TABLE "public"."match_sport_finalizations" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_finalizations" IS 'Current validated post-match state. Permanent-player statistics are synchronized atomically.';



CREATE TABLE IF NOT EXISTS "public"."match_sport_motm_elections" (
    "match_id" "uuid" NOT NULL,
    "finalization_version" integer NOT NULL,
    "state" "public"."sport_vote_state" DEFAULT 'draft'::"public"."sport_vote_state" NOT NULL,
    "opens_at" timestamp with time zone,
    "closes_at" timestamp with time zone,
    "closed_at" timestamp with time zone,
    "total_votes" integer DEFAULT 0 NOT NULL,
    "max_votes" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_sport_motm_elections_check" CHECK (((("state" = 'open'::"public"."sport_vote_state") AND ("opens_at" IS NOT NULL) AND ("closes_at" IS NOT NULL) AND ("closed_at" IS NULL)) OR (("state" = 'closed'::"public"."sport_vote_state") AND ("opens_at" IS NOT NULL) AND ("closes_at" IS NOT NULL) AND ("closed_at" IS NOT NULL)) OR ("state" = ANY (ARRAY['draft'::"public"."sport_vote_state", 'cancelled'::"public"."sport_vote_state", 'unavailable'::"public"."sport_vote_state"])))),
    CONSTRAINT "match_sport_motm_elections_check1" CHECK ((("closes_at" IS NULL) OR ("opens_at" IS NULL) OR ("closes_at" > "opens_at"))),
    CONSTRAINT "match_sport_motm_elections_finalization_version_check" CHECK (("finalization_version" >= 1)),
    CONSTRAINT "match_sport_motm_elections_max_votes_check" CHECK (("max_votes" >= 0)),
    CONSTRAINT "match_sport_motm_elections_total_votes_check" CHECK (("total_votes" >= 0))
);


ALTER TABLE "public"."match_sport_motm_elections" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_motm_elections" IS 'Twenty-four-hour collective MOTM ballot tied to one validated final-attendance version.';



CREATE TABLE IF NOT EXISTS "public"."match_sport_motm_results" (
    "match_id" "uuid" NOT NULL,
    "participant_id" "uuid" NOT NULL,
    "finalization_version" integer NOT NULL,
    "votes_count" integer DEFAULT 0 NOT NULL,
    "is_winner" boolean DEFAULT false NOT NULL,
    "computed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_sport_motm_results_finalization_version_check" CHECK (("finalization_version" >= 1)),
    CONSTRAINT "match_sport_motm_results_votes_count_check" CHECK (("votes_count" >= 0))
);


ALTER TABLE "public"."match_sport_motm_results" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_motm_results" IS 'Closed-ballot totals. Ties deliberately produce several winners.';



CREATE TABLE IF NOT EXISTS "public"."match_sport_motm_votes" (
    "match_id" "uuid" NOT NULL,
    "voter_profile_id" "uuid" NOT NULL,
    "candidate_participant_id" "uuid" NOT NULL,
    "finalization_version" integer NOT NULL,
    "cast_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_sport_motm_votes_finalization_version_check" CHECK (("finalization_version" >= 1))
);


ALTER TABLE "public"."match_sport_motm_votes" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_motm_votes" IS 'Secret and immutable ballot: one permanent present player, one candidate, one vote.';



CREATE TABLE IF NOT EXISTS "public"."match_sport_participant_events" (
    "id" bigint NOT NULL,
    "participant_id" "uuid" NOT NULL,
    "match_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "old_value" "jsonb",
    "new_value" "jsonb",
    "actor_profile_id" "uuid",
    "actor_kind" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_sport_participant_events_actor_kind_check" CHECK (("actor_kind" = ANY (ARRAY['player'::"text", 'staff'::"text", 'system'::"text"]))),
    CONSTRAINT "match_sport_participant_events_event_type_check" CHECK ((("event_type" ~ '^[a-z][a-z0-9_]*$'::"text") AND ("char_length"("event_type") <= 64))),
    CONSTRAINT "match_sport_participant_events_new_value_check" CHECK ((("new_value" IS NULL) OR ("jsonb_typeof"("new_value") = 'object'::"text"))),
    CONSTRAINT "match_sport_participant_events_old_value_check" CHECK ((("old_value" IS NULL) OR ("jsonb_typeof"("old_value") = 'object'::"text")))
);


ALTER TABLE "public"."match_sport_participant_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_participant_events" IS 'Append-only history for availability responses and later staff decisions.';



ALTER TABLE "public"."match_sport_participant_events" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."match_sport_participant_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."match_sport_participants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "season_player_id" "uuid",
    "is_eligible" boolean DEFAULT true NOT NULL,
    "availability_status" "public"."sport_availability_status" DEFAULT 'no_response'::"public"."sport_availability_status" NOT NULL,
    "availability_comment_private" "text",
    "availability_updated_at" timestamp with time zone,
    "availability_updated_by" "uuid",
    "selection_status" "public"."sport_selection_status" DEFAULT 'undecided'::"public"."sport_selection_status" NOT NULL,
    "selection_updated_at" timestamp with time zone,
    "selection_updated_by" "uuid",
    "final_presence_status" "public"."sport_final_presence_status" DEFAULT 'pending'::"public"."sport_final_presence_status" NOT NULL,
    "final_presence_confirmed_at" timestamp with time zone,
    "final_presence_confirmed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "convocation_status" "public"."sport_convocation_status" DEFAULT 'not_applicable'::"public"."sport_convocation_status" NOT NULL,
    "convocation_manual_override" boolean DEFAULT false NOT NULL,
    "waitlist_position_snapshot" integer,
    "waitlist_recommended_not_convoked" boolean DEFAULT false NOT NULL,
    "waitlist_turn_should_consume" boolean DEFAULT false NOT NULL,
    "waitlist_turn_state" "public"."sport_waitlist_turn_state" DEFAULT 'not_applicable'::"public"."sport_waitlist_turn_state" NOT NULL,
    "waitlist_turn_updated_at" timestamp with time zone,
    "promoted_after_withdrawal_at" timestamp with time zone,
    "promoted_from_participant_id" "uuid",
    "guest_player_id" "uuid",
    "final_selection_status" "public"."sport_selection_status" DEFAULT 'undecided'::"public"."sport_selection_status" NOT NULL,
    "final_goals" smallint DEFAULT 0 NOT NULL,
    "final_clean_sheet" boolean DEFAULT false NOT NULL,
    CONSTRAINT "match_sport_participants_availability_comment_private_check" CHECK ((("availability_comment_private" IS NULL) OR ("char_length"("availability_comment_private") <= 500))),
    CONSTRAINT "match_sport_participants_check" CHECK ((("availability_comment_private" IS NULL) OR ("availability_status" = 'absent'::"public"."sport_availability_status"))),
    CONSTRAINT "match_sport_participants_exactly_one_identity_check" CHECK (("num_nonnulls"("season_player_id", "guest_player_id") = 1)),
    CONSTRAINT "match_sport_participants_final_goals_check" CHECK ((("final_goals" >= 0) AND ("final_goals" <= 99))),
    CONSTRAINT "match_sport_participants_final_presence_consistency_check" CHECK ((("final_presence_status" = 'pending'::"public"."sport_final_presence_status") OR ("final_presence_status" = 'present'::"public"."sport_final_presence_status") OR (("final_presence_status" = 'actual_absent'::"public"."sport_final_presence_status") AND ("final_selection_status" = ANY (ARRAY['undecided'::"public"."sport_selection_status", 'not_selected'::"public"."sport_selection_status"])) AND ("final_goals" = 0) AND (NOT "final_clean_sheet")))),
    CONSTRAINT "match_sport_participants_guest_availability_check" CHECK ((("guest_player_id" IS NULL) OR ("availability_status" = 'not_applicable'::"public"."sport_availability_status"))),
    CONSTRAINT "match_sport_participants_waitlist_position_snapshot_check" CHECK ((("waitlist_position_snapshot" IS NULL) OR ("waitlist_position_snapshot" >= 1)))
);


ALTER TABLE "public"."match_sport_participants" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_participants" IS 'Permanent roster participants. Guest identities are introduced by a later isolated migration.';



COMMENT ON COLUMN "public"."match_sport_participants"."availability_comment_private" IS 'Private absence comment visible only to its player and active administrators.';



COMMENT ON COLUMN "public"."match_sport_participants"."final_presence_status" IS 'Actual presence validated after the match; this alone feeds attendance statistics.';



COMMENT ON COLUMN "public"."match_sport_participants"."waitlist_turn_should_consume" IS 'Administrator-controlled decision. It may remain true even when the player is finally convoked.';



COMMENT ON COLUMN "public"."match_sport_participants"."final_selection_status" IS 'Actual post-match role, independent from the published pre-match composition.';



COMMENT ON COLUMN "public"."match_sport_participants"."final_goals" IS 'Validated goals. Permanent players are mirrored to match_player_stats; guest goals stay here.';



CREATE TABLE IF NOT EXISTS "public"."match_sport_workflows" (
    "match_id" "uuid" NOT NULL,
    "availability_state" "public"."sport_availability_state" DEFAULT 'pending'::"public"."sport_availability_state" NOT NULL,
    "availability_opens_at" timestamp with time zone NOT NULL,
    "availability_opened_at" timestamp with time zone,
    "composition_state" "public"."sport_composition_state" DEFAULT 'none'::"public"."sport_composition_state" NOT NULL,
    "composition_version" integer DEFAULT 0 NOT NULL,
    "squad_size_limit" smallint DEFAULT 14 NOT NULL,
    "presence_state" "public"."sport_presence_state" DEFAULT 'pending'::"public"."sport_presence_state" NOT NULL,
    "vote_state" "public"."sport_vote_state" DEFAULT 'unavailable'::"public"."sport_vote_state" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "updated_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "convocation_state" "public"."sport_convocation_state" DEFAULT 'draft'::"public"."sport_convocation_state" NOT NULL,
    "convocation_version" integer DEFAULT 0 NOT NULL,
    "convocation_generated_at" timestamp with time zone,
    "convocation_published_at" timestamp with time zone,
    "late_withdrawal_cutoff_at" timestamp with time zone,
    CONSTRAINT "match_sport_workflows_composition_version_check" CHECK (("composition_version" >= 0)),
    CONSTRAINT "match_sport_workflows_convocation_version_check" CHECK (("convocation_version" >= 0)),
    CONSTRAINT "match_sport_workflows_squad_size_limit_check" CHECK ((("squad_size_limit" >= 1) AND ("squad_size_limit" <= 30)))
);


ALTER TABLE "public"."match_sport_workflows" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_sport_workflows" IS 'Per-match state machine for the optional sports-management module.';



COMMENT ON COLUMN "public"."match_sport_workflows"."availability_opens_at" IS 'Absolute opening instant derived from matches.kickoff_at and server configuration.';



COMMENT ON COLUMN "public"."match_sport_workflows"."squad_size_limit" IS 'Default 14; later staff workflows may override it per match with audit.';



COMMENT ON COLUMN "public"."match_sport_workflows"."late_withdrawal_cutoff_at" IS 'Noon Europe/Paris on the calendar day before kickoff. Strictly later withdrawals preserve the promoted player turn consumption.';



CREATE TABLE IF NOT EXISTS "public"."match_weather" (
    "match_id" "uuid" NOT NULL,
    "forecast_for" timestamp with time zone NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "geocoded_address" "text" NOT NULL,
    "timezone" "text",
    "temperature" numeric,
    "apparent_temperature" numeric,
    "precipitation_probability" integer,
    "weather_code" integer,
    "wind_speed" numeric,
    "wind_gusts" numeric,
    "humidity" integer,
    "hourly_forecast" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "source" "text" DEFAULT 'open-meteo'::"text" NOT NULL,
    "fetched_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "match_weather_geocoded_address_check" CHECK ((("char_length"("geocoded_address") >= 1) AND ("char_length"("geocoded_address") <= 500))),
    CONSTRAINT "match_weather_hourly_forecast_check" CHECK (("jsonb_typeof"("hourly_forecast") = 'array'::"text")),
    CONSTRAINT "match_weather_humidity_check" CHECK ((("humidity" IS NULL) OR (("humidity" >= 0) AND ("humidity" <= 100)))),
    CONSTRAINT "match_weather_latitude_check" CHECK ((("latitude" >= ('-90'::integer)::double precision) AND ("latitude" <= (90)::double precision))),
    CONSTRAINT "match_weather_longitude_check" CHECK ((("longitude" >= ('-180'::integer)::double precision) AND ("longitude" <= (180)::double precision))),
    CONSTRAINT "match_weather_precipitation_probability_check" CHECK ((("precipitation_probability" IS NULL) OR (("precipitation_probability" >= 0) AND ("precipitation_probability" <= 100)))),
    CONSTRAINT "match_weather_source_check" CHECK (("source" = 'open-meteo'::"text")),
    CONSTRAINT "match_weather_wind_gusts_check" CHECK ((("wind_gusts" IS NULL) OR ("wind_gusts" >= (0)::numeric))),
    CONSTRAINT "match_weather_wind_speed_check" CHECK ((("wind_speed" IS NULL) OR ("wind_speed" >= (0)::numeric)))
);


ALTER TABLE "public"."match_weather" OWNER TO "postgres";


COMMENT ON TABLE "public"."match_weather" IS 'Server-cached Open-Meteo forecast for a match, refreshed only from J-6 until kickoff.';



CREATE TABLE IF NOT EXISTS "public"."matches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "opponent_id" "uuid",
    "match_date" "date" NOT NULL,
    "match_time" time without time zone,
    "location" "text" NOT NULL,
    "planned_duration_minutes" integer NOT NULL,
    "status" "text" DEFAULT 'a_venir'::"text" NOT NULL,
    "score_as_grinta" integer,
    "score_adverse" integer,
    "created_by" "uuid" DEFAULT '00000000-0000-0000-0000-000000000001'::"uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "competition" "text" DEFAULT 'Championnat'::"text",
    "result_validated_at" timestamp with time zone,
    "predictions_closed_at" timestamp with time zone,
    "kickoff_at" timestamp with time zone,
    "address" "text",
    "match_type" "text" DEFAULT 'championnat'::"text" NOT NULL,
    "jersey_note" "text",
    CONSTRAINT "matches_created_by_required" CHECK (("created_by" IS NOT NULL)),
    CONSTRAINT "matches_location_check" CHECK (("location" = ANY (ARRAY['domicile'::"text", 'exterieur'::"text"]))),
    CONSTRAINT "matches_match_type_check" CHECK (("match_type" = ANY (ARRAY['amical'::"text", 'championnat'::"text", 'entre_nous'::"text"]))),
    CONSTRAINT "matches_planned_duration_minutes_check" CHECK (("planned_duration_minutes" > 0)),
    CONSTRAINT "matches_score_adverse_check" CHECK ((("score_adverse" >= 0) AND ("score_adverse" <= 99))),
    CONSTRAINT "matches_score_as_grinta_check" CHECK ((("score_as_grinta" >= 0) AND ("score_as_grinta" <= 99))),
    CONSTRAINT "matches_status_check" CHECK (("status" = ANY (ARRAY['a_venir'::"text", 'termine'::"text", 'archive'::"text", 'annule'::"text"])))
);


ALTER TABLE "public"."matches" OWNER TO "postgres";


COMMENT ON COLUMN "public"."matches"."kickoff_at" IS 'Instant absolu du coup d’envoi, dérivé de match_date/match_time en Europe/Paris.';



CREATE TABLE IF NOT EXISTS "public"."opponents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "address" "text",
    CONSTRAINT "opponents_name_check" CHECK ((("name" = "btrim"("name")) AND (("length"("name") >= 2) AND ("length"("name") <= 100)))),
    CONSTRAINT "opponents_name_not_blank" CHECK ((NULLIF("btrim"("name"), ''::"text") IS NOT NULL))
);


ALTER TABLE "public"."opponents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."player_aliases" (
    "id" bigint NOT NULL,
    "player_id" "uuid" NOT NULL,
    "alias" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "player_aliases_alias_check" CHECK (("btrim"("alias") <> ''::"text"))
);


ALTER TABLE "public"."player_aliases" OWNER TO "postgres";


COMMENT ON TABLE "public"."player_aliases" IS 'Variantes de nom connues d''une identité canonique. Un même libellé peut rester ambigu entre plusieurs personnes.';



ALTER TABLE "public"."player_aliases" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."player_aliases_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."players" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "display_name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "archived_at" timestamp with time zone,
    CONSTRAINT "players_display_name_check" CHECK (("btrim"("display_name") <> ''::"text"))
);


ALTER TABLE "public"."players" OWNER TO "postgres";


COMMENT ON TABLE "public"."players" IS 'Identité canonique permanente d''une personne/joueur, indépendante du compte, de la saison et des matchs.';



COMMENT ON COLUMN "public"."players"."display_name" IS 'Libellé canonique. Les variantes historiques sont conservées dans player_aliases.';



CREATE TABLE IF NOT EXISTS "public"."profile_badge_seen" (
    "profile_id" "uuid" NOT NULL,
    "badge_code" "text" NOT NULL,
    "seen_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profile_badge_seen" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profile_badges" (
    "profile_id" "uuid" NOT NULL,
    "badge_id" "uuid" NOT NULL,
    "source" "text" DEFAULT 'auto'::"text" NOT NULL,
    "awarded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "awarded_by" "uuid",
    "featured" boolean DEFAULT false NOT NULL,
    CONSTRAINT "profile_badges_source_check" CHECK (("source" = ANY (ARRAY['auto'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."profile_badges" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "photo_url" "text",
    "role" "text" DEFAULT 'pronostiqueur'::"text" NOT NULL,
    "is_goalkeeper" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "surnom" "text",
    "notify_match_reminders" boolean DEFAULT true NOT NULL,
    "notify_prediction_reminders" boolean DEFAULT true NOT NULL,
    "username" "text",
    "password_set" boolean DEFAULT true NOT NULL,
    "notify_prediction_open" boolean DEFAULT true NOT NULL,
    "must_change_password" boolean DEFAULT false NOT NULL,
    "notify_motm_vote" boolean DEFAULT true NOT NULL,
    "notify_convocation" boolean DEFAULT true NOT NULL,
    "player_id" "uuid",
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['pronostiqueur'::"text", 'admin'::"text"]))),
    CONSTRAINT "profiles_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."must_change_password" IS 'Read by the signed-in user to force the temporary-password replacement screen; writes are performed through secured RPCs.';



CREATE TABLE IF NOT EXISTS "public"."push_delivery_log" (
    "id" bigint NOT NULL,
    "match_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "profile_id" "uuid",
    "endpoint_host" "text",
    "success" boolean NOT NULL,
    "status_code" integer,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attempts" smallint DEFAULT 1 NOT NULL,
    CONSTRAINT "push_delivery_log_attempts_check" CHECK ((("attempts" >= 1) AND ("attempts" <= 2))),
    CONSTRAINT "push_delivery_log_kind_check" CHECK (("kind" = ANY (ARRAY['availability_open'::"text", 'availability_j3'::"text", 'availability_j1'::"text", 'availability_manual'::"text", 'motm_open'::"text", 'prediction_j5'::"text", 'match_cancelled'::"text", 'match_rescheduled_date'::"text", 'match_rescheduled_time'::"text", 'convocation_promoted'::"text"])))
);


ALTER TABLE "public"."push_delivery_log" OWNER TO "postgres";


ALTER TABLE "public"."push_delivery_log" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."push_delivery_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."push_notification_log" (
    "match_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "sent_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."push_notification_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "endpoint" "text" NOT NULL,
    "p256dh" "text" NOT NULL,
    "auth" "text" NOT NULL,
    "user_agent" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."push_subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."season_awards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "award_type" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."season_awards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."season_players" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "is_goalkeeper" boolean DEFAULT false NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "position" integer,
    "profile_id" "uuid",
    "photo_url" "text",
    "is_coach" boolean DEFAULT false NOT NULL,
    "player_id" "uuid" NOT NULL
);


ALTER TABLE "public"."season_players" OWNER TO "postgres";


COMMENT ON COLUMN "public"."season_players"."profile_id" IS 'Optional pronosticator profile linked to this roster player for the season.';



CREATE TABLE IF NOT EXISTS "public"."season_predictions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "predictor_profile_id" "uuid" NOT NULL,
    "category" "text" NOT NULL,
    "predicted_value_30" integer DEFAULT 0 NOT NULL,
    "is_filled" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "season_player_id" "uuid" NOT NULL,
    CONSTRAINT "season_predictions_category_check" CHECK (("category" = ANY (ARRAY['buts'::"text", 'clean_sheets'::"text"]))),
    CONSTRAINT "season_predictions_predicted_value_20_check" CHECK (("predicted_value_30" >= 0))
);


ALTER TABLE "public"."season_predictions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."seasons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "season_predictions_locked_at" timestamp with time zone,
    CONSTRAINT "seasons_name_format_check" CHECK (
CASE
    WHEN ("name" ~ '^[0-9]{4}-[0-9]{4}$'::"text") THEN ((SUBSTRING("name" FROM 6 FOR 4))::integer = ((SUBSTRING("name" FROM 1 FOR 4))::integer + 1))
    ELSE false
END),
    CONSTRAINT "seasons_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'terminee'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."seasons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shared_data_change_signals" (
    "key" "text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "profile_revision" bigint DEFAULT 1 NOT NULL,
    "sports_revision" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "shared_data_change_signals_key_format" CHECK (("key" ~ '^[a-z][a-z0-9_]*$'::"text")),
    CONSTRAINT "shared_data_change_signals_profile_revision_valid" CHECK ((("profile_revision" > 0) AND ("profile_revision" <= "revision"))),
    CONSTRAINT "shared_data_change_signals_revision_positive" CHECK (("revision" > 0)),
    CONSTRAINT "shared_data_change_signals_sports_revision_valid" CHECK ((("sports_revision" > 0) AND ("sports_revision" <= "revision")))
);


ALTER TABLE "public"."shared_data_change_signals" OWNER TO "postgres";


COMMENT ON TABLE "public"."shared_data_change_signals" IS 'Public-safe Realtime revision used to refresh shared Flutter module caches.';



COMMENT ON COLUMN "public"."shared_data_change_signals"."profile_revision" IS 'Revision incremented only when the public.profiles table changes.';



COMMENT ON COLUMN "public"."shared_data_change_signals"."sports_revision" IS 'Revision incremented for availability, selection and composition changes.';



CREATE TABLE IF NOT EXISTS "public"."sport_availability_notification_events" (
    "id" bigint NOT NULL,
    "match_id" "uuid" NOT NULL,
    "participant_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "source" "text" NOT NULL,
    "scheduled_for" timestamp with time zone NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "requested_by" "uuid",
    "reason" "text",
    "dispatch_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "dispatch_requested_at" timestamp with time zone,
    "delivery_completed_at" timestamp with time zone,
    "network_request_id" bigint,
    "attempted_count" integer DEFAULT 0 NOT NULL,
    "sent_count" integer DEFAULT 0 NOT NULL,
    "failed_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sport_availability_notification_events_attempted_count_check" CHECK (("attempted_count" >= 0)),
    CONSTRAINT "sport_availability_notification_events_check" CHECK (((("source" = 'manual'::"text") AND ("kind" = 'availability_manual'::"text")) OR (("source" = 'automatic'::"text") AND ("kind" <> 'availability_manual'::"text")))),
    CONSTRAINT "sport_availability_notification_events_dispatch_status_check" CHECK (("dispatch_status" = ANY (ARRAY['pending'::"text", 'dispatch_requested'::"text", 'completed'::"text", 'no_subscription'::"text", 'dispatch_failed'::"text"]))),
    CONSTRAINT "sport_availability_notification_events_failed_count_check" CHECK (("failed_count" >= 0)),
    CONSTRAINT "sport_availability_notification_events_kind_check" CHECK (("kind" = ANY (ARRAY['availability_open'::"text", 'availability_j3'::"text", 'availability_j1'::"text", 'availability_manual'::"text"]))),
    CONSTRAINT "sport_availability_notification_events_reason_check" CHECK ((("reason" IS NULL) OR ("char_length"("reason") <= 500))),
    CONSTRAINT "sport_availability_notification_events_sent_count_check" CHECK (("sent_count" >= 0)),
    CONSTRAINT "sport_availability_notification_events_source_check" CHECK (("source" = ANY (ARRAY['automatic'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."sport_availability_notification_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."sport_availability_notification_events" IS 'Per-player history and outbox for availability opening and reminder pushes.';



ALTER TABLE "public"."sport_availability_notification_events" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."sport_availability_notification_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."sport_waitlist_entries" (
    "season_id" "uuid" NOT NULL,
    "season_player_id" "uuid" NOT NULL,
    "position" integer NOT NULL,
    "previous_season_attendance_count" integer DEFAULT 0 NOT NULL,
    "previous_season_match_count" integer DEFAULT 0 NOT NULL,
    "source" "text" DEFAULT 'previous_season_attendance'::"text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "updated_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "manual_waitlist_count" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "sport_waitlist_entries_manual_waitlist_count_check" CHECK (("manual_waitlist_count" >= 0)),
    CONSTRAINT "sport_waitlist_entries_position_check" CHECK (("position" >= 1)),
    CONSTRAINT "sport_waitlist_entries_previous_season_attendance_count_check" CHECK (("previous_season_attendance_count" >= 0)),
    CONSTRAINT "sport_waitlist_entries_previous_season_match_count_check" CHECK (("previous_season_match_count" >= 0)),
    CONSTRAINT "sport_waitlist_entries_source_check" CHECK (("source" = ANY (ARRAY['previous_season_attendance'::"text", 'new_player'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."sport_waitlist_entries" OWNER TO "postgres";


COMMENT ON TABLE "public"."sport_waitlist_entries" IS 'Admin-managed permanent waitlist order for one season. Lower position is proposed first for non-convocation.';



COMMENT ON COLUMN "public"."sport_waitlist_entries"."previous_season_attendance_count" IS 'Snapshot used only to initialize the order; administrators retain full manual control.';



CREATE OR REPLACE VIEW "public"."v_match_prediction_flags" WITH ("security_invoker"='true') AS
 SELECT "mp"."profile_id",
    (("mp"."is_filled" AND ("sign"((("mp"."predicted_score_as_grinta" - "mp"."predicted_score_adverse"))::numeric) = "sign"((("m"."score_as_grinta" - "m"."score_adverse"))::numeric))))::integer AS "bon_pari",
    (("mp"."is_filled" AND ("mp"."predicted_score_as_grinta" = "m"."score_as_grinta") AND ("mp"."predicted_score_adverse" = "m"."score_adverse")))::integer AS "exact"
   FROM ("public"."match_predictions" "mp"
     JOIN "public"."matches" "m" ON ((("m"."id" = "mp"."match_id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))));


ALTER VIEW "public"."v_match_prediction_flags" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_match_prediction_points" WITH ("security_invoker"='true') AS
 SELECT "mp"."id",
    "mp"."match_id",
    "mp"."profile_id",
        CASE
            WHEN (NOT "mp"."is_filled") THEN (0)::numeric
            WHEN ("sign"((("mp"."predicted_score_as_grinta" - "mp"."predicted_score_adverse"))::numeric) <> "sign"((("m"."score_as_grinta" - "m"."score_adverse"))::numeric)) THEN (0)::numeric
            ELSE (
            CASE
                WHEN ("m"."score_as_grinta" > "m"."score_adverse") THEN "mo"."odds_victoire_as_grinta"
                WHEN ("m"."score_as_grinta" = "m"."score_adverse") THEN "mo"."odds_nul"
                ELSE "mo"."odds_victoire_adverse"
            END *
            CASE
                WHEN (("mp"."predicted_score_as_grinta" = "m"."score_as_grinta") AND ("mp"."predicted_score_adverse" = "m"."score_adverse")) THEN (2)::numeric
                WHEN (("mp"."predicted_score_as_grinta" - "mp"."predicted_score_adverse") = ("m"."score_as_grinta" - "m"."score_adverse")) THEN 1.5
                WHEN (("mp"."predicted_score_as_grinta" = "m"."score_as_grinta") OR ("mp"."predicted_score_adverse" = "m"."score_adverse")) THEN 1.5
                ELSE (1)::numeric
            END)
        END AS "points"
   FROM (("public"."match_predictions" "mp"
     JOIN "public"."matches" "m" ON ((("m"."id" = "mp"."match_id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))))
     JOIN "public"."match_odds" "mo" ON (("mo"."match_id" = "m"."id")));


ALTER VIEW "public"."v_match_prediction_points" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_player_season_stats" WITH ("security_invoker"='true') AS
 SELECT "season_id",
    "id" AS "season_player_id",
    "first_name",
    "last_name",
    "is_goalkeeper",
    "is_active",
    COALESCE(( SELECT ("sum"("s"."goals"))::integer AS "sum"
           FROM ("public"."match_player_stats" "s"
             JOIN "public"."matches" "m" ON (("m"."id" = "s"."match_id")))
          WHERE (("s"."season_player_id" = "sp"."id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))), 0) AS "goals",
    COALESCE(( SELECT ("count"(*))::integer AS "count"
           FROM ("public"."match_player_stats" "s"
             JOIN "public"."matches" "m" ON (("m"."id" = "s"."match_id")))
          WHERE (("s"."season_player_id" = "sp"."id") AND "s"."clean_sheet" AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))), 0) AS "clean_sheets"
   FROM "public"."season_players" "sp";


ALTER VIEW "public"."v_player_season_stats" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_season_match_count" WITH ("security_invoker"='true') AS
 SELECT "season_id",
    ("count"(*))::integer AS "matches_played"
   FROM "public"."matches"
  WHERE (("status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])) AND ("score_as_grinta" IS NOT NULL))
  GROUP BY "season_id";


ALTER VIEW "public"."v_season_match_count" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_season_prediction_bonus" WITH ("security_invoker"='true') AS
 WITH "eligible_seasons" AS (
         SELECT "seasons"."id",
            "seasons"."status"
           FROM "public"."seasons"
          WHERE (("seasons"."season_predictions_locked_at" IS NOT NULL) OR ("seasons"."status" = 'archived'::"text"))
        ), "expected_predictions" AS (
         SELECT "sp"."season_id",
            "count"(*) AS "expected_count"
           FROM ("public"."season_players" "sp"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
          GROUP BY "sp"."season_id"
        ), "predictor_completion" AS (
         SELECT "sp"."season_id",
            "sp"."predictor_profile_id",
            "count"(*) FILTER (WHERE ("sp"."is_filled" AND ("sp"."category" = ANY (ARRAY['buts'::"text", 'clean_sheets'::"text"])))) AS "filled_count"
           FROM ("public"."season_predictions" "sp"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
          GROUP BY "sp"."season_id", "sp"."predictor_profile_id"
        ), "eligible_predictors" AS (
         SELECT "pc_1"."season_id",
            "pc_1"."predictor_profile_id"
           FROM ("predictor_completion" "pc_1"
             JOIN "expected_predictions" "ep" ON (("ep"."season_id" = "pc_1"."season_id")))
          WHERE (("ep"."expected_count" > 0) AND ("pc_1"."filled_count" = "ep"."expected_count"))
        ), "participant_count" AS (
         SELECT "eligible_predictors"."season_id",
            ("count"(*))::integer AS "participant_count"
           FROM "eligible_predictors"
          GROUP BY "eligible_predictors"."season_id"
        ), "target_goals" AS (
         SELECT "pl"."season_id",
            "pl"."id" AS "season_player_id",
            ("st"."goals")::numeric AS "target"
           FROM (("public"."season_players" "pl"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "pl"."season_id")))
             JOIN "public"."v_player_season_stats" "st" ON (("st"."season_player_id" = "pl"."id")))
          WHERE (NOT "pl"."is_goalkeeper")
        ), "goal_predictions" AS (
         SELECT "sp"."season_id",
            "sp"."predictor_profile_id",
            "sp"."season_player_id",
            "sp"."predicted_value_30"
           FROM (("public"."season_predictions" "sp"
             JOIN "eligible_predictors" "ep" ON ((("ep"."season_id" = "sp"."season_id") AND ("ep"."predictor_profile_id" = "sp"."predictor_profile_id"))))
             JOIN "public"."season_players" "pl" ON (("pl"."id" = "sp"."season_player_id")))
          WHERE (("sp"."category" = 'buts'::"text") AND "sp"."is_filled" AND (NOT "pl"."is_goalkeeper"))
        ), "pair_scores" AS (
         SELECT "a"."season_id",
            "a"."predictor_profile_id",
            ("count"(*))::integer AS "total_pairs",
            ("count"(*) FILTER (WHERE ("sign"((("a"."predicted_value_30" - "b"."predicted_value_30"))::double precision) = ("sign"(("ta"."target" - "tb"."target")))::double precision)))::integer AS "correct_pairs"
           FROM ((("goal_predictions" "a"
             JOIN "goal_predictions" "b" ON ((("b"."season_id" = "a"."season_id") AND ("b"."predictor_profile_id" = "a"."predictor_profile_id") AND ("a"."season_player_id" < "b"."season_player_id"))))
             JOIN "target_goals" "ta" ON ((("ta"."season_id" = "a"."season_id") AND ("ta"."season_player_id" = "a"."season_player_id"))))
             JOIN "target_goals" "tb" ON ((("tb"."season_id" = "b"."season_id") AND ("tb"."season_player_id" = "b"."season_player_id"))))
          WHERE (("ta"."target" IS NOT NULL) AND ("tb"."target" IS NOT NULL))
          GROUP BY "a"."season_id", "a"."predictor_profile_id"
        )
 SELECT "ps"."season_id",
    "ps"."predictor_profile_id",
        CASE
            WHEN (("ps"."total_pairs" = 0) OR (("ps"."correct_pairs" * 2) <= "ps"."total_pairs")) THEN 0
            ELSE LEAST(("pc"."participant_count" * 30), ("round"((((("pc"."participant_count")::numeric * 30.0) * (((2 * "ps"."correct_pairs") - "ps"."total_pairs"))::numeric) / ("ps"."total_pairs")::numeric)))::integer)
        END AS "bonus_points"
   FROM ("pair_scores" "ps"
     JOIN "participant_count" "pc" ON (("pc"."season_id" = "ps"."season_id")));


ALTER VIEW "public"."v_season_prediction_bonus" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_season_prediction_flags" WITH ("security_invoker"='true') AS
 WITH "eligible_seasons" AS (
         SELECT "seasons"."id",
            "seasons"."status"
           FROM "public"."seasons"
          WHERE (("seasons"."season_predictions_locked_at" IS NOT NULL) OR ("seasons"."status" = 'archived'::"text"))
        ), "expected_predictions" AS (
         SELECT "sp"."season_id",
            "count"(*) AS "expected_count"
           FROM ("public"."season_players" "sp"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
          GROUP BY "sp"."season_id"
        ), "predictor_completion" AS (
         SELECT "sp"."season_id",
            "sp"."predictor_profile_id",
            "count"(*) FILTER (WHERE ("sp"."is_filled" AND ("sp"."category" = ANY (ARRAY['buts'::"text", 'clean_sheets'::"text"])))) AS "filled_count"
           FROM ("public"."season_predictions" "sp"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
          GROUP BY "sp"."season_id", "sp"."predictor_profile_id"
        ), "eligible_predictors" AS (
         SELECT "pc"."season_id",
            "pc"."predictor_profile_id"
           FROM ("predictor_completion" "pc"
             JOIN "expected_predictions" "ep" ON (("ep"."season_id" = "pc"."season_id")))
          WHERE (("ep"."expected_count" > 0) AND ("pc"."filled_count" = "ep"."expected_count"))
        ), "base" AS (
         SELECT "sp"."season_id",
            "sp"."predictor_profile_id",
            "sp"."season_player_id",
            "sp"."category",
            "sp"."predicted_value_30",
                CASE "sp"."category"
                    WHEN 'buts'::"text" THEN "st"."goals"
                    WHEN 'clean_sheets'::"text" THEN "st"."clean_sheets"
                    ELSE 0
                END AS "metric",
            "es"."status" AS "season_status",
            "mc"."matches_played"
           FROM (((("public"."season_predictions" "sp"
             JOIN "eligible_predictors" "ep" ON ((("ep"."season_id" = "sp"."season_id") AND ("ep"."predictor_profile_id" = "sp"."predictor_profile_id"))))
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
             JOIN "public"."v_player_season_stats" "st" ON (("st"."season_player_id" = "sp"."season_player_id")))
             LEFT JOIN "public"."v_season_match_count" "mc" ON (("mc"."season_id" = "sp"."season_id")))
          WHERE ("sp"."is_filled" AND ("sp"."category" = ANY (ARRAY['buts'::"text", 'clean_sheets'::"text"])))
        ), "targeted" AS (
         SELECT "base"."season_id",
            "base"."predictor_profile_id",
            "base"."season_player_id",
            "base"."category",
            "base"."predicted_value_30",
            "base"."metric",
            "base"."season_status",
            "base"."matches_played",
                CASE
                    WHEN ("base"."season_status" = 'archived'::"text") THEN ("base"."metric")::numeric
                    WHEN (COALESCE("base"."matches_played", 0) > 0) THEN "round"(((("base"."metric")::numeric * 30.0) / ("base"."matches_played")::numeric))
                    ELSE NULL::numeric
                END AS "target"
           FROM "base"
        ), "ranked" AS (
         SELECT "targeted"."season_id",
            "targeted"."predictor_profile_id",
            "targeted"."season_player_id",
            "targeted"."category",
            "targeted"."predicted_value_30",
            "targeted"."metric",
            "targeted"."season_status",
            "targeted"."matches_played",
            "targeted"."target",
            "rank"() OVER (PARTITION BY "targeted"."season_id", "targeted"."season_player_id", "targeted"."category" ORDER BY ("abs"((("targeted"."predicted_value_30")::numeric - "targeted"."target")))) AS "proximity_rank"
           FROM "targeted"
          WHERE ("targeted"."target" IS NOT NULL)
        )
 SELECT "season_id",
    "predictor_profile_id",
    (("proximity_rank" = 1))::integer AS "bon_pari",
    ((("predicted_value_30")::numeric = "target"))::integer AS "exact"
   FROM "ranked";


ALTER VIEW "public"."v_season_prediction_flags" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_season_prediction_points" WITH ("security_invoker"='true') AS
 WITH "eligible_seasons" AS (
         SELECT "seasons"."id",
            "seasons"."status"
           FROM "public"."seasons"
          WHERE (("seasons"."season_predictions_locked_at" IS NOT NULL) OR ("seasons"."status" = 'archived'::"text"))
        ), "expected_predictions" AS (
         SELECT "sp"."season_id",
            "count"(*) AS "expected_count"
           FROM ("public"."season_players" "sp"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
          GROUP BY "sp"."season_id"
        ), "predictor_completion" AS (
         SELECT "sp"."season_id",
            "sp"."predictor_profile_id",
            "count"(*) FILTER (WHERE ("sp"."is_filled" AND ("sp"."category" = ANY (ARRAY['buts'::"text", 'clean_sheets'::"text"])))) AS "filled_count"
           FROM ("public"."season_predictions" "sp"
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
          GROUP BY "sp"."season_id", "sp"."predictor_profile_id"
        ), "eligible_predictors" AS (
         SELECT "pc"."season_id",
            "pc"."predictor_profile_id"
           FROM ("predictor_completion" "pc"
             JOIN "expected_predictions" "ep" ON (("ep"."season_id" = "pc"."season_id")))
          WHERE (("ep"."expected_count" > 0) AND ("pc"."filled_count" = "ep"."expected_count"))
        ), "base" AS (
         SELECT "sp"."id",
            "sp"."season_id",
            "sp"."predictor_profile_id",
            "sp"."season_player_id",
            "sp"."category",
            "sp"."predicted_value_30",
                CASE "sp"."category"
                    WHEN 'buts'::"text" THEN "st"."goals"
                    WHEN 'clean_sheets'::"text" THEN "st"."clean_sheets"
                    ELSE 0
                END AS "metric",
            "es"."status" AS "season_status",
            "mc"."matches_played"
           FROM (((("public"."season_predictions" "sp"
             JOIN "eligible_predictors" "ep" ON ((("ep"."season_id" = "sp"."season_id") AND ("ep"."predictor_profile_id" = "sp"."predictor_profile_id"))))
             JOIN "eligible_seasons" "es" ON (("es"."id" = "sp"."season_id")))
             JOIN "public"."v_player_season_stats" "st" ON (("st"."season_player_id" = "sp"."season_player_id")))
             LEFT JOIN "public"."v_season_match_count" "mc" ON (("mc"."season_id" = "sp"."season_id")))
          WHERE ("sp"."is_filled" AND ("sp"."category" = ANY (ARRAY['buts'::"text", 'clean_sheets'::"text"])))
        ), "targeted" AS (
         SELECT "base"."id",
            "base"."season_id",
            "base"."predictor_profile_id",
            "base"."season_player_id",
            "base"."category",
            "base"."predicted_value_30",
            "base"."metric",
            "base"."season_status",
            "base"."matches_played",
                CASE
                    WHEN ("base"."season_status" = 'archived'::"text") THEN ("base"."metric")::numeric
                    WHEN (COALESCE("base"."matches_played", 0) > 0) THEN "round"(((("base"."metric")::numeric * 30.0) / ("base"."matches_played")::numeric))
                    ELSE NULL::numeric
                END AS "target"
           FROM "base"
        ), "ranked" AS (
         SELECT "targeted"."id",
            "targeted"."season_id",
            "targeted"."predictor_profile_id",
            "targeted"."season_player_id",
            "targeted"."category",
            "targeted"."predicted_value_30",
            "targeted"."target",
            "count"(*) OVER (PARTITION BY "targeted"."season_id", "targeted"."season_player_id", "targeted"."category") AS "participant_count",
            "rank"() OVER (PARTITION BY "targeted"."season_id", "targeted"."season_player_id", "targeted"."category" ORDER BY ("abs"((("targeted"."predicted_value_30")::numeric - "targeted"."target")))) AS "proximity_rank"
           FROM "targeted"
          WHERE ("targeted"."target" IS NOT NULL)
        )
 SELECT "id",
    "season_id",
    "predictor_profile_id",
    "season_player_id",
    "category",
    ((((("participant_count" - "proximity_rank") + 1) * 3) *
        CASE
            WHEN (("predicted_value_30")::numeric = "target") THEN 2
            ELSE 1
        END))::integer AS "points"
   FROM "ranked";


ALTER VIEW "public"."v_season_prediction_points" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_classement_general" WITH ("security_invoker"='true') AS
 WITH "match_totals" AS (
         SELECT "v_match_prediction_points"."profile_id",
            COALESCE("sum"("v_match_prediction_points"."points"), (0)::numeric) AS "match_points"
           FROM "public"."v_match_prediction_points"
          GROUP BY "v_match_prediction_points"."profile_id"
        ), "match_flags" AS (
         SELECT "v_match_prediction_flags"."profile_id",
            COALESCE("sum"("v_match_prediction_flags"."bon_pari"), (0)::bigint) AS "match_bons",
            COALESCE("sum"("v_match_prediction_flags"."exact"), (0)::bigint) AS "match_exacts"
           FROM "public"."v_match_prediction_flags"
          GROUP BY "v_match_prediction_flags"."profile_id"
        ), "season_totals" AS (
         SELECT "v_season_prediction_points"."predictor_profile_id" AS "profile_id",
            (COALESCE("sum"("v_season_prediction_points"."points"), (0)::bigint))::numeric AS "season_points"
           FROM "public"."v_season_prediction_points"
          GROUP BY "v_season_prediction_points"."predictor_profile_id"
        ), "season_bonus" AS (
         SELECT "v_season_prediction_bonus"."predictor_profile_id" AS "profile_id",
            (COALESCE("sum"("v_season_prediction_bonus"."bonus_points"), (0)::bigint))::numeric AS "bonus_points"
           FROM "public"."v_season_prediction_bonus"
          GROUP BY "v_season_prediction_bonus"."predictor_profile_id"
        ), "season_flags" AS (
         SELECT "v_season_prediction_flags"."predictor_profile_id" AS "profile_id",
            COALESCE("sum"("v_season_prediction_flags"."bon_pari"), (0)::bigint) AS "season_bons",
            COALESCE("sum"("v_season_prediction_flags"."exact"), (0)::bigint) AS "season_exacts"
           FROM "public"."v_season_prediction_flags"
          GROUP BY "v_season_prediction_flags"."predictor_profile_id"
        ), "totals" AS (
         SELECT "p"."id" AS "profile_id",
            "p"."first_name",
            "p"."surnom",
            COALESCE("mt"."match_points", (0)::numeric) AS "match_points",
            (COALESCE("st"."season_points", (0)::numeric) + COALESCE("sb"."bonus_points", (0)::numeric)) AS "season_points",
            COALESCE("mf"."match_bons", (0)::bigint) AS "match_bons",
            COALESCE("mf"."match_exacts", (0)::bigint) AS "match_exacts",
            COALESCE("sf"."season_bons", (0)::bigint) AS "season_bons",
            COALESCE("sf"."season_exacts", (0)::bigint) AS "season_exacts"
           FROM ((((("public"."profiles" "p"
             LEFT JOIN "match_totals" "mt" ON (("mt"."profile_id" = "p"."id")))
             LEFT JOIN "match_flags" "mf" ON (("mf"."profile_id" = "p"."id")))
             LEFT JOIN "season_totals" "st" ON (("st"."profile_id" = "p"."id")))
             LEFT JOIN "season_bonus" "sb" ON (("sb"."profile_id" = "p"."id")))
             LEFT JOIN "season_flags" "sf" ON (("sf"."profile_id" = "p"."id")))
          WHERE ("p"."status" = 'active'::"text")
        )
 SELECT "profile_id",
    "first_name",
    "surnom",
    "match_points",
    "season_points",
    (("match_points" * (100)::numeric) + "season_points") AS "total_points",
    "match_bons",
    "match_exacts",
    "season_bons",
    "season_exacts"
   FROM "totals";


ALTER VIEW "public"."v_classement_general" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_scorer_standings" WITH ("security_invoker"='true') AS
 SELECT "season_id",
    "season_player_id",
    "first_name",
    "last_name",
    "is_goalkeeper",
    "goals",
    "clean_sheets"
   FROM "public"."v_player_season_stats"
  WHERE "is_active";


ALTER VIEW "public"."v_scorer_standings" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_statistics_players" WITH ("security_invoker"='true') AS
 WITH "open_season" AS (
         SELECT "seasons"."id",
            "seasons"."name"
           FROM "public"."seasons"
          WHERE ("seasons"."status" = 'open'::"text")
          ORDER BY "seasons"."created_at" DESC
         LIMIT 1
        ), "prev_ref" AS (
         SELECT "s"."id",
            "s"."name"
           FROM ("public"."seasons" "s"
             CROSS JOIN "open_season" "o")
          WHERE ("s"."name" < "o"."name")
          ORDER BY "s"."name" DESC
         LIMIT 1
        ), "app_present" AS (
         SELECT "present"."match_id",
            "present"."season_player_id",
            "m"."season_id",
            "m"."score_as_grinta",
            "m"."score_adverse"
           FROM (( SELECT "match_attendance"."match_id",
                    "match_attendance"."season_player_id"
                   FROM "public"."match_attendance"
                UNION
                 SELECT "match_player_stats"."match_id",
                    "match_player_stats"."season_player_id"
                   FROM "public"."match_player_stats"
                UNION
                 SELECT "match_man_of_match"."match_id",
                    "match_man_of_match"."season_player_id"
                   FROM "public"."match_man_of_match") "present"
             JOIN "public"."matches" "m" ON ((("m"."id" = "present"."match_id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))))
        ), "app_results" AS (
         SELECT "app_present"."season_player_id",
            ("count"(*))::integer AS "matches_played",
            ("count"(*) FILTER (WHERE ("app_present"."score_as_grinta" > "app_present"."score_adverse")))::integer AS "wins",
            ("count"(*) FILTER (WHERE ("app_present"."score_as_grinta" = "app_present"."score_adverse")))::integer AS "draws",
            ("count"(*) FILTER (WHERE ("app_present"."score_as_grinta" < "app_present"."score_adverse")))::integer AS "losses",
            ("count"(*) FILTER (WHERE ("app_present"."score_adverse" = 0)))::integer AS "team_clean_sheets"
           FROM "app_present"
          GROUP BY "app_present"."season_player_id"
        ), "app_pstats" AS (
         SELECT "st"."season_player_id",
            (COALESCE("sum"("st"."goals"), (0)::bigint))::integer AS "goals",
            ("count"(*) FILTER (WHERE "st"."clean_sheet"))::integer AS "clean_sheets"
           FROM ("public"."match_player_stats" "st"
             JOIN "public"."matches" "m" ON ((("m"."id" = "st"."match_id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))))
          GROUP BY "st"."season_player_id"
        ), "app_mvp" AS (
         SELECT "mvp"."season_player_id",
            ("count"(DISTINCT "mvp"."match_id"))::integer AS "hdm"
           FROM ("public"."match_man_of_match" "mvp"
             JOIN "public"."matches" "m" ON ((("m"."id" = "mvp"."match_id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))))
          GROUP BY "mvp"."season_player_id"
        ), "app_season_player" AS (
         SELECT "sp"."season_id",
            "sp"."profile_id",
            "sp"."position" AS "display_order",
            "concat_ws"(' '::"text", "sp"."first_name", NULLIF("sp"."last_name", ''::"text")) AS "full_name",
            "sp"."is_goalkeeper",
            COALESCE("r"."matches_played", 0) AS "matches_played",
            COALESCE("r"."wins", 0) AS "wins",
            COALESCE("r"."draws", 0) AS "draws",
            COALESCE("r"."losses", 0) AS "losses",
            COALESCE("g"."goals", 0) AS "goals",
            COALESCE("mv"."hdm", 0) AS "hdm",
            COALESCE("g"."clean_sheets", 0) AS "clean_sheets",
            COALESCE("r"."team_clean_sheets", 0) AS "team_clean_sheets",
                CASE
                    WHEN "sp"."is_goalkeeper" THEN COALESCE("g"."clean_sheets", 0)
                    ELSE COALESCE("g"."goals", 0)
                END AS "ranking_metric"
           FROM ((("public"."season_players" "sp"
             LEFT JOIN "app_results" "r" ON (("r"."season_player_id" = "sp"."id")))
             LEFT JOIN "app_pstats" "g" ON (("g"."season_player_id" = "sp"."id")))
             LEFT JOIN "app_mvp" "mv" ON (("mv"."season_player_id" = "sp"."id")))
          WHERE "sp"."is_active"
        ), "prev_has_app" AS (
         SELECT (EXISTS ( SELECT 1
                   FROM ("app_season_player" "asp"
                     JOIN "prev_ref" "pr" ON (("pr"."id" = "asp"."season_id"))))) AS "has_app"
        ), "current_ranked" AS (
         SELECT 'current'::"text" AS "period_key",
            "os"."name" AS "period_label",
            ("rank"() OVER (PARTITION BY "asp"."is_goalkeeper" ORDER BY "asp"."ranking_metric" DESC))::integer AS "display_rank",
            COALESCE("asp"."display_order", 9999) AS "display_order",
            "asp"."full_name" AS "player_name",
            "asp"."is_goalkeeper",
            "asp"."matches_played",
            "asp"."wins",
            "asp"."draws",
            "asp"."losses",
            "asp"."goals",
            "asp"."hdm",
            "asp"."clean_sheets",
            "asp"."profile_id",
            "asp"."team_clean_sheets"
           FROM ("app_season_player" "asp"
             JOIN "open_season" "os" ON (("os"."id" = "asp"."season_id")))
        ), "previous_from_app" AS (
         SELECT 'previous'::"text" AS "period_key",
            "pr"."name" AS "period_label",
            ("rank"() OVER (PARTITION BY "asp"."is_goalkeeper" ORDER BY "asp"."ranking_metric" DESC))::integer AS "display_rank",
            COALESCE("asp"."display_order", 9999) AS "display_order",
            "asp"."full_name" AS "player_name",
            "asp"."is_goalkeeper",
            "asp"."matches_played",
            "asp"."wins",
            "asp"."draws",
            "asp"."losses",
            "asp"."goals",
            "asp"."hdm",
            "asp"."clean_sheets",
            "asp"."profile_id",
            "asp"."team_clean_sheets"
           FROM (("app_season_player" "asp"
             JOIN "prev_ref" "pr" ON (("pr"."id" = "asp"."season_id")))
             CROSS JOIN "prev_has_app" "ph")
          WHERE "ph"."has_app"
        ), "previous_from_import" AS (
         SELECT 'previous'::"text" AS "period_key",
            "h"."season_name" AS "period_label",
            "h"."display_rank",
            "h"."display_rank" AS "display_order",
            "h"."player_name",
            "h"."is_goalkeeper",
            "h"."matches_played",
            "h"."wins",
            "h"."draws",
            "h"."losses",
            "h"."goals",
            "h"."hdm",
            COALESCE("h"."clean_sheets", 0) AS "clean_sheets",
            "h"."profile_id",
            COALESCE("h"."team_clean_sheets", 0) AS "team_clean_sheets"
           FROM ("public"."historical_player_statistics" "h"
             CROSS JOIN "prev_has_app" "ph")
          WHERE (("h"."scope" = 'previous'::"text") AND (NOT "ph"."has_app"))
        ), "historical_all_time" AS (
         SELECT "h"."player_name",
            "h"."profile_id",
            "h"."is_goalkeeper",
            "h"."matches_played",
            "h"."wins",
            "h"."draws",
            "h"."losses",
            "h"."goals",
            "h"."hdm",
            COALESCE("h"."clean_sheets", 0) AS "clean_sheets",
            COALESCE("h"."team_clean_sheets", 0) AS "team_clean_sheets"
           FROM "public"."historical_player_statistics" "h"
          WHERE ("h"."scope" = 'all_time'::"text")
        ), "app_all" AS (
         SELECT "app_season_player"."full_name",
            "app_season_player"."is_goalkeeper",
            ("max"(("app_season_player"."profile_id")::"text"))::"uuid" AS "profile_id",
            ("sum"("app_season_player"."matches_played"))::integer AS "matches_played",
            ("sum"("app_season_player"."wins"))::integer AS "wins",
            ("sum"("app_season_player"."draws"))::integer AS "draws",
            ("sum"("app_season_player"."losses"))::integer AS "losses",
            ("sum"("app_season_player"."goals"))::integer AS "goals",
            ("sum"("app_season_player"."hdm"))::integer AS "hdm",
            ("sum"("app_season_player"."clean_sheets"))::integer AS "clean_sheets",
            ("sum"("app_season_player"."team_clean_sheets"))::integer AS "team_clean_sheets"
           FROM "app_season_player"
          GROUP BY "app_season_player"."full_name", "app_season_player"."is_goalkeeper"
         HAVING ("sum"("app_season_player"."matches_played") > 0)
        ), "all_time_combined" AS (
         SELECT COALESCE("history"."player_name", "app"."full_name") AS "player_name",
            COALESCE("history"."profile_id", "app"."profile_id") AS "profile_id",
            COALESCE("history"."is_goalkeeper", "app"."is_goalkeeper") AS "is_goalkeeper",
            (COALESCE("history"."matches_played", 0) + COALESCE("app"."matches_played", 0)) AS "matches_played",
            (COALESCE("history"."wins", 0) + COALESCE("app"."wins", 0)) AS "wins",
            (COALESCE("history"."draws", 0) + COALESCE("app"."draws", 0)) AS "draws",
            (COALESCE("history"."losses", 0) + COALESCE("app"."losses", 0)) AS "losses",
            (COALESCE("history"."goals", 0) + COALESCE("app"."goals", 0)) AS "goals",
            (COALESCE("history"."hdm", 0) + COALESCE("app"."hdm", 0)) AS "hdm",
            (COALESCE("history"."clean_sheets", 0) + COALESCE("app"."clean_sheets", 0)) AS "clean_sheets",
            (COALESCE("history"."team_clean_sheets", 0) + COALESCE("app"."team_clean_sheets", 0)) AS "team_clean_sheets"
           FROM ("historical_all_time" "history"
             FULL JOIN "app_all" "app" ON ((("lower"("btrim"("history"."player_name")) = "lower"("btrim"("app"."full_name"))) AND ("history"."is_goalkeeper" = "app"."is_goalkeeper"))))
        ), "all_time_ranked" AS (
         SELECT 'all_time'::"text" AS "period_key",
            'Toutes saisons'::"text" AS "period_label",
            ("rank"() OVER (PARTITION BY "all_time_combined"."is_goalkeeper" ORDER BY "all_time_combined"."matches_played" DESC, "all_time_combined"."goals" DESC, "all_time_combined"."player_name"))::integer AS "display_rank",
            ("rank"() OVER (PARTITION BY "all_time_combined"."is_goalkeeper" ORDER BY "all_time_combined"."matches_played" DESC, "all_time_combined"."goals" DESC, "all_time_combined"."player_name"))::integer AS "display_order",
            "all_time_combined"."player_name",
            "all_time_combined"."is_goalkeeper",
            "all_time_combined"."matches_played",
            "all_time_combined"."wins",
            "all_time_combined"."draws",
            "all_time_combined"."losses",
            "all_time_combined"."goals",
            "all_time_combined"."hdm",
            "all_time_combined"."clean_sheets",
            "all_time_combined"."profile_id",
            "all_time_combined"."team_clean_sheets"
           FROM "all_time_combined"
        )
 SELECT "current_ranked"."period_key",
    "current_ranked"."period_label",
    "current_ranked"."display_rank",
    "current_ranked"."display_order",
    "current_ranked"."player_name",
    "current_ranked"."is_goalkeeper",
    "current_ranked"."matches_played",
    "current_ranked"."wins",
    "current_ranked"."draws",
    "current_ranked"."losses",
    "current_ranked"."goals",
    "current_ranked"."hdm",
    "current_ranked"."clean_sheets",
    "current_ranked"."profile_id",
    "current_ranked"."team_clean_sheets"
   FROM "current_ranked"
UNION ALL
 SELECT "previous_from_app"."period_key",
    "previous_from_app"."period_label",
    "previous_from_app"."display_rank",
    "previous_from_app"."display_order",
    "previous_from_app"."player_name",
    "previous_from_app"."is_goalkeeper",
    "previous_from_app"."matches_played",
    "previous_from_app"."wins",
    "previous_from_app"."draws",
    "previous_from_app"."losses",
    "previous_from_app"."goals",
    "previous_from_app"."hdm",
    "previous_from_app"."clean_sheets",
    "previous_from_app"."profile_id",
    "previous_from_app"."team_clean_sheets"
   FROM "previous_from_app"
UNION ALL
 SELECT "previous_from_import"."period_key",
    "previous_from_import"."period_label",
    "previous_from_import"."display_rank",
    "previous_from_import"."display_order",
    "previous_from_import"."player_name",
    "previous_from_import"."is_goalkeeper",
    "previous_from_import"."matches_played",
    "previous_from_import"."wins",
    "previous_from_import"."draws",
    "previous_from_import"."losses",
    "previous_from_import"."goals",
    "previous_from_import"."hdm",
    "previous_from_import"."clean_sheets",
    "previous_from_import"."profile_id",
    "previous_from_import"."team_clean_sheets"
   FROM "previous_from_import"
UNION ALL
 SELECT "all_time_ranked"."period_key",
    "all_time_ranked"."period_label",
    "all_time_ranked"."display_rank",
    "all_time_ranked"."display_order",
    "all_time_ranked"."player_name",
    "all_time_ranked"."is_goalkeeper",
    "all_time_ranked"."matches_played",
    "all_time_ranked"."wins",
    "all_time_ranked"."draws",
    "all_time_ranked"."losses",
    "all_time_ranked"."goals",
    "all_time_ranked"."hdm",
    "all_time_ranked"."clean_sheets",
    "all_time_ranked"."profile_id",
    "all_time_ranked"."team_clean_sheets"
   FROM "all_time_ranked";


ALTER VIEW "public"."v_statistics_players" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_statistics_players" IS 'Statistiques joueurs Actuelle/Précédente/Toutes, toujours nommés par leur vrai prénom (jamais leur surnom). team_clean_sheets compte les matchs joués avec score_adverse = 0, indépendamment du clean sheet gardien.';



CREATE OR REPLACE VIEW "public"."v_statistics_team_dynamic_base" WITH ("security_invoker"='true') AS
 WITH "open_season" AS (
         SELECT "seasons"."id",
            "seasons"."name"
           FROM "public"."seasons"
          WHERE ("seasons"."status" = 'open'::"text")
          ORDER BY "seasons"."created_at" DESC
         LIMIT 1
        ), "previous_season" AS (
         SELECT "s"."id",
            "s"."name"
           FROM ("public"."seasons" "s"
             CROSS JOIN "open_season" "current")
          WHERE ("s"."name" < "current"."name")
          ORDER BY "s"."name" DESC
         LIMIT 1
        ), "baseline" AS (
         SELECT "historical_team_statistics"."scope",
            "historical_team_statistics"."through_season",
            "historical_team_statistics"."matches_played",
            "historical_team_statistics"."wins",
            "historical_team_statistics"."draws",
            "historical_team_statistics"."losses",
            "historical_team_statistics"."goals_for",
            "historical_team_statistics"."goals_against",
            "historical_team_statistics"."best_win_streak",
            "historical_team_statistics"."best_win_start",
            "historical_team_statistics"."best_win_end",
            "historical_team_statistics"."best_unbeaten_streak",
            "historical_team_statistics"."best_unbeaten_start",
            "historical_team_statistics"."best_unbeaten_end",
            "historical_team_statistics"."worst_loss_streak",
            "historical_team_statistics"."worst_loss_start",
            "historical_team_statistics"."worst_loss_end",
            "historical_team_statistics"."worst_winless_streak",
            "historical_team_statistics"."worst_winless_start",
            "historical_team_statistics"."worst_winless_end",
            "historical_team_statistics"."updated_at"
           FROM "public"."historical_team_statistics"
          WHERE ("historical_team_statistics"."scope" = 'all_time'::"text")
        ), "scored_matches" AS (
         SELECT "m"."id",
            "m"."season_id",
            "s"."name" AS "season_name",
            "m"."match_date",
            "m"."score_as_grinta" AS "goals_for",
            "m"."score_adverse" AS "goals_against",
            ("m"."score_as_grinta" - "m"."score_adverse") AS "margin",
                CASE
                    WHEN ("m"."score_as_grinta" > "m"."score_adverse") THEN 'V'::"text"
                    WHEN ("m"."score_as_grinta" = "m"."score_adverse") THEN 'N'::"text"
                    ELSE 'D'::"text"
                END AS "result"
           FROM ("public"."matches" "m"
             JOIN "public"."seasons" "s" ON (("s"."id" = "m"."season_id")))
          WHERE (("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])) AND ("m"."score_as_grinta" IS NOT NULL) AND ("m"."score_adverse" IS NOT NULL))
        ), "period_refs" AS (
         SELECT 'current'::"text" AS "period_key",
            "current"."id" AS "season_id",
            "current"."name" AS "period_label"
           FROM "open_season" "current"
        UNION ALL
         SELECT 'previous'::"text" AS "text",
            "previous"."id",
            "previous"."name"
           FROM "previous_season" "previous"
        ), "period_totals" AS (
         SELECT "refs"."period_key",
            "refs"."period_label",
            ("count"("matches"."id"))::integer AS "matches_played",
            ("count"(*) FILTER (WHERE ("matches"."result" = 'V'::"text")))::integer AS "wins",
            ("count"(*) FILTER (WHERE ("matches"."result" = 'N'::"text")))::integer AS "draws",
            ("count"(*) FILTER (WHERE ("matches"."result" = 'D'::"text")))::integer AS "losses",
            (COALESCE("sum"("matches"."goals_for"), (0)::bigint))::integer AS "goals_for",
            (COALESCE("sum"("matches"."goals_against"), (0)::bigint))::integer AS "goals_against"
           FROM ("period_refs" "refs"
             LEFT JOIN "scored_matches" "matches" ON (("matches"."season_id" = "refs"."season_id")))
          GROUP BY "refs"."period_key", "refs"."period_label"
        ), "period_recent_ranked" AS (
         SELECT "refs"."period_key",
            "matches"."result",
            "matches"."match_date",
            "matches"."id",
            "row_number"() OVER (PARTITION BY "refs"."period_key" ORDER BY "matches"."match_date" DESC, "matches"."id" DESC) AS "recent_rank"
           FROM ("period_refs" "refs"
             JOIN "scored_matches" "matches" ON (("matches"."season_id" = "refs"."season_id")))
        ), "period_recent" AS (
         SELECT "period_recent_ranked"."period_key",
            "array_agg"("period_recent_ranked"."result" ORDER BY "period_recent_ranked"."match_date", "period_recent_ranked"."id") AS "recent_results"
           FROM "period_recent_ranked"
          WHERE ("period_recent_ranked"."recent_rank" <= 6)
          GROUP BY "period_recent_ranked"."period_key"
        ), "period_margin_counts" AS (
         SELECT "refs"."period_key",
            "matches"."margin",
            ("count"(*))::integer AS "match_count"
           FROM ("period_refs" "refs"
             JOIN "scored_matches" "matches" ON (("matches"."season_id" = "refs"."season_id")))
          GROUP BY "refs"."period_key", "matches"."margin"
        ), "period_margins" AS (
         SELECT "period_margin_counts"."period_key",
            "jsonb_object_agg"(("period_margin_counts"."margin")::"text", "period_margin_counts"."match_count" ORDER BY "period_margin_counts"."margin") AS "distribution"
           FROM "period_margin_counts"
          GROUP BY "period_margin_counts"."period_key"
        ), "period_streak_expanded" AS (
         SELECT "refs"."period_key",
            "matches"."id",
            "matches"."match_date",
            "streak"."kind",
            "streak"."qualifies",
            "sum"(
                CASE
                    WHEN "streak"."qualifies" THEN 0
                    ELSE 1
                END) OVER (PARTITION BY "refs"."period_key", "streak"."kind" ORDER BY "matches"."match_date", "matches"."id") AS "streak_group"
           FROM (("period_refs" "refs"
             JOIN "scored_matches" "matches" ON (("matches"."season_id" = "refs"."season_id")))
             CROSS JOIN LATERAL ( VALUES ('win'::"text",("matches"."result" = 'V'::"text")), ('unbeaten'::"text",("matches"."result" <> 'D'::"text")), ('loss'::"text",("matches"."result" = 'D'::"text")), ('winless'::"text",("matches"."result" <> 'V'::"text"))) "streak"("kind", "qualifies"))
        ), "period_streaks" AS (
         SELECT "period_streak_expanded"."period_key",
            "period_streak_expanded"."kind",
            ("count"(*))::integer AS "streak_length",
            "min"("period_streak_expanded"."match_date") AS "start_date",
            "max"("period_streak_expanded"."match_date") AS "end_date"
           FROM "period_streak_expanded"
          WHERE "period_streak_expanded"."qualifies"
          GROUP BY "period_streak_expanded"."period_key", "period_streak_expanded"."kind", "period_streak_expanded"."streak_group"
        ), "period_streak_ranked" AS (
         SELECT "period_streaks"."period_key",
            "period_streaks"."kind",
            "period_streaks"."streak_length",
            "period_streaks"."start_date",
            "period_streaks"."end_date",
            "row_number"() OVER (PARTITION BY "period_streaks"."period_key", "period_streaks"."kind" ORDER BY "period_streaks"."streak_length" DESC, "period_streaks"."end_date" DESC) AS "streak_rank"
           FROM "period_streaks"
        ), "period_streak_summary" AS (
         SELECT "period_streak_ranked"."period_key",
            COALESCE("max"("period_streak_ranked"."streak_length") FILTER (WHERE (("period_streak_ranked"."kind" = 'win'::"text") AND ("period_streak_ranked"."streak_rank" = 1))), 0) AS "best_win_streak",
            "max"("period_streak_ranked"."start_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'win'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "best_win_start",
            "max"("period_streak_ranked"."end_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'win'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "best_win_end",
            COALESCE("max"("period_streak_ranked"."streak_length") FILTER (WHERE (("period_streak_ranked"."kind" = 'unbeaten'::"text") AND ("period_streak_ranked"."streak_rank" = 1))), 0) AS "best_unbeaten_streak",
            "max"("period_streak_ranked"."start_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'unbeaten'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "best_unbeaten_start",
            "max"("period_streak_ranked"."end_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'unbeaten'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "best_unbeaten_end",
            COALESCE("max"("period_streak_ranked"."streak_length") FILTER (WHERE (("period_streak_ranked"."kind" = 'loss'::"text") AND ("period_streak_ranked"."streak_rank" = 1))), 0) AS "worst_loss_streak",
            "max"("period_streak_ranked"."start_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'loss'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "worst_loss_start",
            "max"("period_streak_ranked"."end_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'loss'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "worst_loss_end",
            COALESCE("max"("period_streak_ranked"."streak_length") FILTER (WHERE (("period_streak_ranked"."kind" = 'winless'::"text") AND ("period_streak_ranked"."streak_rank" = 1))), 0) AS "worst_winless_streak",
            "max"("period_streak_ranked"."start_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'winless'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "worst_winless_start",
            "max"("period_streak_ranked"."end_date") FILTER (WHERE (("period_streak_ranked"."kind" = 'winless'::"text") AND ("period_streak_ranked"."streak_rank" = 1))) AS "worst_winless_end"
           FROM "period_streak_ranked"
          GROUP BY "period_streak_ranked"."period_key"
        ), "dynamic_periods" AS (
         SELECT "totals"."period_key",
            "totals"."period_label",
            "totals"."matches_played",
            "totals"."wins",
            "totals"."draws",
            "totals"."losses",
            "totals"."goals_for",
            "totals"."goals_against",
            ("totals"."goals_for" - "totals"."goals_against") AS "goal_difference",
            0 AS "clean_sheets",
            COALESCE("recent"."recent_results", ARRAY[]::"text"[]) AS "recent_results",
            "margins"."distribution" AS "score_margin_distribution",
            COALESCE("streaks"."best_win_streak", 0) AS "best_win_streak",
            "streaks"."best_win_start",
            "streaks"."best_win_end",
            COALESCE("streaks"."best_unbeaten_streak", 0) AS "best_unbeaten_streak",
            "streaks"."best_unbeaten_start",
            "streaks"."best_unbeaten_end",
            COALESCE("streaks"."worst_loss_streak", 0) AS "worst_loss_streak",
            "streaks"."worst_loss_start",
            "streaks"."worst_loss_end",
            COALESCE("streaks"."worst_winless_streak", 0) AS "worst_winless_streak",
            "streaks"."worst_winless_start",
            "streaks"."worst_winless_end"
           FROM ((("period_totals" "totals"
             LEFT JOIN "period_recent" "recent" USING ("period_key"))
             LEFT JOIN "period_margins" "margins" USING ("period_key"))
             LEFT JOIN "period_streak_summary" "streaks" USING ("period_key"))
        ), "post_baseline_matches" AS (
         SELECT "matches"."id",
            "matches"."season_id",
            "matches"."season_name",
            "matches"."match_date",
            "matches"."goals_for",
            "matches"."goals_against",
            "matches"."margin",
            "matches"."result"
           FROM ("scored_matches" "matches"
             CROSS JOIN "baseline" "history")
          WHERE ("matches"."season_name" > "history"."through_season")
        ), "all_time_sequence" AS (
         SELECT "matches"."id",
            "matches"."season_id",
            "matches"."season_name",
            "matches"."match_date",
            "matches"."goals_for",
            "matches"."goals_against",
            "matches"."margin",
            "matches"."result"
           FROM ("scored_matches" "matches"
             CROSS JOIN "baseline" "history")
          WHERE ("matches"."season_name" >= "history"."through_season")
        ), "all_time_totals" AS (
         SELECT ("history"."matches_played" + ("count"("matches"."id"))::integer) AS "matches_played",
            ("history"."wins" + ("count"(*) FILTER (WHERE ("matches"."result" = 'V'::"text")))::integer) AS "wins",
            ("history"."draws" + ("count"(*) FILTER (WHERE ("matches"."result" = 'N'::"text")))::integer) AS "draws",
            ("history"."losses" + ("count"(*) FILTER (WHERE ("matches"."result" = 'D'::"text")))::integer) AS "losses",
            ("history"."goals_for" + (COALESCE("sum"("matches"."goals_for"), (0)::bigint))::integer) AS "goals_for",
            ("history"."goals_against" + (COALESCE("sum"("matches"."goals_against"), (0)::bigint))::integer) AS "goals_against"
           FROM ("baseline" "history"
             LEFT JOIN "post_baseline_matches" "matches" ON (true))
          GROUP BY "history"."matches_played", "history"."wins", "history"."draws", "history"."losses", "history"."goals_for", "history"."goals_against"
        ), "all_time_recent_ranked" AS (
         SELECT "all_time_sequence"."result",
            "all_time_sequence"."match_date",
            "all_time_sequence"."id",
            "row_number"() OVER (ORDER BY "all_time_sequence"."match_date" DESC, "all_time_sequence"."id" DESC) AS "recent_rank"
           FROM "all_time_sequence"
        ), "all_time_recent" AS (
         SELECT "array_agg"("all_time_recent_ranked"."result" ORDER BY "all_time_recent_ranked"."match_date", "all_time_recent_ranked"."id") AS "recent_results"
           FROM "all_time_recent_ranked"
          WHERE ("all_time_recent_ranked"."recent_rank" <= 6)
        ), "all_time_streak_expanded" AS (
         SELECT "matches"."id",
            "matches"."match_date",
            "streak"."kind",
            "streak"."qualifies",
            "sum"(
                CASE
                    WHEN "streak"."qualifies" THEN 0
                    ELSE 1
                END) OVER (PARTITION BY "streak"."kind" ORDER BY "matches"."match_date", "matches"."id") AS "streak_group"
           FROM ("all_time_sequence" "matches"
             CROSS JOIN LATERAL ( VALUES ('win'::"text",("matches"."result" = 'V'::"text")), ('unbeaten'::"text",("matches"."result" <> 'D'::"text")), ('loss'::"text",("matches"."result" = 'D'::"text")), ('winless'::"text",("matches"."result" <> 'V'::"text"))) "streak"("kind", "qualifies"))
        ), "all_time_streaks" AS (
         SELECT "all_time_streak_expanded"."kind",
            ("count"(*))::integer AS "streak_length",
            "min"("all_time_streak_expanded"."match_date") AS "start_date",
            "max"("all_time_streak_expanded"."match_date") AS "end_date"
           FROM "all_time_streak_expanded"
          WHERE "all_time_streak_expanded"."qualifies"
          GROUP BY "all_time_streak_expanded"."kind", "all_time_streak_expanded"."streak_group"
        ), "all_time_streak_ranked" AS (
         SELECT "all_time_streaks"."kind",
            "all_time_streaks"."streak_length",
            "all_time_streaks"."start_date",
            "all_time_streaks"."end_date",
            "row_number"() OVER (PARTITION BY "all_time_streaks"."kind" ORDER BY "all_time_streaks"."streak_length" DESC, "all_time_streaks"."end_date" DESC) AS "streak_rank"
           FROM "all_time_streaks"
        ), "all_time_dynamic_streaks" AS (
         SELECT COALESCE("max"("all_time_streak_ranked"."streak_length") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'win'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))), 0) AS "best_win_streak",
            "max"("all_time_streak_ranked"."start_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'win'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "best_win_start",
            "max"("all_time_streak_ranked"."end_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'win'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "best_win_end",
            COALESCE("max"("all_time_streak_ranked"."streak_length") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'unbeaten'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))), 0) AS "best_unbeaten_streak",
            "max"("all_time_streak_ranked"."start_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'unbeaten'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "best_unbeaten_start",
            "max"("all_time_streak_ranked"."end_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'unbeaten'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "best_unbeaten_end",
            COALESCE("max"("all_time_streak_ranked"."streak_length") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'loss'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))), 0) AS "worst_loss_streak",
            "max"("all_time_streak_ranked"."start_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'loss'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "worst_loss_start",
            "max"("all_time_streak_ranked"."end_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'loss'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "worst_loss_end",
            COALESCE("max"("all_time_streak_ranked"."streak_length") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'winless'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))), 0) AS "worst_winless_streak",
            "max"("all_time_streak_ranked"."start_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'winless'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "worst_winless_start",
            "max"("all_time_streak_ranked"."end_date") FILTER (WHERE (("all_time_streak_ranked"."kind" = 'winless'::"text") AND ("all_time_streak_ranked"."streak_rank" = 1))) AS "worst_winless_end"
           FROM "all_time_streak_ranked"
        ), "all_time_period" AS (
         SELECT 'all_time'::"text" AS "period_key",
            'Toutes saisons'::"text" AS "period_label",
            "totals"."matches_played",
            "totals"."wins",
            "totals"."draws",
            "totals"."losses",
            "totals"."goals_for",
            "totals"."goals_against",
            ("totals"."goals_for" - "totals"."goals_against") AS "goal_difference",
            0 AS "clean_sheets",
            COALESCE("recent"."recent_results", ARRAY[]::"text"[]) AS "recent_results",
            NULL::"jsonb" AS "score_margin_distribution",
                CASE
                    WHEN ("dynamic"."best_win_streak" > "history"."best_win_streak") THEN "dynamic"."best_win_streak"
                    ELSE "history"."best_win_streak"
                END AS "best_win_streak",
                CASE
                    WHEN ("dynamic"."best_win_streak" > "history"."best_win_streak") THEN "dynamic"."best_win_start"
                    ELSE "history"."best_win_start"
                END AS "best_win_start",
                CASE
                    WHEN ("dynamic"."best_win_streak" > "history"."best_win_streak") THEN "dynamic"."best_win_end"
                    ELSE "history"."best_win_end"
                END AS "best_win_end",
                CASE
                    WHEN ("dynamic"."best_unbeaten_streak" > "history"."best_unbeaten_streak") THEN "dynamic"."best_unbeaten_streak"
                    ELSE "history"."best_unbeaten_streak"
                END AS "best_unbeaten_streak",
                CASE
                    WHEN ("dynamic"."best_unbeaten_streak" > "history"."best_unbeaten_streak") THEN "dynamic"."best_unbeaten_start"
                    ELSE "history"."best_unbeaten_start"
                END AS "best_unbeaten_start",
                CASE
                    WHEN ("dynamic"."best_unbeaten_streak" > "history"."best_unbeaten_streak") THEN "dynamic"."best_unbeaten_end"
                    ELSE "history"."best_unbeaten_end"
                END AS "best_unbeaten_end",
                CASE
                    WHEN ("dynamic"."worst_loss_streak" > "history"."worst_loss_streak") THEN "dynamic"."worst_loss_streak"
                    ELSE "history"."worst_loss_streak"
                END AS "worst_loss_streak",
                CASE
                    WHEN ("dynamic"."worst_loss_streak" > "history"."worst_loss_streak") THEN "dynamic"."worst_loss_start"
                    ELSE "history"."worst_loss_start"
                END AS "worst_loss_start",
                CASE
                    WHEN ("dynamic"."worst_loss_streak" > "history"."worst_loss_streak") THEN "dynamic"."worst_loss_end"
                    ELSE "history"."worst_loss_end"
                END AS "worst_loss_end",
                CASE
                    WHEN ("dynamic"."worst_winless_streak" > "history"."worst_winless_streak") THEN "dynamic"."worst_winless_streak"
                    ELSE "history"."worst_winless_streak"
                END AS "worst_winless_streak",
                CASE
                    WHEN ("dynamic"."worst_winless_streak" > "history"."worst_winless_streak") THEN "dynamic"."worst_winless_start"
                    ELSE "history"."worst_winless_start"
                END AS "worst_winless_start",
                CASE
                    WHEN ("dynamic"."worst_winless_streak" > "history"."worst_winless_streak") THEN "dynamic"."worst_winless_end"
                    ELSE "history"."worst_winless_end"
                END AS "worst_winless_end"
           FROM ((("all_time_totals" "totals"
             CROSS JOIN "baseline" "history")
             CROSS JOIN "all_time_recent" "recent")
             CROSS JOIN "all_time_dynamic_streaks" "dynamic")
        )
 SELECT "dynamic_periods"."period_key",
    "dynamic_periods"."period_label",
    "dynamic_periods"."matches_played",
    "dynamic_periods"."wins",
    "dynamic_periods"."draws",
    "dynamic_periods"."losses",
    "dynamic_periods"."goals_for",
    "dynamic_periods"."goals_against",
    "dynamic_periods"."goal_difference",
    "dynamic_periods"."clean_sheets",
    "dynamic_periods"."recent_results",
    "dynamic_periods"."score_margin_distribution",
    "dynamic_periods"."best_win_streak",
    "dynamic_periods"."best_win_start",
    "dynamic_periods"."best_win_end",
    "dynamic_periods"."best_unbeaten_streak",
    "dynamic_periods"."best_unbeaten_start",
    "dynamic_periods"."best_unbeaten_end",
    "dynamic_periods"."worst_loss_streak",
    "dynamic_periods"."worst_loss_start",
    "dynamic_periods"."worst_loss_end",
    "dynamic_periods"."worst_winless_streak",
    "dynamic_periods"."worst_winless_start",
    "dynamic_periods"."worst_winless_end"
   FROM "dynamic_periods"
UNION ALL
 SELECT "all_time_period"."period_key",
    "all_time_period"."period_label",
    "all_time_period"."matches_played",
    "all_time_period"."wins",
    "all_time_period"."draws",
    "all_time_period"."losses",
    "all_time_period"."goals_for",
    "all_time_period"."goals_against",
    "all_time_period"."goal_difference",
    "all_time_period"."clean_sheets",
    "all_time_period"."recent_results",
    "all_time_period"."score_margin_distribution",
    "all_time_period"."best_win_streak",
    "all_time_period"."best_win_start",
    "all_time_period"."best_win_end",
    "all_time_period"."best_unbeaten_streak",
    "all_time_period"."best_unbeaten_start",
    "all_time_period"."best_unbeaten_end",
    "all_time_period"."worst_loss_streak",
    "all_time_period"."worst_loss_start",
    "all_time_period"."worst_loss_end",
    "all_time_period"."worst_winless_streak",
    "all_time_period"."worst_winless_start",
    "all_time_period"."worst_winless_end"
   FROM "all_time_period";


ALTER VIEW "public"."v_statistics_team_dynamic_base" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_statistics_team_with_recent_results" WITH ("security_invoker"='true') AS
 WITH "open_season" AS (
         SELECT "seasons"."id",
            "seasons"."name"
           FROM "public"."seasons"
          WHERE ("seasons"."status" = 'open'::"text")
          ORDER BY "seasons"."created_at" DESC
         LIMIT 1
        ), "previous_season" AS (
         SELECT "season"."id",
            "season"."name"
           FROM ("public"."seasons" "season"
             CROSS JOIN "open_season" "current")
          WHERE ("season"."name" < "current"."name")
          ORDER BY "season"."name" DESC
         LIMIT 1
        ), "previous_has_app_roster" AS (
         SELECT (EXISTS ( SELECT 1
                   FROM ("public"."season_players" "player"
                     JOIN "previous_season" "previous" ON (("previous"."id" = "player"."season_id"))))) AS "has_app"
        ), "imported_previous" AS (
         SELECT 'previous'::"text" AS "period_key",
            "history"."through_season" AS "period_label",
            "history"."matches_played",
            "history"."wins",
            "history"."draws",
            "history"."losses",
            "history"."goals_for",
            "history"."goals_against",
            ("history"."goals_for" - "history"."goals_against") AS "goal_difference",
            0 AS "clean_sheets",
            "history"."recent_results",
            "history"."score_margin_distribution",
            "history"."best_win_streak",
            "history"."best_win_start",
            "history"."best_win_end",
            "history"."best_unbeaten_streak",
            "history"."best_unbeaten_start",
            "history"."best_unbeaten_end",
            "history"."worst_loss_streak",
            "history"."worst_loss_start",
            "history"."worst_loss_end",
            "history"."worst_winless_streak",
            "history"."worst_winless_start",
            "history"."worst_winless_end"
           FROM ("public"."historical_team_statistics" "history"
             CROSS JOIN "previous_has_app_roster" "app")
          WHERE (("history"."scope" = 'previous'::"text") AND (NOT "app"."has_app"))
        )
 SELECT "dynamic"."period_key",
    "dynamic"."period_label",
    "dynamic"."matches_played",
    "dynamic"."wins",
    "dynamic"."draws",
    "dynamic"."losses",
    "dynamic"."goals_for",
    "dynamic"."goals_against",
    "dynamic"."goal_difference",
    "dynamic"."clean_sheets",
    "dynamic"."recent_results",
    "dynamic"."score_margin_distribution",
    "dynamic"."best_win_streak",
    "dynamic"."best_win_start",
    "dynamic"."best_win_end",
    "dynamic"."best_unbeaten_streak",
    "dynamic"."best_unbeaten_start",
    "dynamic"."best_unbeaten_end",
    "dynamic"."worst_loss_streak",
    "dynamic"."worst_loss_start",
    "dynamic"."worst_loss_end",
    "dynamic"."worst_winless_streak",
    "dynamic"."worst_winless_start",
    "dynamic"."worst_winless_end"
   FROM "public"."v_statistics_team_dynamic_base" "dynamic"
  WHERE ("dynamic"."period_key" = ANY (ARRAY['current'::"text", 'all_time'::"text"]))
UNION ALL
 SELECT "dynamic"."period_key",
    "dynamic"."period_label",
    "dynamic"."matches_played",
    "dynamic"."wins",
    "dynamic"."draws",
    "dynamic"."losses",
    "dynamic"."goals_for",
    "dynamic"."goals_against",
    "dynamic"."goal_difference",
    "dynamic"."clean_sheets",
    "dynamic"."recent_results",
    "dynamic"."score_margin_distribution",
    "dynamic"."best_win_streak",
    "dynamic"."best_win_start",
    "dynamic"."best_win_end",
    "dynamic"."best_unbeaten_streak",
    "dynamic"."best_unbeaten_start",
    "dynamic"."best_unbeaten_end",
    "dynamic"."worst_loss_streak",
    "dynamic"."worst_loss_start",
    "dynamic"."worst_loss_end",
    "dynamic"."worst_winless_streak",
    "dynamic"."worst_winless_start",
    "dynamic"."worst_winless_end"
   FROM ("public"."v_statistics_team_dynamic_base" "dynamic"
     CROSS JOIN "previous_has_app_roster" "app")
  WHERE (("dynamic"."period_key" = 'previous'::"text") AND "app"."has_app")
UNION ALL
 SELECT "imported"."period_key",
    "imported"."period_label",
    "imported"."matches_played",
    "imported"."wins",
    "imported"."draws",
    "imported"."losses",
    "imported"."goals_for",
    "imported"."goals_against",
    "imported"."goal_difference",
    "imported"."clean_sheets",
    "imported"."recent_results",
    "imported"."score_margin_distribution",
    "imported"."best_win_streak",
    "imported"."best_win_start",
    "imported"."best_win_end",
    "imported"."best_unbeaten_streak",
    "imported"."best_unbeaten_start",
    "imported"."best_unbeaten_end",
    "imported"."worst_loss_streak",
    "imported"."worst_loss_start",
    "imported"."worst_loss_end",
    "imported"."worst_winless_streak",
    "imported"."worst_winless_start",
    "imported"."worst_winless_end"
   FROM "imported_previous" "imported";


ALTER VIEW "public"."v_statistics_team_with_recent_results" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_statistics_team" WITH ("security_invoker"='true') AS
 WITH "baseline" AS (
         SELECT "historical_team_statistics"."through_season",
            "historical_team_statistics"."recent_results",
            "historical_team_statistics"."score_margin_distribution"
           FROM "public"."historical_team_statistics"
          WHERE ("historical_team_statistics"."scope" = 'all_time'::"text")
        ), "post_baseline" AS (
         SELECT "m"."id",
            "m"."match_date",
                CASE
                    WHEN ("m"."score_as_grinta" > "m"."score_adverse") THEN 'V'::"text"
                    WHEN ("m"."score_as_grinta" = "m"."score_adverse") THEN 'N'::"text"
                    ELSE 'D'::"text"
                END AS "result",
            ("m"."score_as_grinta" - "m"."score_adverse") AS "margin"
           FROM (("public"."matches" "m"
             JOIN "public"."seasons" "s" ON (("s"."id" = "m"."season_id")))
             CROSS JOIN "baseline" "b")
          WHERE (("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])) AND ("m"."score_as_grinta" IS NOT NULL) AND ("m"."score_adverse" IS NOT NULL) AND ("s"."name" > "b"."through_season"))
        ), "post_ranked" AS (
         SELECT "post_baseline"."id",
            "post_baseline"."match_date",
            "post_baseline"."result",
            "post_baseline"."margin",
            "row_number"() OVER (ORDER BY "post_baseline"."match_date" DESC, "post_baseline"."id" DESC) AS "rn"
           FROM "post_baseline"
        ), "post_recent" AS (
         SELECT COALESCE("array_agg"("post_ranked"."result" ORDER BY "post_ranked"."match_date", "post_ranked"."id") FILTER (WHERE ("post_ranked"."rn" <= 6)), ARRAY[]::"text"[]) AS "results",
            ("count"(*))::integer AS "total_count"
           FROM "post_ranked"
        ), "recent_all_time" AS (
         SELECT
                CASE
                    WHEN ("p"."total_count" >= 6) THEN "p"."results"
                    ELSE (COALESCE("b"."recent_results"[GREATEST(((COALESCE("array_length"("b"."recent_results", 1), 0) - (6 - "p"."total_count")) + 1), 1):COALESCE("array_length"("b"."recent_results", 1), 0)], ARRAY[]::"text"[]) || "p"."results")
                END AS "results"
           FROM ("baseline" "b"
             CROSS JOIN "post_recent" "p")
        ), "margin_parts" AS (
         SELECT ("jsonb_each_text"."key")::integer AS "margin",
            ("jsonb_each_text"."value")::integer AS "cnt"
           FROM "baseline" "b",
            LATERAL "jsonb_each_text"(COALESCE("b"."score_margin_distribution", '{}'::"jsonb")) "jsonb_each_text"("key", "value")
        UNION ALL
         SELECT "post_baseline"."margin",
            ("count"(*))::integer AS "count"
           FROM "post_baseline"
          GROUP BY "post_baseline"."margin"
        ), "all_time_margins" AS (
         SELECT COALESCE("jsonb_object_agg"(("x"."margin")::"text", "x"."cnt" ORDER BY "x"."margin"), '{}'::"jsonb") AS "distribution"
           FROM ( SELECT "margin_parts"."margin",
                    ("sum"("margin_parts"."cnt"))::integer AS "cnt"
                   FROM "margin_parts"
                  GROUP BY "margin_parts"."margin") "x"
        )
 SELECT "period_key",
    "period_label",
    "matches_played",
    "wins",
    "draws",
    "losses",
    "goals_for",
    "goals_against",
    "goal_difference",
    "clean_sheets",
        CASE
            WHEN ("period_key" = 'previous'::"text") THEN ARRAY[]::"text"[]
            WHEN ("period_key" = 'all_time'::"text") THEN ( SELECT "recent_all_time"."results"
               FROM "recent_all_time")
            ELSE "recent_results"
        END AS "recent_results",
        CASE
            WHEN ("period_key" = 'all_time'::"text") THEN ( SELECT "all_time_margins"."distribution"
               FROM "all_time_margins")
            ELSE "score_margin_distribution"
        END AS "score_margin_distribution",
    "best_win_streak",
    "best_win_start",
    "best_win_end",
    "best_unbeaten_streak",
    "best_unbeaten_start",
    "best_unbeaten_end",
    "worst_loss_streak",
    "worst_loss_start",
    "worst_loss_end",
    "worst_winless_streak",
    "worst_winless_start",
    "worst_winless_end"
   FROM "public"."v_statistics_team_with_recent_results" "source";


ALTER VIEW "public"."v_statistics_team" OWNER TO "postgres";


ALTER TABLE ONLY "private"."app_feature_flag_audit"
    ADD CONSTRAINT "app_feature_flag_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."app_feature_flags"
    ADD CONSTRAINT "app_feature_flags_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "private"."prediction_reminder_cron_config"
    ADD CONSTRAINT "prediction_reminder_cron_config_pkey" PRIMARY KEY ("singleton");



ALTER TABLE ONLY "private"."registration_attempts"
    ADD CONSTRAINT "registration_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."sport_admin_audit_log"
    ADD CONSTRAINT "sport_admin_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."badge_inbox_state"
    ADD CONSTRAINT "badge_inbox_state_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."badges"
    ADD CONSTRAINT "badges_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."badges"
    ADD CONSTRAINT "badges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."club_events"
    ADD CONSTRAINT "club_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."club_settings"
    ADD CONSTRAINT "club_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feature_flag_change_signals"
    ADD CONSTRAINT "feature_flag_change_signals_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."guest_players"
    ADD CONSTRAINT "guest_players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."historical_match_details"
    ADD CONSTRAINT "historical_match_details_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."historical_match_players"
    ADD CONSTRAINT "historical_match_players_pkey" PRIMARY KEY ("match_id", "player_id");



ALTER TABLE ONLY "public"."historical_match_scores"
    ADD CONSTRAINT "historical_match_scores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."historical_player_name_links"
    ADD CONSTRAINT "historical_player_name_links_pkey" PRIMARY KEY ("normalized_name");



ALTER TABLE ONLY "public"."historical_player_statistics"
    ADD CONSTRAINT "historical_player_statistics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."historical_player_statistics"
    ADD CONSTRAINT "historical_player_statistics_scope_player_name_key" UNIQUE ("scope", "player_name");



ALTER TABLE ONLY "public"."historical_team_statistics"
    ADD CONSTRAINT "historical_team_statistics_pkey" PRIMARY KEY ("scope");



ALTER TABLE ONLY "public"."match_attendance"
    ADD CONSTRAINT "match_attendance_pkey" PRIMARY KEY ("match_id", "season_player_id");



ALTER TABLE ONLY "public"."match_composition_entries"
    ADD CONSTRAINT "match_composition_entries_pkey" PRIMARY KEY ("match_id", "participant_id");



ALTER TABLE ONLY "public"."match_composition_publications"
    ADD CONSTRAINT "match_composition_publications_match_id_version_key" UNIQUE ("match_id", "version");



ALTER TABLE ONLY "public"."match_composition_publications"
    ADD CONSTRAINT "match_composition_publications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_compositions"
    ADD CONSTRAINT "match_compositions_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."match_internal_composition_entries"
    ADD CONSTRAINT "match_internal_composition_entries_pkey" PRIMARY KEY ("match_id", "participant_id");



ALTER TABLE ONLY "public"."match_internal_compositions"
    ADD CONSTRAINT "match_internal_compositions_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."match_live_events"
    ADD CONSTRAINT "match_live_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_live_sessions"
    ADD CONSTRAINT "match_live_sessions_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."match_man_of_match"
    ADD CONSTRAINT "match_man_of_match_pkey" PRIMARY KEY ("match_id", "season_player_id");



ALTER TABLE ONLY "public"."match_odds"
    ADD CONSTRAINT "match_odds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_player_stats"
    ADD CONSTRAINT "match_player_stats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_predictions"
    ADD CONSTRAINT "match_predictions_match_id_profile_id_key" UNIQUE ("match_id", "profile_id");



ALTER TABLE ONLY "public"."match_predictions"
    ADD CONSTRAINT "match_predictions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_sport_finalization_versions"
    ADD CONSTRAINT "match_sport_finalization_versions_match_id_version_key" UNIQUE ("match_id", "version");



ALTER TABLE ONLY "public"."match_sport_finalization_versions"
    ADD CONSTRAINT "match_sport_finalization_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_sport_finalizations"
    ADD CONSTRAINT "match_sport_finalizations_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."match_sport_motm_elections"
    ADD CONSTRAINT "match_sport_motm_elections_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."match_sport_motm_results"
    ADD CONSTRAINT "match_sport_motm_results_pkey" PRIMARY KEY ("match_id", "participant_id");



ALTER TABLE ONLY "public"."match_sport_motm_votes"
    ADD CONSTRAINT "match_sport_motm_votes_pkey" PRIMARY KEY ("match_id", "voter_profile_id");



ALTER TABLE ONLY "public"."match_sport_participant_events"
    ADD CONSTRAINT "match_sport_participant_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_id_match_id_key" UNIQUE ("id", "match_id");



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_match_id_season_player_id_key" UNIQUE ("match_id", "season_player_id");



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."match_sport_workflows"
    ADD CONSTRAINT "match_sport_workflows_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."match_weather"
    ADD CONSTRAINT "match_weather_pkey" PRIMARY KEY ("match_id");



ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."opponents"
    ADD CONSTRAINT "opponents_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."opponents"
    ADD CONSTRAINT "opponents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."player_aliases"
    ADD CONSTRAINT "player_aliases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."players"
    ADD CONSTRAINT "players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profile_badge_seen"
    ADD CONSTRAINT "profile_badge_seen_pkey" PRIMARY KEY ("profile_id", "badge_code");



ALTER TABLE ONLY "public"."profile_badges"
    ADD CONSTRAINT "profile_badges_pkey" PRIMARY KEY ("profile_id", "badge_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."push_delivery_log"
    ADD CONSTRAINT "push_delivery_log_pkey" PRIMARY KEY ("id");



ALTER TABLE "public"."push_notification_log"
    ADD CONSTRAINT "push_notification_log_kind_check" CHECK (("kind" = ANY (ARRAY['motm_open'::"text", 'motm_result_general'::"text", 'motm_result_winner'::"text", 'prediction_j5'::"text", 'match_cancelled'::"text", 'match_rescheduled_date'::"text", 'match_rescheduled_time'::"text"]))) NOT VALID;



ALTER TABLE ONLY "public"."push_notification_log"
    ADD CONSTRAINT "push_notification_log_pkey" PRIMARY KEY ("match_id", "kind");



ALTER TABLE ONLY "public"."push_subscriptions"
    ADD CONSTRAINT "push_subscriptions_endpoint_key" UNIQUE ("endpoint");



ALTER TABLE ONLY "public"."push_subscriptions"
    ADD CONSTRAINT "push_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."season_awards"
    ADD CONSTRAINT "season_awards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."season_awards"
    ADD CONSTRAINT "season_awards_season_id_profile_id_award_type_key" UNIQUE ("season_id", "profile_id", "award_type");



ALTER TABLE ONLY "public"."season_players"
    ADD CONSTRAINT "season_players_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."season_predictions"
    ADD CONSTRAINT "season_predictions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."seasons"
    ADD CONSTRAINT "seasons_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."seasons"
    ADD CONSTRAINT "seasons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shared_data_change_signals"
    ADD CONSTRAINT "shared_data_change_signals_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."sport_availability_notification_events"
    ADD CONSTRAINT "sport_availability_notification_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sport_waitlist_entries"
    ADD CONSTRAINT "sport_waitlist_entries_pkey" PRIMARY KEY ("season_player_id");



ALTER TABLE ONLY "public"."sport_waitlist_entries"
    ADD CONSTRAINT "sport_waitlist_entries_season_id_position_key" UNIQUE ("season_id", "position");



CREATE INDEX "idx_app_feature_flag_audit_actor_profile_id" ON "private"."app_feature_flag_audit" USING "btree" ("actor_profile_id");



CREATE INDEX "idx_app_feature_flag_audit_feature_key" ON "private"."app_feature_flag_audit" USING "btree" ("feature_key");



CREATE INDEX "idx_app_feature_flags_updated_by" ON "private"."app_feature_flags" USING "btree" ("updated_by");



CREATE INDEX "idx_sport_admin_audit_log_actor_profile_id" ON "private"."sport_admin_audit_log" USING "btree" ("actor_profile_id");



CREATE INDEX "registration_attempts_origin_time_idx" ON "private"."registration_attempts" USING "btree" ("origin_hash", "attempted_at" DESC);



CREATE INDEX "registration_attempts_time_idx" ON "private"."registration_attempts" USING "btree" ("attempted_at" DESC);



CREATE INDEX "sport_admin_audit_log_match_timeline_idx" ON "private"."sport_admin_audit_log" USING "btree" ("match_id", "created_at" DESC);



CREATE INDEX "club_events_created_by_idx" ON "public"."club_events" USING "btree" ("created_by");



CREATE INDEX "club_events_season_starts_idx" ON "public"."club_events" USING "btree" ("season_id", "starts_at" DESC);



CREATE INDEX "guest_players_active_name_idx" ON "public"."guest_players" USING "btree" ("lower"("btrim"("first_name")), "lower"(COALESCE("btrim"("last_name"), ''::"text"))) WHERE "is_reusable";



CREATE INDEX "guest_players_player_id_idx" ON "public"."guest_players" USING "btree" ("player_id");



CREATE UNIQUE INDEX "guest_players_reusable_identity_unique_idx" ON "public"."guest_players" USING "btree" ("lower"("btrim"("first_name")), "lower"(COALESCE("btrim"("last_name"), ''::"text")), "is_goalkeeper") WHERE "is_reusable";



CREATE INDEX "historical_match_players_player_id_idx" ON "public"."historical_match_players" USING "btree" ("player_id");



CREATE INDEX "historical_match_scores_date_idx" ON "public"."historical_match_scores" USING "btree" ("match_date" DESC, "id" DESC);



CREATE INDEX "historical_match_scores_opponent_date_idx" ON "public"."historical_match_scores" USING "btree" ("opponent_id", "match_date" DESC, "id" DESC);



CREATE INDEX "historical_player_name_links_player_id_idx" ON "public"."historical_player_name_links" USING "btree" ("player_id");



CREATE INDEX "historical_player_statistics_player_id_idx" ON "public"."historical_player_statistics" USING "btree" ("player_id");



CREATE INDEX "idx_guest_players_created_by" ON "public"."guest_players" USING "btree" ("created_by");



CREATE INDEX "idx_guest_players_updated_by" ON "public"."guest_players" USING "btree" ("updated_by");



CREATE INDEX "idx_hps_profile_id" ON "public"."historical_player_statistics" USING "btree" ("profile_id");



CREATE INDEX "idx_match_composition_entries_participant_id_match_id" ON "public"."match_composition_entries" USING "btree" ("participant_id", "match_id");



CREATE INDEX "idx_match_composition_publications_published_by" ON "public"."match_composition_publications" USING "btree" ("published_by");



CREATE INDEX "idx_match_compositions_last_modified_by" ON "public"."match_compositions" USING "btree" ("last_modified_by");



CREATE INDEX "idx_match_compositions_published_by" ON "public"."match_compositions" USING "btree" ("published_by");



CREATE UNIQUE INDEX "idx_match_odds_match" ON "public"."match_odds" USING "btree" ("match_id");



CREATE INDEX "idx_match_sport_finalization_versions_created_by" ON "public"."match_sport_finalization_versions" USING "btree" ("created_by");



CREATE INDEX "idx_match_sport_finalizations_corrected_by" ON "public"."match_sport_finalizations" USING "btree" ("corrected_by");



CREATE INDEX "idx_match_sport_finalizations_validated_by" ON "public"."match_sport_finalizations" USING "btree" ("validated_by");



CREATE INDEX "idx_match_sport_motm_results_participant_id_match_id" ON "public"."match_sport_motm_results" USING "btree" ("participant_id", "match_id");



CREATE INDEX "idx_match_sport_motm_votes_candidate_participant_id_match_id" ON "public"."match_sport_motm_votes" USING "btree" ("candidate_participant_id", "match_id");



CREATE INDEX "idx_match_sport_motm_votes_voter_profile_id" ON "public"."match_sport_motm_votes" USING "btree" ("voter_profile_id");



CREATE INDEX "idx_match_sport_participant_events_actor_profile_id" ON "public"."match_sport_participant_events" USING "btree" ("actor_profile_id");



CREATE INDEX "idx_match_sport_participant_events_participant_id_match_id" ON "public"."match_sport_participant_events" USING "btree" ("participant_id", "match_id");



CREATE INDEX "idx_match_sport_participants_availability_updated_by" ON "public"."match_sport_participants" USING "btree" ("availability_updated_by");



CREATE INDEX "idx_match_sport_participants_final_presence_confirmed_by" ON "public"."match_sport_participants" USING "btree" ("final_presence_confirmed_by");



CREATE INDEX "idx_match_sport_participants_promoted_from_participant_id" ON "public"."match_sport_participants" USING "btree" ("promoted_from_participant_id");



CREATE INDEX "idx_match_sport_participants_selection_updated_by" ON "public"."match_sport_participants" USING "btree" ("selection_updated_by");



CREATE INDEX "idx_match_sport_workflows_created_by" ON "public"."match_sport_workflows" USING "btree" ("created_by");



CREATE INDEX "idx_match_sport_workflows_updated_by" ON "public"."match_sport_workflows" USING "btree" ("updated_by");



CREATE INDEX "idx_matches_created_by" ON "public"."matches" USING "btree" ("created_by");



CREATE INDEX "idx_matches_date" ON "public"."matches" USING "btree" ("match_date");



CREATE INDEX "idx_matches_opponent" ON "public"."matches" USING "btree" ("opponent_id");



CREATE INDEX "idx_matches_season" ON "public"."matches" USING "btree" ("season_id");



CREATE INDEX "idx_predictions_profile" ON "public"."match_predictions" USING "btree" ("profile_id");



CREATE INDEX "idx_profile_badges_featured" ON "public"."profile_badges" USING "btree" ("profile_id") WHERE "featured";



CREATE INDEX "idx_push_delivery_log_created_at" ON "public"."push_delivery_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_push_delivery_log_health" ON "public"."push_delivery_log" USING "btree" ("created_at" DESC, "success", "status_code");



CREATE INDEX "idx_push_delivery_log_match_kind" ON "public"."push_delivery_log" USING "btree" ("match_id", "kind", "created_at" DESC);



CREATE INDEX "idx_push_delivery_log_profile" ON "public"."push_delivery_log" USING "btree" ("profile_id", "created_at" DESC);



CREATE INDEX "idx_push_subscriptions_profile" ON "public"."push_subscriptions" USING "btree" ("profile_id");



CREATE INDEX "idx_season_predictions_predictor" ON "public"."season_predictions" USING "btree" ("predictor_profile_id");



CREATE UNIQUE INDEX "idx_seasons_open" ON "public"."seasons" USING "btree" ("status") WHERE ("status" = 'open'::"text");



CREATE INDEX "idx_sport_availability_notification_events_participant_id_match" ON "public"."sport_availability_notification_events" USING "btree" ("participant_id", "match_id");



CREATE INDEX "idx_sport_availability_notification_events_requested_by" ON "public"."sport_availability_notification_events" USING "btree" ("requested_by");



CREATE INDEX "idx_sport_waitlist_entries_created_by" ON "public"."sport_waitlist_entries" USING "btree" ("created_by");



CREATE INDEX "idx_sport_waitlist_entries_season_player_id_season_id" ON "public"."sport_waitlist_entries" USING "btree" ("season_player_id", "season_id");



CREATE INDEX "idx_sport_waitlist_entries_updated_by" ON "public"."sport_waitlist_entries" USING "btree" ("updated_by");



CREATE INDEX "match_attendance_player_idx" ON "public"."match_attendance" USING "btree" ("season_player_id");



CREATE INDEX "match_composition_entries_zone_idx" ON "public"."match_composition_entries" USING "btree" ("match_id", "zone", "sort_order");



CREATE INDEX "match_composition_publications_latest_idx" ON "public"."match_composition_publications" USING "btree" ("match_id", "version" DESC);



CREATE INDEX "match_internal_composition_entries_participant_match_idx" ON "public"."match_internal_composition_entries" USING "btree" ("participant_id", "match_id");



CREATE INDEX "match_live_events_created_by_idx" ON "public"."match_live_events" USING "btree" ("created_by");



CREATE INDEX "match_live_events_match_id_created_idx" ON "public"."match_live_events" USING "btree" ("match_id", "created_at");



CREATE INDEX "match_live_events_player_in_participant_match_idx" ON "public"."match_live_events" USING "btree" ("player_in_participant_id", "match_id");



CREATE INDEX "match_live_events_player_out_participant_match_idx" ON "public"."match_live_events" USING "btree" ("player_out_participant_id", "match_id");



CREATE INDEX "match_live_events_scorer_participant_match_idx" ON "public"."match_live_events" USING "btree" ("scorer_participant_id", "match_id");



CREATE INDEX "match_live_sessions_updated_by_idx" ON "public"."match_live_sessions" USING "btree" ("updated_by");



CREATE INDEX "match_mvp_player_idx" ON "public"."match_man_of_match" USING "btree" ("season_player_id");



CREATE UNIQUE INDEX "match_player_stats_match_player_uidx" ON "public"."match_player_stats" USING "btree" ("match_id", "season_player_id");



CREATE INDEX "match_player_stats_season_player_id_idx" ON "public"."match_player_stats" USING "btree" ("season_player_id");



CREATE INDEX "match_sport_final_participants_present_idx" ON "public"."match_sport_participants" USING "btree" ("match_id", "final_selection_status") WHERE ("final_presence_status" = 'present'::"public"."sport_final_presence_status");



CREATE INDEX "match_sport_finalization_versions_latest_idx" ON "public"."match_sport_finalization_versions" USING "btree" ("match_id", "version" DESC);



CREATE INDEX "match_sport_motm_elections_due_idx" ON "public"."match_sport_motm_elections" USING "btree" ("state", "closes_at") WHERE ("state" = 'open'::"public"."sport_vote_state");



CREATE INDEX "match_sport_motm_results_winner_idx" ON "public"."match_sport_motm_results" USING "btree" ("match_id", "is_winner") WHERE "is_winner";



CREATE INDEX "match_sport_motm_votes_candidate_idx" ON "public"."match_sport_motm_votes" USING "btree" ("match_id", "candidate_participant_id");



CREATE INDEX "match_sport_participant_events_timeline_idx" ON "public"."match_sport_participant_events" USING "btree" ("participant_id", "created_at" DESC);



CREATE INDEX "match_sport_participants_convocation_idx" ON "public"."match_sport_participants" USING "btree" ("match_id", "convocation_status", "availability_status") WHERE "is_eligible";



CREATE INDEX "match_sport_participants_guest_idx" ON "public"."match_sport_participants" USING "btree" ("guest_player_id") WHERE ("guest_player_id" IS NOT NULL);



CREATE UNIQUE INDEX "match_sport_participants_match_guest_uidx" ON "public"."match_sport_participants" USING "btree" ("match_id", "guest_player_id") WHERE ("guest_player_id" IS NOT NULL);



CREATE INDEX "match_sport_participants_match_status_idx" ON "public"."match_sport_participants" USING "btree" ("match_id", "availability_status") WHERE "is_eligible";



CREATE INDEX "match_sport_participants_pending_turn_idx" ON "public"."match_sport_participants" USING "btree" ("match_id", "waitlist_turn_state") WHERE ("waitlist_turn_state" = 'pending'::"public"."sport_waitlist_turn_state");



CREATE INDEX "match_sport_participants_season_player_idx" ON "public"."match_sport_participants" USING "btree" ("season_player_id");



CREATE INDEX "match_sport_workflows_availability_due_idx" ON "public"."match_sport_workflows" USING "btree" ("availability_state", "availability_opens_at");



CREATE INDEX "match_weather_fetched_at_idx" ON "public"."match_weather" USING "btree" ("fetched_at");



CREATE UNIQUE INDEX "matches_match_date_uidx" ON "public"."matches" USING "btree" ("match_date");



CREATE INDEX "matches_upcoming_kickoff_idx" ON "public"."matches" USING "btree" ("kickoff_at", "id") WHERE ("status" = 'a_venir'::"text");



CREATE UNIQUE INDEX "opponents_normalized_name_idx" ON "public"."opponents" USING "btree" ("lower"("btrim"("name")));



CREATE INDEX "player_aliases_normalized_alias_idx" ON "public"."player_aliases" USING "btree" ("private"."normalize_player_name"("alias"));



CREATE UNIQUE INDEX "player_aliases_player_normalized_alias_uidx" ON "public"."player_aliases" USING "btree" ("player_id", "private"."normalize_player_name"("alias"));



CREATE INDEX "profile_badges_awarded_by_idx" ON "public"."profile_badges" USING "btree" ("awarded_by");



CREATE INDEX "profile_badges_badge_id_idx" ON "public"."profile_badges" USING "btree" ("badge_id");



CREATE INDEX "profile_badges_profile_idx" ON "public"."profile_badges" USING "btree" ("profile_id");



CREATE INDEX "profiles_player_id_idx" ON "public"."profiles" USING "btree" ("player_id") WHERE ("player_id" IS NOT NULL);



CREATE UNIQUE INDEX "profiles_username_lower_uidx" ON "public"."profiles" USING "btree" ("lower"("username")) WHERE ("username" IS NOT NULL);



CREATE INDEX "season_awards_profile_id_idx" ON "public"."season_awards" USING "btree" ("profile_id");



CREATE UNIQUE INDEX "season_players_id_season_id_uidx" ON "public"."season_players" USING "btree" ("id", "season_id");



CREATE INDEX "season_players_player_id_idx" ON "public"."season_players" USING "btree" ("player_id");



CREATE INDEX "season_players_profile_id_idx" ON "public"."season_players" USING "btree" ("profile_id") WHERE ("profile_id" IS NOT NULL);



CREATE INDEX "season_players_season_id_idx" ON "public"."season_players" USING "btree" ("season_id");



CREATE UNIQUE INDEX "season_players_season_profile_unique" ON "public"."season_players" USING "btree" ("season_id", "profile_id") WHERE ("profile_id" IS NOT NULL);



CREATE INDEX "season_predictions_season_player_id_idx" ON "public"."season_predictions" USING "btree" ("season_player_id");



CREATE UNIQUE INDEX "season_predictions_unique_idx" ON "public"."season_predictions" USING "btree" ("season_id", "predictor_profile_id", "season_player_id", "category");



CREATE UNIQUE INDEX "sport_availability_notification_auto_once_idx" ON "public"."sport_availability_notification_events" USING "btree" ("participant_id", "kind", "scheduled_for") WHERE ("source" = 'automatic'::"text");



CREATE INDEX "sport_availability_notification_match_timeline_idx" ON "public"."sport_availability_notification_events" USING "btree" ("match_id", "requested_at" DESC);



CREATE INDEX "sport_availability_notification_profile_timeline_idx" ON "public"."sport_availability_notification_events" USING "btree" ("profile_id", "requested_at" DESC);



CREATE INDEX "sport_waitlist_entries_season_order_idx" ON "public"."sport_waitlist_entries" USING "btree" ("season_id", "position");



CREATE OR REPLACE TRIGGER "trg_signal_feature_flag_change" AFTER UPDATE OF "enabled", "config" ON "private"."app_feature_flags" FOR EACH ROW WHEN ((("old"."enabled" IS DISTINCT FROM "new"."enabled") OR ("old"."config" IS DISTINCT FROM "new"."config"))) EXECUTE FUNCTION "private"."signal_feature_flag_change"();



CREATE OR REPLACE TRIGGER "capture_guest_player_alias_after_write" AFTER INSERT OR UPDATE OF "first_name", "last_name" ON "public"."guest_players" FOR EACH ROW EXECUTE FUNCTION "private"."capture_player_alias"();



CREATE OR REPLACE TRIGGER "capture_historical_player_alias_after_write" AFTER INSERT OR UPDATE OF "player_name" ON "public"."historical_player_statistics" FOR EACH ROW EXECUTE FUNCTION "private"."capture_player_alias"();



CREATE OR REPLACE TRIGGER "capture_profile_player_alias_after_write" AFTER INSERT OR UPDATE OF "first_name", "last_name" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "private"."capture_player_alias"();



CREATE OR REPLACE TRIGGER "capture_season_player_alias_after_write" AFTER INSERT OR UPDATE OF "first_name", "last_name" ON "public"."season_players" FOR EACH ROW EXECUTE FUNCTION "private"."capture_player_alias"();



CREATE OR REPLACE TRIGGER "ensure_guest_player_identity_before_insert" BEFORE INSERT ON "public"."guest_players" FOR EACH ROW EXECUTE FUNCTION "private"."ensure_guest_player_identity"();



CREATE OR REPLACE TRIGGER "ensure_historical_player_identity_before_insert" BEFORE INSERT ON "public"."historical_player_statistics" FOR EACH ROW EXECUTE FUNCTION "private"."ensure_historical_player_identity"();



CREATE OR REPLACE TRIGGER "ensure_profile_player_identity_before_insert" BEFORE INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "private"."ensure_profile_player_identity"();



CREATE OR REPLACE TRIGGER "ensure_season_player_identity_before_insert" BEFORE INSERT ON "public"."season_players" FOR EACH ROW EXECUTE FUNCTION "private"."ensure_season_player_identity"();



CREATE OR REPLACE TRIGGER "guard_finished_match_composition_entry_write" BEFORE INSERT OR DELETE OR UPDATE ON "public"."match_composition_entries" FOR EACH ROW EXECUTE FUNCTION "private"."guard_finished_match_composition_write"();



CREATE OR REPLACE TRIGGER "guard_finished_match_composition_publication_write" BEFORE INSERT OR DELETE OR UPDATE ON "public"."match_composition_publications" FOR EACH ROW EXECUTE FUNCTION "private"."guard_finished_match_composition_write"();



CREATE OR REPLACE TRIGGER "guard_finished_match_composition_write" BEFORE INSERT OR DELETE OR UPDATE ON "public"."match_compositions" FOR EACH ROW EXECUTE FUNCTION "private"."guard_finished_match_composition_write"();



CREATE OR REPLACE TRIGGER "guard_match_prediction_window" BEFORE INSERT OR UPDATE ON "public"."match_predictions" FOR EACH ROW EXECUTE FUNCTION "public"."guard_match_prediction_window"();



CREATE OR REPLACE TRIGGER "normalize_waitlisted_withdrawal_before_update" BEFORE UPDATE OF "availability_status" ON "public"."match_sport_participants" FOR EACH ROW EXECUTE FUNCTION "private"."normalize_waitlisted_withdrawal"();



CREATE OR REPLACE TRIGGER "on_profile_pending_signup" AFTER INSERT ON "public"."profiles" FOR EACH ROW WHEN (("new"."status" = 'pending'::"text")) EXECUTE FUNCTION "private"."notify_admins_of_pending_signup"();



CREATE OR REPLACE TRIGGER "sync_historical_match_players_after_write" AFTER INSERT OR DELETE OR UPDATE ON "public"."historical_match_details" FOR EACH ROW EXECUTE FUNCTION "private"."sync_historical_match_players"();



CREATE OR REPLACE TRIGGER "trg_auto_match_odds_v4" AFTER INSERT OR UPDATE OF "opponent_id", "location", "status" ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_match_odds_v4"();



CREATE OR REPLACE TRIGGER "trg_award_titles" AFTER INSERT OR UPDATE ON "public"."seasons" FOR EACH ROW EXECUTE FUNCTION "public"."trg_award_titles_on_season_close"();



CREATE OR REPLACE TRIGGER "trg_badges_attendance" AFTER INSERT OR DELETE ON "public"."match_attendance" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_attendance"();



CREATE OR REPLACE TRIGGER "trg_badges_historical_link" AFTER INSERT OR UPDATE OF "profile_id" ON "public"."historical_player_statistics" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_historical_link"();



CREATE OR REPLACE TRIGGER "trg_badges_match_result" AFTER INSERT OR UPDATE ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_match_result"();



CREATE OR REPLACE TRIGGER "trg_badges_mvp" AFTER INSERT OR DELETE ON "public"."match_man_of_match" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_mvp"();



CREATE OR REPLACE TRIGGER "trg_badges_player_stats" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_player_stats" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_player_stats"();



CREATE OR REPLACE TRIGGER "trg_badges_prediction" AFTER INSERT OR UPDATE ON "public"."match_predictions" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_prediction"();



CREATE OR REPLACE TRIGGER "trg_badges_roster" AFTER INSERT OR UPDATE OF "profile_id", "first_name", "last_name", "season_id" ON "public"."season_players" FOR EACH ROW EXECUTE FUNCTION "public"."trg_badges_on_roster_change"();



CREATE OR REPLACE TRIGGER "trg_cleanup_replaced_photo" AFTER UPDATE OF "photo_url" ON "public"."guest_players" FOR EACH ROW EXECUTE FUNCTION "public"."cleanup_replaced_photo"();



CREATE OR REPLACE TRIGGER "trg_cleanup_replaced_photo" AFTER UPDATE OF "photo_url" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."cleanup_replaced_photo"();



CREATE OR REPLACE TRIGGER "trg_cleanup_replaced_photo" AFTER UPDATE OF "photo_url" ON "public"."season_players" FOR EACH ROW EXECUTE FUNCTION "public"."cleanup_replaced_photo"();



CREATE OR REPLACE TRIGGER "trg_guard_match_archive_transition" BEFORE UPDATE OF "status" ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "private"."guard_match_archive_transition"();



CREATE OR REPLACE TRIGGER "trg_guard_match_lifecycle_write" BEFORE DELETE OR UPDATE ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "private"."guard_match_lifecycle_write"();



CREATE OR REPLACE TRIGGER "trg_guard_match_status_chronology" BEFORE INSERT OR UPDATE OF "match_date", "match_time", "status" ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "private"."guard_match_status_chronology"();



CREATE OR REPLACE TRIGGER "trg_guard_postgame_correction_window" BEFORE UPDATE ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "private"."guard_postgame_correction_window"();



CREATE OR REPLACE TRIGGER "trg_guard_sensitive_profile_fields" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."guard_sensitive_profile_fields"();



CREATE OR REPLACE TRIGGER "trg_notification_match_changes" AFTER UPDATE OF "status", "kickoff_at" ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "private"."handle_match_notification_change"();



CREATE OR REPLACE TRIGGER "trg_notify_waitlist_promotion" AFTER UPDATE OF "convocation_status" ON "public"."match_sport_participants" FOR EACH ROW EXECUTE FUNCTION "private"."notify_waitlist_promotion"();



CREATE OR REPLACE TRIGGER "trg_push_on_motm_election_closed" AFTER UPDATE OF "state" ON "public"."match_sport_motm_elections" FOR EACH ROW EXECUTE FUNCTION "public"."push_on_motm_election_closed"();



CREATE OR REPLACE TRIGGER "trg_push_on_motm_election_opened" AFTER INSERT OR UPDATE OF "state", "opens_at", "closes_at", "finalization_version" ON "public"."match_sport_motm_elections" FOR EACH ROW EXECUTE FUNCTION "public"."push_on_motm_election_opened"();



CREATE OR REPLACE TRIGGER "trg_recalculate_upcoming_odds_v3" AFTER UPDATE OF "status", "score_as_grinta", "score_adverse" ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_recalculate_upcoming_odds_v3"();



CREATE OR REPLACE TRIGGER "trg_reset_internal_composition_on_first_effectif_publish" AFTER UPDATE OF "convocation_version" ON "public"."match_sport_workflows" FOR EACH ROW WHEN (("old"."convocation_version" IS DISTINCT FROM "new"."convocation_version")) EXECUTE FUNCTION "private"."reset_internal_match_composition_on_first_effectif_publish"();



CREATE OR REPLACE TRIGGER "trg_reset_match_motm_after_finalization" AFTER INSERT ON "public"."match_sport_finalization_versions" FOR EACH ROW EXECUTE FUNCTION "private"."trg_reset_match_motm_after_finalization"();



CREATE OR REPLACE TRIGGER "trg_season_player_coach_sync" AFTER UPDATE OF "is_coach" ON "public"."season_players" FOR EACH ROW EXECUTE FUNCTION "private"."apply_coach_flag_to_participants"();



CREATE OR REPLACE TRIGGER "trg_seed_match_predictions" AFTER INSERT ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "public"."seed_match_predictions"();



CREATE OR REPLACE TRIGGER "trg_seed_predictions_for_active_profile" AFTER INSERT OR UPDATE OF "status", "role" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."seed_predictions_for_active_profile"();



CREATE OR REPLACE TRIGGER "trg_seed_season_predictions_for_player" AFTER INSERT ON "public"."season_players" FOR EACH ROW EXECUTE FUNCTION "public"."seed_season_predictions_for_player"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."badges" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."guest_players" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_attendance" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_composition_entries" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_composition_publications" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_compositions" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_internal_composition_entries" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_internal_compositions" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_man_of_match" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_odds" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_player_stats" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_sport_finalizations" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_sport_motm_results" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_sport_participants" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."match_sport_workflows" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."matches" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."opponents" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."profile_badges" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."profiles" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."season_players" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."season_predictions" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."seasons" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_shared_data_change" AFTER INSERT OR DELETE OR UPDATE ON "public"."sport_waitlist_entries" FOR EACH STATEMENT EXECUTE FUNCTION "private"."signal_shared_data_change"();



CREATE OR REPLACE TRIGGER "trg_sync_match_kickoff_at" BEFORE INSERT OR UPDATE OF "match_date", "match_time", "kickoff_at" ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "public"."sync_match_kickoff_at"();



CREATE OR REPLACE TRIGGER "trg_validate_profile_names" BEFORE INSERT OR UPDATE OF "first_name", "last_name", "surnom" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."validate_profile_names"();



CREATE OR REPLACE TRIGGER "trg_validate_season_prediction_row" BEFORE INSERT OR UPDATE OF "season_id", "season_player_id", "category", "predicted_value_30" ON "public"."season_predictions" FOR EACH ROW EXECUTE FUNCTION "public"."validate_season_prediction_row"();



ALTER TABLE ONLY "private"."app_feature_flag_audit"
    ADD CONSTRAINT "app_feature_flag_audit_actor_profile_id_fkey" FOREIGN KEY ("actor_profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."app_feature_flag_audit"
    ADD CONSTRAINT "app_feature_flag_audit_feature_key_fkey" FOREIGN KEY ("feature_key") REFERENCES "private"."app_feature_flags"("key") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "private"."app_feature_flags"
    ADD CONSTRAINT "app_feature_flags_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."sport_admin_audit_log"
    ADD CONSTRAINT "sport_admin_audit_log_actor_profile_id_fkey" FOREIGN KEY ("actor_profile_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "private"."sport_admin_audit_log"
    ADD CONSTRAINT "sport_admin_audit_log_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."badge_inbox_state"
    ADD CONSTRAINT "badge_inbox_state_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."club_events"
    ADD CONSTRAINT "club_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."club_events"
    ADD CONSTRAINT "club_events_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."guest_players"
    ADD CONSTRAINT "guest_players_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."guest_players"
    ADD CONSTRAINT "guest_players_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."guest_players"
    ADD CONSTRAINT "guest_players_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."historical_match_details"
    ADD CONSTRAINT "historical_match_details_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."historical_match_scores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."historical_match_players"
    ADD CONSTRAINT "historical_match_players_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."historical_match_scores"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."historical_match_players"
    ADD CONSTRAINT "historical_match_players_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."historical_match_scores"
    ADD CONSTRAINT "historical_match_scores_opponent_id_fkey" FOREIGN KEY ("opponent_id") REFERENCES "public"."opponents"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."historical_player_name_links"
    ADD CONSTRAINT "historical_player_name_links_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."historical_player_statistics"
    ADD CONSTRAINT "historical_player_statistics_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."historical_player_statistics"
    ADD CONSTRAINT "historical_player_statistics_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."match_attendance"
    ADD CONSTRAINT "match_attendance_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_attendance"
    ADD CONSTRAINT "match_attendance_season_player_id_fkey" FOREIGN KEY ("season_player_id") REFERENCES "public"."season_players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_composition_entries"
    ADD CONSTRAINT "match_composition_entries_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_compositions"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_composition_entries"
    ADD CONSTRAINT "match_composition_entries_participant_id_match_id_fkey" FOREIGN KEY ("participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_composition_publications"
    ADD CONSTRAINT "match_composition_publications_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_compositions"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_composition_publications"
    ADD CONSTRAINT "match_composition_publications_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_compositions"
    ADD CONSTRAINT "match_compositions_last_modified_by_fkey" FOREIGN KEY ("last_modified_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_compositions"
    ADD CONSTRAINT "match_compositions_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_workflows"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_compositions"
    ADD CONSTRAINT "match_compositions_published_by_fkey" FOREIGN KEY ("published_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_internal_composition_entries"
    ADD CONSTRAINT "match_internal_composition_entries_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_internal_compositions"("match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_internal_composition_entries"
    ADD CONSTRAINT "match_internal_composition_entries_participant_fkey" FOREIGN KEY ("participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_internal_compositions"
    ADD CONSTRAINT "match_internal_compositions_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_live_events"
    ADD CONSTRAINT "match_live_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_live_events"
    ADD CONSTRAINT "match_live_events_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_live_events"
    ADD CONSTRAINT "match_live_events_player_in_participant_id_match_id_fkey" FOREIGN KEY ("player_in_participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_live_events"
    ADD CONSTRAINT "match_live_events_player_out_participant_id_match_id_fkey" FOREIGN KEY ("player_out_participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_live_events"
    ADD CONSTRAINT "match_live_events_scorer_participant_id_match_id_fkey" FOREIGN KEY ("scorer_participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_live_sessions"
    ADD CONSTRAINT "match_live_sessions_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_live_sessions"
    ADD CONSTRAINT "match_live_sessions_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_man_of_match"
    ADD CONSTRAINT "match_man_of_match_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_man_of_match"
    ADD CONSTRAINT "match_man_of_match_season_player_id_fkey" FOREIGN KEY ("season_player_id") REFERENCES "public"."season_players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_odds"
    ADD CONSTRAINT "match_odds_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_player_stats"
    ADD CONSTRAINT "match_player_stats_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_player_stats"
    ADD CONSTRAINT "match_player_stats_season_player_id_fkey" FOREIGN KEY ("season_player_id") REFERENCES "public"."season_players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_predictions"
    ADD CONSTRAINT "match_predictions_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_predictions"
    ADD CONSTRAINT "match_predictions_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_sport_finalization_versions"
    ADD CONSTRAINT "match_sport_finalization_versions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_finalization_versions"
    ADD CONSTRAINT "match_sport_finalization_versions_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_finalizations"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_finalizations"
    ADD CONSTRAINT "match_sport_finalizations_corrected_by_fkey" FOREIGN KEY ("corrected_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_finalizations"
    ADD CONSTRAINT "match_sport_finalizations_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_workflows"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_finalizations"
    ADD CONSTRAINT "match_sport_finalizations_validated_by_fkey" FOREIGN KEY ("validated_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_motm_elections"
    ADD CONSTRAINT "match_sport_motm_elections_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_workflows"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_motm_results"
    ADD CONSTRAINT "match_sport_motm_results_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_motm_elections"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_motm_results"
    ADD CONSTRAINT "match_sport_motm_results_participant_id_match_id_fkey" FOREIGN KEY ("participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_sport_motm_votes"
    ADD CONSTRAINT "match_sport_motm_votes_candidate_participant_id_match_id_fkey" FOREIGN KEY ("candidate_participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_sport_motm_votes"
    ADD CONSTRAINT "match_sport_motm_votes_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_motm_elections"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_motm_votes"
    ADD CONSTRAINT "match_sport_motm_votes_voter_profile_id_fkey" FOREIGN KEY ("voter_profile_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_participant_events"
    ADD CONSTRAINT "match_sport_participant_events_actor_profile_id_fkey" FOREIGN KEY ("actor_profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."match_sport_participant_events"
    ADD CONSTRAINT "match_sport_participant_events_participant_id_match_id_fkey" FOREIGN KEY ("participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_availability_updated_by_fkey" FOREIGN KEY ("availability_updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_final_presence_confirmed_by_fkey" FOREIGN KEY ("final_presence_confirmed_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_guest_player_id_fkey" FOREIGN KEY ("guest_player_id") REFERENCES "public"."guest_players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_workflows"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_promoted_from_participant_id_fkey" FOREIGN KEY ("promoted_from_participant_id") REFERENCES "public"."match_sport_participants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_season_player_id_fkey" FOREIGN KEY ("season_player_id") REFERENCES "public"."season_players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."match_sport_participants"
    ADD CONSTRAINT "match_sport_participants_selection_updated_by_fkey" FOREIGN KEY ("selection_updated_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."match_sport_workflows"
    ADD CONSTRAINT "match_sport_workflows_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_workflows"
    ADD CONSTRAINT "match_sport_workflows_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_sport_workflows"
    ADD CONSTRAINT "match_sport_workflows_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."match_weather"
    ADD CONSTRAINT "match_weather_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET DEFAULT;



ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_opponent_id_fkey" FOREIGN KEY ("opponent_id") REFERENCES "public"."opponents"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."player_aliases"
    ADD CONSTRAINT "player_aliases_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_badge_seen"
    ADD CONSTRAINT "profile_badge_seen_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_badges"
    ADD CONSTRAINT "profile_badges_awarded_by_fkey" FOREIGN KEY ("awarded_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profile_badges"
    ADD CONSTRAINT "profile_badges_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "public"."badges"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_badges"
    ADD CONSTRAINT "profile_badges_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."push_delivery_log"
    ADD CONSTRAINT "push_delivery_log_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_delivery_log"
    ADD CONSTRAINT "push_delivery_log_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."push_notification_log"
    ADD CONSTRAINT "push_notification_log_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_subscriptions"
    ADD CONSTRAINT "push_subscriptions_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."season_awards"
    ADD CONSTRAINT "season_awards_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."season_awards"
    ADD CONSTRAINT "season_awards_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."season_players"
    ADD CONSTRAINT "season_players_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."season_players"
    ADD CONSTRAINT "season_players_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."season_players"
    ADD CONSTRAINT "season_players_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."season_predictions"
    ADD CONSTRAINT "season_predictions_predictor_profile_id_fkey" FOREIGN KEY ("predictor_profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."season_predictions"
    ADD CONSTRAINT "season_predictions_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."season_predictions"
    ADD CONSTRAINT "season_predictions_season_player_id_fkey" FOREIGN KEY ("season_player_id") REFERENCES "public"."season_players"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sport_availability_notification_events"
    ADD CONSTRAINT "sport_availability_notification_ev_participant_id_match_id_fkey" FOREIGN KEY ("participant_id", "match_id") REFERENCES "public"."match_sport_participants"("id", "match_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sport_availability_notification_events"
    ADD CONSTRAINT "sport_availability_notification_events_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."match_sport_workflows"("match_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sport_availability_notification_events"
    ADD CONSTRAINT "sport_availability_notification_events_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sport_availability_notification_events"
    ADD CONSTRAINT "sport_availability_notification_events_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sport_waitlist_entries"
    ADD CONSTRAINT "sport_waitlist_entries_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sport_waitlist_entries"
    ADD CONSTRAINT "sport_waitlist_entries_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sport_waitlist_entries"
    ADD CONSTRAINT "sport_waitlist_entries_season_player_id_season_id_fkey" FOREIGN KEY ("season_player_id", "season_id") REFERENCES "public"."season_players"("id", "season_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sport_waitlist_entries"
    ADD CONSTRAINT "sport_waitlist_entries_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."profiles"("id") ON DELETE RESTRICT;



ALTER TABLE "private"."app_feature_flag_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."app_feature_flags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deny_client_access" ON "private"."app_feature_flag_audit" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "private"."app_feature_flags" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "private"."sport_admin_audit_log" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "private"."sport_admin_audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Authenticated users can read historical statistics" ON "public"."historical_player_statistics" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "active_authenticated_profile_only" ON "public"."badge_inbox_state" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."badges" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."club_events" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."club_settings" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."feature_flag_change_signals" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."guest_players" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."historical_match_details" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."historical_match_players" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."historical_match_scores" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."historical_player_name_links" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."historical_player_statistics" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."historical_team_statistics" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_attendance" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_composition_entries" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_composition_publications" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_compositions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_internal_composition_entries" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_internal_compositions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_live_events" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_live_sessions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_man_of_match" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_odds" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_player_stats" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_predictions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_finalization_versions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_finalizations" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_motm_elections" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_motm_results" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_motm_votes" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_participant_events" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_participants" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_sport_workflows" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."match_weather" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."matches" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."opponents" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."player_aliases" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."players" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."profile_badge_seen" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."profile_badges" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."profiles" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."push_delivery_log" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."push_notification_log" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."push_subscriptions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."season_awards" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."season_players" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."season_predictions" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."seasons" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."sport_availability_notification_events" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "active_authenticated_profile_only" ON "public"."sport_waitlist_entries" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile")) WITH CHECK (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "authenticated_read_match_odds" ON "public"."match_odds" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_matches" ON "public"."matches" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_opponents" ON "public"."opponents" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_profiles" ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_season_players" ON "public"."season_players" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_season_predictions" ON "public"."season_predictions" FOR SELECT TO "authenticated" USING ((("predictor_profile_id" = ( SELECT "auth"."uid"() AS "uid")) OR (EXISTS ( SELECT 1
   FROM "public"."seasons" "s"
  WHERE (("s"."id" = "season_predictions"."season_id") AND (("s"."season_predictions_locked_at" IS NOT NULL) OR ("s"."status" = 'archived'::"text")))))));



CREATE POLICY "authenticated_read_seasons" ON "public"."seasons" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."badge_inbox_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "badge_inbox_state_insert_own" ON "public"."badge_inbox_state" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "profile_id"));



CREATE POLICY "badge_inbox_state_select_own" ON "public"."badge_inbox_state" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "profile_id"));



CREATE POLICY "badge_inbox_state_update_own" ON "public"."badge_inbox_state" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "profile_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "profile_id"));



ALTER TABLE "public"."badges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "badges_read" ON "public"."badges" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."club_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "club_events_active_read" ON "public"."club_events" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



CREATE POLICY "club_events_admin_delete" ON "public"."club_events" FOR DELETE TO "authenticated" USING (( SELECT "private"."is_admin"() AS "is_admin"));



CREATE POLICY "club_events_admin_insert" ON "public"."club_events" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "private"."is_admin"() AS "is_admin") AND ("created_by" = ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "club_events_admin_update" ON "public"."club_events" FOR UPDATE TO "authenticated" USING (( SELECT "private"."is_admin"() AS "is_admin")) WITH CHECK (( SELECT "private"."is_admin"() AS "is_admin"));



ALTER TABLE "public"."club_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "club_settings_read" ON "public"."club_settings" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "deny_client_access" ON "public"."historical_match_details" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."historical_match_players" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."historical_match_scores" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."historical_player_name_links" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_composition_entries" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_compositions" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_sport_finalization_versions" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_sport_finalizations" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_sport_motm_elections" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_sport_motm_results" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."match_sport_motm_votes" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."player_aliases" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."players" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "deny_client_access" ON "public"."sport_availability_notification_events" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "public"."feature_flag_change_signals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feature_flag_change_signals_read" ON "public"."feature_flag_change_signals" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."guest_players" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "guest_players_admin_select" ON "public"."guest_players" FOR SELECT TO "authenticated" USING ((( SELECT "private"."is_feature_enabled"('sports_management'::"text") AS "is_feature_enabled") AND ( SELECT "private"."is_admin"() AS "is_admin")));



ALTER TABLE "public"."historical_match_details" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."historical_match_players" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."historical_match_scores" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."historical_player_name_links" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."historical_player_statistics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."historical_team_statistics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "historical_team_statistics_authenticated_read" ON "public"."historical_team_statistics" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."match_attendance" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_attendance_read" ON "public"."match_attendance" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."match_composition_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_composition_publications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_composition_publications_active_profile_select" ON "public"."match_composition_publications" FOR SELECT TO "authenticated" USING ((( SELECT "private"."is_feature_enabled"('sports_management'::"text") AS "is_feature_enabled") AND ( SELECT "private"."is_active_profile"() AS "is_active_profile")));



ALTER TABLE "public"."match_compositions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_internal_composition_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_internal_composition_entries_delete" ON "public"."match_internal_composition_entries" FOR DELETE TO "authenticated" USING ("public"."is_match_staff"());



CREATE POLICY "match_internal_composition_entries_insert" ON "public"."match_internal_composition_entries" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_match_staff"());



CREATE POLICY "match_internal_composition_entries_select" ON "public"."match_internal_composition_entries" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "match_internal_composition_entries_update" ON "public"."match_internal_composition_entries" FOR UPDATE TO "authenticated" USING ("public"."is_match_staff"()) WITH CHECK ("public"."is_match_staff"());



ALTER TABLE "public"."match_internal_compositions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_internal_compositions_delete" ON "public"."match_internal_compositions" FOR DELETE TO "authenticated" USING ("public"."is_match_staff"());



CREATE POLICY "match_internal_compositions_insert" ON "public"."match_internal_compositions" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_match_staff"());



CREATE POLICY "match_internal_compositions_select" ON "public"."match_internal_compositions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "match_internal_compositions_update" ON "public"."match_internal_compositions" FOR UPDATE TO "authenticated" USING ("public"."is_match_staff"()) WITH CHECK ("public"."is_match_staff"());



ALTER TABLE "public"."match_live_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_live_events_active_profile_select" ON "public"."match_live_events" FOR SELECT TO "authenticated" USING ((( SELECT "private"."is_feature_enabled"('sports_management'::"text") AS "is_feature_enabled") AND ( SELECT "private"."is_active_profile"() AS "is_active_profile")));



ALTER TABLE "public"."match_live_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_live_sessions_active_profile_select" ON "public"."match_live_sessions" FOR SELECT TO "authenticated" USING ((( SELECT "private"."is_feature_enabled"('sports_management'::"text") AS "is_feature_enabled") AND ( SELECT "private"."is_active_profile"() AS "is_active_profile")));



ALTER TABLE "public"."match_man_of_match" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_mvp_read" ON "public"."match_man_of_match" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."match_odds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_player_stats" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_player_stats_read" ON "public"."match_player_stats" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."match_predictions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_predictions_owner_insert" ON "public"."match_predictions" FOR INSERT TO "authenticated" WITH CHECK ((("profile_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "private"."is_active_profile"() AS "is_active_profile") AND ((NOT "is_filled") OR (EXISTS ( SELECT 1
   FROM "public"."matches" "m"
  WHERE (("m"."id" = "match_predictions"."match_id") AND ("m"."status" = 'a_venir'::"text") AND ("m"."kickoff_at" IS NOT NULL) AND ("now"() >= ("m"."kickoff_at" - '6 days'::interval)) AND ("now"() < ("m"."kickoff_at" - '00:05:00'::interval)) AND (("m"."predictions_closed_at" IS NULL) OR ("now"() < "m"."predictions_closed_at"))))))));



CREATE POLICY "match_predictions_owner_update_window" ON "public"."match_predictions" FOR UPDATE TO "authenticated" USING (("profile_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK ((("profile_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "private"."is_active_profile"() AS "is_active_profile") AND ((NOT "is_filled") OR (EXISTS ( SELECT 1
   FROM "public"."matches" "m"
  WHERE (("m"."id" = "match_predictions"."match_id") AND ("m"."status" = 'a_venir'::"text") AND ("m"."kickoff_at" IS NOT NULL) AND ("now"() >= ("m"."kickoff_at" - '6 days'::interval)) AND ("now"() < ("m"."kickoff_at" - '00:05:00'::interval)) AND (("m"."predictions_closed_at" IS NULL) OR ("now"() < "m"."predictions_closed_at"))))))));



ALTER TABLE "public"."match_sport_finalization_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_sport_finalizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_sport_motm_elections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_sport_motm_results" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_sport_motm_votes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."match_sport_participant_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_sport_participant_events_authorized_select" ON "public"."match_sport_participant_events" FOR SELECT TO "authenticated" USING (( SELECT "private"."can_read_sport_participant"("match_sport_participant_events"."participant_id") AS "can_read_sport_participant"));



ALTER TABLE "public"."match_sport_participants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_sport_participants_authorized_select" ON "public"."match_sport_participants" FOR SELECT TO "authenticated" USING (( SELECT "private"."can_read_sport_participant"("match_sport_participants"."id") AS "can_read_sport_participant"));



ALTER TABLE "public"."match_sport_workflows" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_sport_workflows_authorized_select" ON "public"."match_sport_workflows" FOR SELECT TO "authenticated" USING (( SELECT "private"."can_read_sport_workflow"("match_sport_workflows"."match_id") AS "can_read_sport_workflow"));



ALTER TABLE "public"."match_weather" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "match_weather_active_profile_select" ON "public"."match_weather" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



ALTER TABLE "public"."matches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "matches_authorized_update" ON "public"."matches" FOR UPDATE TO "authenticated" USING ((( SELECT "private"."is_admin"() AS "is_admin") AND ("status" <> 'archive'::"text"))) WITH CHECK (( SELECT "private"."is_admin"() AS "is_admin"));



CREATE POLICY "matches_staff_delete" ON "public"."matches" FOR DELETE TO "authenticated" USING (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



CREATE POLICY "matches_staff_insert" ON "public"."matches" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "private"."is_match_staff"() AS "is_match_staff") AND ("created_by" = ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."opponents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "opponents_admin_delete" ON "public"."opponents" FOR DELETE TO "authenticated" USING (( SELECT "private"."is_admin"() AS "is_admin"));



CREATE POLICY "opponents_admin_insert" ON "public"."opponents" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "private"."is_admin"() AS "is_admin"));



CREATE POLICY "opponents_admin_update" ON "public"."opponents" FOR UPDATE TO "authenticated" USING (( SELECT "private"."is_admin"() AS "is_admin")) WITH CHECK (( SELECT "private"."is_admin"() AS "is_admin"));



ALTER TABLE "public"."player_aliases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."players" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profile_badge_seen" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profile_badge_seen_insert_own" ON "public"."profile_badge_seen" FOR INSERT TO "authenticated" WITH CHECK (("profile_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "profile_badge_seen_select_own" ON "public"."profile_badge_seen" FOR SELECT TO "authenticated" USING (("profile_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."profile_badges" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profile_badges_read" ON "public"."profile_badges" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_update_authorized" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "private"."is_match_staff"() AS "is_match_staff"))) WITH CHECK ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "private"."is_match_staff"() AS "is_match_staff")));



ALTER TABLE "public"."push_delivery_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "push_delivery_log_deny_client_roles" ON "public"."push_delivery_log" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "public"."push_notification_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "push_notification_log_no_client_access" ON "public"."push_notification_log" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "public"."push_subscriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "push_subscriptions_owner_delete" ON "public"."push_subscriptions" FOR DELETE TO "authenticated" USING (("profile_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "push_subscriptions_owner_insert" ON "public"."push_subscriptions" FOR INSERT TO "authenticated" WITH CHECK (("profile_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "push_subscriptions_owner_select" ON "public"."push_subscriptions" FOR SELECT TO "authenticated" USING (("profile_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "push_subscriptions_owner_update" ON "public"."push_subscriptions" FOR UPDATE TO "authenticated" USING (("profile_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("profile_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "read_own_or_revealed_match_predictions" ON "public"."match_predictions" FOR SELECT TO "authenticated" USING ((("profile_id" = ( SELECT "auth"."uid"() AS "uid")) OR (EXISTS ( SELECT 1
   FROM "public"."matches" "m"
  WHERE (("m"."id" = "match_predictions"."match_id") AND ("m"."status" = ANY (ARRAY['termine'::"text", 'archive'::"text"])))))));



ALTER TABLE "public"."season_awards" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "season_awards_deny_client_roles" ON "public"."season_awards" AS RESTRICTIVE TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "public"."season_players" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "season_players_staff_delete" ON "public"."season_players" FOR DELETE TO "authenticated" USING (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



CREATE POLICY "season_players_staff_insert" ON "public"."season_players" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



CREATE POLICY "season_players_staff_update" ON "public"."season_players" FOR UPDATE TO "authenticated" USING (( SELECT "private"."is_match_staff"() AS "is_match_staff")) WITH CHECK (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



ALTER TABLE "public"."season_predictions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "season_predictions_owner_insert" ON "public"."season_predictions" FOR INSERT TO "authenticated" WITH CHECK ((("predictor_profile_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "private"."is_active_profile"() AS "is_active_profile") AND (EXISTS ( SELECT 1
   FROM "public"."seasons" "s"
  WHERE (("s"."id" = "season_predictions"."season_id") AND ("s"."status" = 'open'::"text") AND ("s"."season_predictions_locked_at" IS NULL))))));



CREATE POLICY "season_predictions_owner_update" ON "public"."season_predictions" FOR UPDATE TO "authenticated" USING (("predictor_profile_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK ((("predictor_profile_id" = ( SELECT "auth"."uid"() AS "uid")) AND ( SELECT "private"."is_active_profile"() AS "is_active_profile") AND (EXISTS ( SELECT 1
   FROM "public"."seasons" "s"
  WHERE (("s"."id" = "season_predictions"."season_id") AND ("s"."status" = 'open'::"text") AND ("s"."season_predictions_locked_at" IS NULL))))));



ALTER TABLE "public"."seasons" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "seasons_staff_delete" ON "public"."seasons" FOR DELETE TO "authenticated" USING (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



CREATE POLICY "seasons_staff_insert" ON "public"."seasons" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



CREATE POLICY "seasons_staff_update" ON "public"."seasons" FOR UPDATE TO "authenticated" USING (( SELECT "private"."is_match_staff"() AS "is_match_staff")) WITH CHECK (( SELECT "private"."is_match_staff"() AS "is_match_staff"));



ALTER TABLE "public"."shared_data_change_signals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "shared_data_change_signals_active_read" ON "public"."shared_data_change_signals" FOR SELECT TO "authenticated" USING (( SELECT "private"."is_active_profile"() AS "is_active_profile"));



ALTER TABLE "public"."sport_availability_notification_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sport_waitlist_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sport_waitlist_entries_admin_select" ON "public"."sport_waitlist_entries" FOR SELECT TO "authenticated" USING ((( SELECT "private"."is_feature_enabled"('sports_management'::"text") AS "is_feature_enabled") AND ( SELECT "private"."is_admin"() AS "is_admin")));



GRANT USAGE ON SCHEMA "private" TO "authenticated";
GRANT USAGE ON SCHEMA "private" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "private"."add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."apply_coach_flag_to_participants"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."assert_match_postgame_correction_open"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."can_read_sport_participant"("p_participant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."can_read_sport_participant"("p_participant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."can_read_sport_participant"("p_participant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."can_read_sport_workflow"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."can_read_sport_workflow"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."can_read_sport_workflow"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."capture_player_alias"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."close_due_match_motm_elections"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."close_match_motm_election"("p_match_id" "uuid", "p_require_due" boolean) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."composition_snapshot"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."composition_snapshot"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."composition_snapshot"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "private"."configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "private"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."create_match_with_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."create_match_with_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "private"."create_match_with_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "private"."create_player_identity"("p_display_name" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."create_sport_availability_notification"("p_match_id" "uuid", "p_participant_id" "uuid", "p_profile_id" "uuid", "p_kind" "text", "p_source" "text", "p_scheduled_for" timestamp with time zone, "p_requested_by" "uuid", "p_reason" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."dispatch_convocation_push"("p_match_id" "uuid", "p_profile_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."dispatch_motm_push"("p_kind" "text", "p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."dispatch_motm_result_notification"("p_kind" "text", "p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."dispatch_sport_notification_event"("p_event_id" bigint) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."end_match_live"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."end_match_live"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."end_match_live"("p_match_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."enrich_match_convocation_history"("p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."enrich_match_convocation_history"("p_payload" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."enrich_sport_waitlist_history"("p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."enrich_sport_waitlist_history"("p_payload" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."ensure_guest_player_identity"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."ensure_historical_player_identity"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."ensure_match_motm_election"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."ensure_profile_player_identity"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."ensure_season_player_identity"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."ensure_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."ensure_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."ensure_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."finalize_due_waitlist_turns_for_season"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."finalize_due_waitlist_turns_for_season"("p_season_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."finalize_due_waitlist_turns_for_season"("p_season_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."finalize_match_waitlist_turns_internal"("p_match_id" "uuid", "p_force" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."finalize_match_waitlist_turns_internal"("p_match_id" "uuid", "p_force" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "private"."finalize_match_waitlist_turns_internal"("p_match_id" "uuid", "p_force" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_admin_match_composition"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_admin_match_composition"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_admin_match_composition"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_admin_match_motm_dashboard"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_admin_match_motm_dashboard"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_admin_match_motm_dashboard"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_admin_match_sport_finalization"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_admin_match_sport_finalization"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_admin_match_sport_finalization"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_all_historical_match_results"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_all_historical_match_results"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_all_historical_match_results"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_finished_bench_counts"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_finished_bench_counts"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_finished_bench_counts"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_guest_players"("p_include_archived" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_guest_players"("p_include_archived" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_guest_players"("p_include_archived" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_historical_match_detail"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_historical_match_detail"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_historical_match_detail"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_historical_match_results"("p_season_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_historical_match_results"("p_season_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_historical_match_results"("p_season_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_match_availability_board"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_availability_board"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_match_availability_board"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_match_convocations"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_convocations"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_match_convocations"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_match_guests"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_guests"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_match_guests"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_match_live_add_player_options"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_live_add_player_options"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_match_live_add_player_options"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_match_live_timeline"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_live_timeline"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_match_live_timeline"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_match_motm_vote"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_motm_vote"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."get_match_sport_statistics_integrity"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_match_sport_statistics_integrity"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_match_sport_statistics_integrity"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_my_match_availability"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_my_match_availability"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_my_match_availability"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_notifications_paused"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_notifications_paused"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_notifications_paused"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_player_position_history"("p_since" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_player_position_history"("p_since" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_player_position_history"("p_since" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_public_feature_flags"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_public_feature_flags"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_public_feature_flags"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_published_match_composition"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_published_match_composition"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_published_match_composition"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_published_match_sport_result"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_published_match_sport_result"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_published_match_sport_result"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_sport_availability_reminder_summary"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_sport_availability_reminder_summary"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_sport_availability_reminder_summary"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_sport_waitlist"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_sport_waitlist"("p_season_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."get_sport_waitlist"("p_season_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."get_sport_waitlist_readonly"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."get_sport_waitlist_readonly"("p_season_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."guard_finished_match_composition_write"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."guard_match_archive_transition"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."guard_match_lifecycle_write"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."guard_match_status_chronology"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."guard_postgame_correction_window"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."handle_convoked_withdrawal"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."handle_convoked_withdrawal"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."handle_convoked_withdrawal"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."handle_match_notification_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."is_active_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_active_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."is_active_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."is_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."is_feature_enabled"("p_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_feature_enabled"("p_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."is_feature_enabled"("p_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."is_known_non_player_archive_name"("p_name" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."is_match_coach_or_admin"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_match_coach_or_admin"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."is_match_coach_or_admin"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."is_match_staff"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_match_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."is_match_staff"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."is_moderator"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_moderator"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."is_moderator"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."list_admin_match_motm_votes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."list_admin_match_motm_votes"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."list_admin_match_motm_votes"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."match_features_open_at"("p_kickoff_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_has_eligible_motm_ballot"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_live_snapshot"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."match_live_snapshot"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."match_live_snapshot"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."match_motm_anchor_version"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_motm_candidate_participants"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_motm_opens_at"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_motm_result_notification_payloads"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_notification_time_label"("p_kickoff_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_postgame_correction_closes_at"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_prediction_closes_at"("p_kickoff_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_prediction_notification_at"("p_kickoff_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."match_sport_finalization_snapshot"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."match_sport_finalization_snapshot"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."match_sport_finalization_snapshot"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."match_weather_refresh_interval"("p_kickoff_at" timestamp with time zone, "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."match_weather_refresh_interval"("p_kickoff_at" timestamp with time zone, "p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "private"."merge_player_identities"("p_source_player_id" "uuid", "p_target_player_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."normalize_player_name"("p_name" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."normalize_waitlisted_withdrawal"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."normalize_waitlisted_withdrawal"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."notify_admins_of_pending_signup"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."notify_waitlist_promotion"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "private"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) TO "service_role";



REVOKE ALL ON FUNCTION "private"."override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."process_match_motm_jobs"("p_now" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."process_sport_availability_notifications"("p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."process_sport_availability_notifications"("p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "private"."publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."push_due_motm_open_notifications"("p_now" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."push_due_motm_result_notifications"("p_now" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."recompute_match_convocations_internal"("p_match_id" "uuid", "p_reset_overrides" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."recompute_match_convocations_internal"("p_match_id" "uuid", "p_reset_overrides" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "private"."recompute_match_convocations_internal"("p_match_id" "uuid", "p_reset_overrides" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "private"."refresh_historical_match_players"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."reopen_match_live"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."reopen_match_live"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."reopen_match_live"("p_match_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."request_match_weather_refresh"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."request_match_weather_refresh"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."require_sports_management_enabled"() FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."require_sports_management_enabled"() TO "authenticated";
GRANT ALL ON FUNCTION "private"."require_sports_management_enabled"() TO "service_role";



REVOKE ALL ON FUNCTION "private"."resequence_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."resequence_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."resequence_sport_waitlist"("p_season_id" "uuid", "p_actor" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."reset_internal_match_composition_on_first_effectif_publish"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."resolve_historical_player_name"("p_name" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."resolve_open_sport_season"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."resolve_open_sport_season"("p_season_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."resolve_open_sport_season"("p_season_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."restore_returning_convoked_player"("p_match_id" "uuid", "p_participant_id" "uuid", "p_actor" "uuid", "p_actor_kind" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "private"."save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "private"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "private"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "private"."send_sport_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."send_sport_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."send_sport_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "private"."set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_notifications_paused"("p_enabled" boolean, "p_justification" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_notifications_paused"("p_enabled" boolean, "p_justification" "text") TO "authenticated";
GRANT ALL ON FUNCTION "private"."set_notifications_paused"("p_enabled" boolean, "p_justification" "text") TO "service_role";



REVOKE ALL ON FUNCTION "private"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."signal_feature_flag_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."signal_shared_data_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."sync_historical_match_players"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."sync_match_sport_workflow"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."sync_match_sport_workflow"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "private"."sync_match_sport_workflow"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "private"."transition_match_motm_election"("p_match_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."trg_reset_match_motm_after_finalization"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."try_motm_result_notification"("p_kind" "text", "p_match_id" "uuid", "p_sent_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."update_match_with_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."update_match_with_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "private"."update_match_with_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "private"."update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_add_or_reuse_match_guest"("p_match_id" "uuid", "p_guest_player_id" "uuid", "p_first_name" "text", "p_last_name" "text", "p_is_goalkeeper" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_cancel_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_close_match_motm_vote_early"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_configure_match_sport_workflow"("p_match_id" "uuid", "p_squad_size_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_create_match_complete"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_match_complete"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_create_match_complete"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_create_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_finalize_match_sport_postgame"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_finalize_match_waitlist_turns"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_finalize_match_waitlist_turns"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_finalize_match_waitlist_turns"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_finished_bench_counts"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_finished_bench_counts"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_finished_bench_counts"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_guest_players"("p_include_archived" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_guest_players"("p_include_archived" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_guest_players"("p_include_archived" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_internal_composition"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_internal_composition"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_internal_composition"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_availability_reminders"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_availability_reminders"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_availability_reminders"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_composition"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_composition"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_composition"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_convocations"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_convocations"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_convocations"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_guests"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_guests"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_guests"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_motm_dashboard"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_motm_dashboard"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_motm_dashboard"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_sport_finalization"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_sport_finalization"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_sport_finalization"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_match_sport_statistics_integrity"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_match_sport_statistics_integrity"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_match_sport_statistics_integrity"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_notifications_paused"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_notifications_paused"() TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_notifications_paused"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_player_position_history"("p_since" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_player_position_history"("p_since" timestamp with time zone) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_player_position_history"("p_since" timestamp with time zone) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_get_sport_waitlist"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_get_sport_waitlist"("p_season_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_get_sport_waitlist"("p_season_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_list_match_motm_votes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_list_match_motm_votes"() TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_list_match_motm_votes"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_override_match_availability"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_private_comment" "text", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_publish_match_convocations"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_publish_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_recompute_match_convocations"("p_match_id" "uuid", "p_reset_overrides" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_recompute_match_convocations"("p_match_id" "uuid", "p_reset_overrides" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_recompute_match_convocations"("p_match_id" "uuid", "p_reset_overrides" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_remove_match_guest"("p_match_id" "uuid", "p_participant_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_reorder_sport_waitlist"("p_season_id" "uuid", "p_ordered_player_ids" "uuid"[], "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_require_password_change"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_require_password_change"("p_profile_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_require_password_change"("p_profile_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_restart_match_motm_vote"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_save_internal_composition"("p_match_id" "uuid", "p_team1_name" "text", "p_team2_name" "text", "p_entries" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_save_internal_composition"("p_match_id" "uuid", "p_team1_name" "text", "p_team2_name" "text", "p_entries" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_save_internal_composition"("p_match_id" "uuid", "p_team1_name" "text", "p_team2_name" "text", "p_entries" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_save_match_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_save_match_effectif"("p_match_id" "uuid", "p_squad_size_limit" integer, "p_decisions" "jsonb", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_send_custom_push"("p_title" "text", "p_body" "text", "p_profile_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_send_custom_push"("p_title" "text", "p_body" "text", "p_profile_ids" "uuid"[]) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_send_custom_push"("p_title" "text", "p_body" "text", "p_profile_ids" "uuid"[]) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_send_match_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_send_match_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_send_match_availability_reminder"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_guest_archived"("p_guest_player_id" "uuid", "p_archived" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_guest_photo"("p_guest_player_id" "uuid", "p_photo_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_guest_photo"("p_guest_player_id" "uuid", "p_photo_url" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_guest_photo"("p_guest_player_id" "uuid", "p_photo_url" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_match_address"("p_match_id" "uuid", "p_address" "text", "p_remember_as_default" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_match_address"("p_match_id" "uuid", "p_address" "text", "p_remember_as_default" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_match_address"("p_match_id" "uuid", "p_address" "text", "p_remember_as_default" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_match_convocation"("p_match_id" "uuid", "p_season_player_id" "uuid", "p_status" "text", "p_turn_should_consume" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_match_jersey"("p_match_id" "uuid", "p_jersey_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_match_jersey"("p_match_id" "uuid", "p_jersey_note" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_match_jersey"("p_match_id" "uuid", "p_jersey_note" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_match_type"("p_match_id" "uuid", "p_match_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_match_type"("p_match_id" "uuid", "p_match_type" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_match_type"("p_match_id" "uuid", "p_match_type" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_notifications_paused"("p_enabled" boolean, "p_justification" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_notifications_paused"("p_enabled" boolean, "p_justification" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_notifications_paused"("p_enabled" boolean, "p_justification" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_waitlist_manual_count"("p_season_player_id" "uuid", "p_count" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_waitlist_manual_count"("p_season_player_id" "uuid", "p_count" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_set_waitlist_manual_count"("p_season_player_id" "uuid", "p_count" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_sync_match_sport_workflow"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_sync_match_sport_workflow"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_sync_match_sport_workflow"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_update_match_complete"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_match_complete"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_update_match_complete"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer, "p_address" "text", "p_remember_address_as_default" boolean, "p_match_type" "text", "p_jersey_note" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_update_postmatch_composition"("p_match_id" "uuid", "p_formation_code" "text", "p_entries" "jsonb", "p_allow_squad_size_exception" boolean, "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_update_profile_fields"("p_profile_id" "uuid", "p_role" "text", "p_status" "text", "p_is_goalkeeper" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_profile_fields"("p_profile_id" "uuid", "p_role" "text", "p_status" "text", "p_is_goalkeeper" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."admin_update_profile_fields"("p_profile_id" "uuid", "p_role" "text", "p_status" "text", "p_is_goalkeeper" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."archive_match"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."archive_match"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."archive_match"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."award_season_titles"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."award_season_titles"("p_season_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."calculate_match_odds_v4"("p_opponent_id" "uuid", "p_location" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."calculate_match_odds_v4"("p_opponent_id" "uuid", "p_location" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."calculate_match_odds_v5"("p_opponent_id" "uuid", "p_reference_date" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."calculate_match_odds_v5"("p_opponent_id" "uuid", "p_reference_date" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_match"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_match"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."cancel_match"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."cast_match_motm_vote"("p_match_id" "uuid", "p_candidate_participant_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cleanup_replaced_photo"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cleanup_replaced_photo"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."close_match_predictions"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."close_match_predictions"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_match_predictions"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."coach_add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_add_match_live_players"("p_match_id" "uuid", "p_players" "jsonb", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_adjust_match_live_score"("p_match_id" "uuid", "p_team" "text", "p_delta" integer, "p_scorer_participant_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_delete_match_live_event"("p_match_id" "uuid", "p_event_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_end_match_live"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_end_match_live"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_end_match_live"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_publish_match_live_recap"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_participants" "jsonb", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_reopen_match_live"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_reopen_match_live"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_reopen_match_live"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_restart_match_live_session"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_save_match_live_lineup"("p_match_id" "uuid", "p_entries" "jsonb", "p_substitution" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_set_match_live_clock_state"("p_match_id" "uuid", "p_action" "text", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."coach_set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."coach_set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."coach_set_match_live_event_scorer"("p_match_id" "uuid", "p_event_id" "uuid", "p_scorer_participant_id" "uuid", "p_is_opponent_own_goal" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."complete_password_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_password_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_password_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."confirm_start_match_live"("p_match_id" "uuid", "p_reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."consume_registration_rate_limit"("p_origin_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."consume_registration_rate_limit"("p_origin_hash" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_internal_match"("p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_address" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_internal_match"("p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_address" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_internal_match"("p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_address" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_match_with_odds"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_match_with_odds"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_match_with_odds"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_match_with_odds_and_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_match_with_odds_and_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."create_match_with_odds_and_sport_limit"("p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."current_profile_role"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_profile_role"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_match"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_match"("p_match_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_match"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."featured_badges"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."featured_badges"() TO "service_role";
GRANT ALL ON FUNCTION "public"."featured_badges"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."finalize_match_postgame"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_match_postgame"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_match_postgame_with_lineup"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer, "p_present" "uuid"[], "p_man_of_match_player_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_match_postgame_with_lineup"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer, "p_present" "uuid"[], "p_man_of_match_player_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."finalize_match_postgame_with_lineup"("p_match_id" "uuid", "p_score_adverse" integer, "p_scorers" "jsonb", "p_clean_sheet_player_id" "uuid", "p_score_as_grinta" integer, "p_present" "uuid"[], "p_man_of_match_player_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_all_historical_match_results"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_all_historical_match_results"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_all_historical_match_results"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_historical_match_detail"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_historical_match_detail"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_historical_match_detail"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_historical_match_results"("p_season_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_historical_match_results"("p_season_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_historical_match_results"("p_season_name" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_last_opponent_encounters"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_last_opponent_encounters"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_last_opponent_encounters"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_match_availability_board"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_match_availability_board"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_match_availability_board"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_match_live_add_player_options"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_match_live_add_player_options"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_match_live_add_player_options"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_match_live_state"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_match_live_state"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_match_live_state"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_match_live_timeline"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_match_live_timeline"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_match_live_timeline"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_match_motm_vote"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_match_motm_vote"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_match_motm_vote"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_match_sport_result"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_match_sport_result"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_match_sport_result"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_my_match_availability"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_match_availability"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_my_match_availability"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_my_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_or_create_opponent"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_or_create_opponent"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_opponent"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_public_feature_flags"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_public_feature_flags"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_public_feature_flags"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_published_match_composition"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_published_match_composition"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_published_match_composition"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_sport_waitlist"("p_season_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_sport_waitlist"("p_season_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."get_sport_waitlist"("p_season_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."guard_match_prediction_window"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_match_prediction_window"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_sensitive_profile_fields"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_sensitive_profile_fields"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_auth_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_mark_sport_notification_delivery"("p_event_id" bigint, "p_attempted" integer, "p_sent" integer, "p_failed" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_mark_sport_notification_delivery"("p_event_id" bigint, "p_attempted" integer, "p_sent" integer, "p_failed" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_match_weather_candidates"("p_match_id" "uuid", "p_now" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_match_weather_candidates"("p_match_id" "uuid", "p_now" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_push_config"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_push_config"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_push_delivery_health"("p_since" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_push_delivery_health"("p_since" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_push_dispatch"("p_kind" "text", "p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_push_dispatch"("p_kind" "text", "p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_push_notify"("p_kind" "text", "p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_push_notify"("p_kind" "text", "p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_push_prune"("p_endpoints" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_push_prune"("p_endpoints" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."internal_sport_push_dispatch"("p_kind" "text", "p_match_id" "uuid", "p_profile_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."internal_sport_push_dispatch"("p_kind" "text", "p_match_id" "uuid", "p_profile_ids" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_active_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_active_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_match_staff"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_match_staff"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_match_staff"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_moderator"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_moderator"() TO "service_role";
GRANT ALL ON FUNCTION "public"."is_moderator"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_valid_person_name"("txt" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_valid_person_name"("txt" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."match_prediction_participant_count"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."match_prediction_participant_count"("p_match_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."match_prediction_participant_count"("p_match_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."open_match_live_workspace"("p_match_id" "uuid", "p_planned_duration_minutes" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."open_or_create_season"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."open_or_create_season"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."open_or_create_season"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prepare_profile_for_hard_deletion"("p_profile_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."preview_match_odds"("p_opponent_id" "uuid", "p_location" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."preview_match_odds"("p_opponent_id" "uuid", "p_location" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."preview_match_odds"("p_opponent_id" "uuid", "p_location" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."profile_badge_metrics"("p_profile_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."profile_badge_stars"("p_profile_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."profile_mvp_count"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."profile_mvp_count"("p_profile_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."push_closing_reminders"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."push_closing_reminders"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."push_on_match_insert"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."push_on_match_insert"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."push_on_motm_election_closed"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."push_on_motm_election_closed"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."push_on_motm_election_opened"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."push_on_motm_election_opened"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."push_prediction_j5_notifications"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."push_prediction_j5_notifications"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."recalculate_all_badges"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recalculate_all_badges"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."recalculate_profile_badges"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recalculate_profile_badges"("p_profile_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."recalculate_upcoming_match_odds_v4"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recalculate_upcoming_match_odds_v4"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_push_subscription"("p_endpoint" "text", "p_p256dh" "text", "p_auth" "text", "p_user_agent" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_push_subscription"("p_endpoint" "text", "p_p256dh" "text", "p_auth" "text", "p_user_agent" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_push_subscription"("p_endpoint" "text", "p_p256dh" "text", "p_auth" "text", "p_user_agent" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_use_x2" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_use_x2" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."save_match_prediction"("p_match_id" "uuid", "p_score_as_grinta" integer, "p_score_adverse" integer, "p_use_x2" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_my_season_predictions"("p_season_id" "uuid", "p_items" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."seed_match_predictions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seed_match_predictions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."seed_predictions_for_active_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seed_predictions_for_active_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."seed_season_predictions_for_player"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."seed_season_predictions_for_player"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_test_push"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_test_push"() TO "service_role";
GRANT ALL ON FUNCTION "public"."send_test_push"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_badge_featured"("p_badge_code" "text", "p_featured" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_badge_featured"("p_badge_code" "text", "p_featured" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."set_badge_featured"("p_badge_code" "text", "p_featured" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_match_odds"("p_match_id" "uuid", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_match_odds"("p_match_id" "uuid", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_my_match_availability"("p_match_id" "uuid", "p_status" "text", "p_private_comment" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."set_season_predictions_lock"("p_season_id" "uuid", "p_locked" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_season_predictions_lock"("p_season_id" "uuid", "p_locked" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_season_predictions_lock"("p_season_id" "uuid", "p_locked" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_season_status"("p_season_id" "uuid", "p_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_season_status"("p_season_id" "uuid", "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_season_status"("p_season_id" "uuid", "p_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."set_sports_management_enabled"("p_enabled" boolean, "p_justification" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_app_integrity_report"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_app_integrity_report"() TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_app_integrity_report"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_award_badge"("p_profile_id" "uuid", "p_badge_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_award_badge"("p_profile_id" "uuid", "p_badge_code" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_award_badge"("p_profile_id" "uuid", "p_badge_code" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_create_badge"("p_code" "text", "p_name" "text", "p_emoji" "text", "p_description" "text", "p_image_url" "text", "p_color" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_create_badge"("p_code" "text", "p_name" "text", "p_emoji" "text", "p_description" "text", "p_image_url" "text", "p_color" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_create_badge"("p_code" "text", "p_name" "text", "p_emoji" "text", "p_description" "text", "p_image_url" "text", "p_color" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_list_historical_players"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_list_historical_players"() TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_list_historical_players"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_list_profiles"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_list_profiles"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."staff_list_profiles"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."staff_profile_username"("p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_profile_username"("p_profile_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."staff_profile_username"("p_profile_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."staff_revoke_badge"("p_profile_id" "uuid", "p_badge_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_revoke_badge"("p_profile_id" "uuid", "p_badge_code" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_revoke_badge"("p_profile_id" "uuid", "p_badge_code" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_set_historical_profile"("p_profile_id" "uuid", "p_historical_id" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_set_historical_profile"("p_profile_id" "uuid", "p_historical_id" bigint) TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_set_historical_profile"("p_profile_id" "uuid", "p_historical_id" bigint) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_set_match_attendance"("p_match_id" "uuid", "p_present" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_set_match_attendance"("p_match_id" "uuid", "p_present" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."staff_set_match_mvp"("p_match_id" "uuid", "p_players" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_set_match_mvp"("p_match_id" "uuid", "p_players" "uuid"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."staff_set_season_player_profile"("p_season_player_id" "uuid", "p_profile_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_set_season_player_profile"("p_season_player_id" "uuid", "p_profile_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_set_season_player_profile"("p_season_player_id" "uuid", "p_profile_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."staff_validate_profile"("p_profile_id" "uuid", "p_season_player_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."staff_validate_profile"("p_profile_id" "uuid", "p_season_player_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."staff_validate_profile"("p_profile_id" "uuid", "p_season_player_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."sync_match_kickoff_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_match_kickoff_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_award_titles_on_season_close"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_award_titles_on_season_close"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_attendance"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_attendance"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_historical_link"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_historical_link"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_match_result"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_match_result"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_mvp"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_mvp"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_player_stats"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_player_stats"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_prediction"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_prediction"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trg_badges_on_roster_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trg_badges_on_roster_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trigger_match_odds_v4"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trigger_match_odds_v4"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."trigger_recalculate_upcoming_odds_v3"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."trigger_recalculate_upcoming_odds_v3"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_internal_match"("p_match_id" "uuid", "p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_internal_match"("p_match_id" "uuid", "p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_internal_match"("p_match_id" "uuid", "p_season_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_match_with_odds"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_match_with_odds"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_match_with_odds"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_match_with_odds_and_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_match_with_odds_and_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_match_with_odds_and_sport_limit"("p_match_id" "uuid", "p_season_id" "uuid", "p_opponent_id" "uuid", "p_match_date" "date", "p_match_time" time without time zone, "p_location" "text", "p_status" "text", "p_win" numeric, "p_draw" numeric, "p_loss" numeric, "p_squad_size_limit" integer) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_my_app_preferences"("p_notify_prediction_open" boolean, "p_notify_prediction_reminders" boolean, "p_notify_match_reminders" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_app_preferences"("p_notify_prediction_open" boolean, "p_notify_prediction_reminders" boolean, "p_notify_match_reminders" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_my_app_preferences"("p_notify_prediction_open" boolean, "p_notify_prediction_reminders" boolean, "p_notify_match_reminders" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_my_notification_preferences"("p_notify_prediction" boolean, "p_notify_motm_vote" boolean, "p_notify_convocation" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_my_notification_preferences"("p_notify_prediction" boolean, "p_notify_motm_vote" boolean, "p_notify_convocation" boolean) TO "service_role";
GRANT ALL ON FUNCTION "public"."update_my_notification_preferences"("p_notify_prediction" boolean, "p_notify_motm_vote" boolean, "p_notify_convocation" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."upsert_match_odds_v4"("p_match_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."upsert_match_odds_v4"("p_match_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_profile_names"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_profile_names"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_season_prediction_row"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_season_prediction_row"() TO "service_role";



GRANT SELECT,INSERT ON TABLE "private"."app_feature_flag_audit" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "private"."app_feature_flag_audit_id_seq" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "private"."app_feature_flags" TO "service_role";



GRANT SELECT,INSERT ON TABLE "private"."sport_admin_audit_log" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "private"."sport_admin_audit_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."badge_inbox_state" TO "service_role";
GRANT SELECT,INSERT,UPDATE ON TABLE "public"."badge_inbox_state" TO "authenticated";



GRANT ALL ON TABLE "public"."badges" TO "authenticated";
GRANT ALL ON TABLE "public"."badges" TO "service_role";



GRANT ALL ON TABLE "public"."club_events" TO "authenticated";
GRANT ALL ON TABLE "public"."club_events" TO "service_role";



GRANT ALL ON TABLE "public"."club_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."club_settings" TO "service_role";



GRANT ALL ON TABLE "public"."feature_flag_change_signals" TO "service_role";
GRANT SELECT ON TABLE "public"."feature_flag_change_signals" TO "authenticated";



GRANT ALL ON TABLE "public"."guest_players" TO "service_role";
GRANT SELECT ON TABLE "public"."guest_players" TO "authenticated";



GRANT ALL ON TABLE "public"."historical_match_details" TO "authenticated";
GRANT ALL ON TABLE "public"."historical_match_details" TO "service_role";



GRANT ALL ON TABLE "public"."historical_match_players" TO "service_role";



GRANT ALL ON TABLE "public"."historical_match_scores" TO "service_role";



GRANT ALL ON TABLE "public"."historical_player_name_links" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."historical_player_statistics" TO "authenticated";
GRANT ALL ON TABLE "public"."historical_player_statistics" TO "service_role";



GRANT ALL ON SEQUENCE "public"."historical_player_statistics_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."historical_player_statistics_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."historical_team_statistics" TO "service_role";
GRANT SELECT ON TABLE "public"."historical_team_statistics" TO "authenticated";



GRANT ALL ON TABLE "public"."match_attendance" TO "authenticated";
GRANT ALL ON TABLE "public"."match_attendance" TO "service_role";



GRANT ALL ON TABLE "public"."match_composition_entries" TO "service_role";



GRANT ALL ON TABLE "public"."match_composition_publications" TO "service_role";
GRANT SELECT ON TABLE "public"."match_composition_publications" TO "authenticated";



GRANT ALL ON TABLE "public"."match_compositions" TO "service_role";



GRANT ALL ON TABLE "public"."match_internal_composition_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."match_internal_composition_entries" TO "service_role";



GRANT ALL ON TABLE "public"."match_internal_compositions" TO "authenticated";
GRANT ALL ON TABLE "public"."match_internal_compositions" TO "service_role";



GRANT ALL ON TABLE "public"."match_live_events" TO "service_role";
GRANT SELECT ON TABLE "public"."match_live_events" TO "authenticated";



GRANT ALL ON TABLE "public"."match_live_sessions" TO "service_role";
GRANT SELECT ON TABLE "public"."match_live_sessions" TO "authenticated";



GRANT ALL ON TABLE "public"."match_man_of_match" TO "authenticated";
GRANT ALL ON TABLE "public"."match_man_of_match" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."match_odds" TO "authenticated";
GRANT ALL ON TABLE "public"."match_odds" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."match_player_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."match_player_stats" TO "service_role";



GRANT SELECT,INSERT,MAINTAIN,UPDATE ON TABLE "public"."match_predictions" TO "authenticated";
GRANT ALL ON TABLE "public"."match_predictions" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_finalization_versions" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_finalizations" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_motm_elections" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_motm_results" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_motm_votes" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_participant_events" TO "service_role";
GRANT SELECT ON TABLE "public"."match_sport_participant_events" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."match_sport_participant_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."match_sport_participants" TO "service_role";
GRANT SELECT ON TABLE "public"."match_sport_participants" TO "authenticated";



GRANT ALL ON TABLE "public"."match_sport_workflows" TO "service_role";
GRANT SELECT ON TABLE "public"."match_sport_workflows" TO "authenticated";



GRANT ALL ON TABLE "public"."match_weather" TO "service_role";
GRANT SELECT ON TABLE "public"."match_weather" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE "public"."matches" TO "authenticated";
GRANT ALL ON TABLE "public"."matches" TO "service_role";



GRANT SELECT("address") ON TABLE "public"."matches" TO "authenticated";



GRANT SELECT,DELETE,MAINTAIN,UPDATE ON TABLE "public"."opponents" TO "authenticated";
GRANT ALL ON TABLE "public"."opponents" TO "service_role";



GRANT SELECT("address") ON TABLE "public"."opponents" TO "authenticated";



GRANT ALL ON TABLE "public"."player_aliases" TO "service_role";



GRANT ALL ON SEQUENCE "public"."player_aliases_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."player_aliases_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."players" TO "service_role";



GRANT ALL ON TABLE "public"."profile_badge_seen" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_badge_seen" TO "service_role";



GRANT ALL ON TABLE "public"."profile_badges" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_badges" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT("id") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("first_name"),UPDATE("first_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("last_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("photo_url"),UPDATE("photo_url") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("status") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("updated_at") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT("surnom"),UPDATE("surnom") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."push_delivery_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."push_delivery_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."push_delivery_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."push_notification_log" TO "service_role";



GRANT ALL ON TABLE "public"."push_subscriptions" TO "service_role";
GRANT DELETE ON TABLE "public"."push_subscriptions" TO "authenticated";



GRANT ALL ON TABLE "public"."season_awards" TO "authenticated";
GRANT ALL ON TABLE "public"."season_awards" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE "public"."season_players" TO "authenticated";
GRANT ALL ON TABLE "public"."season_players" TO "service_role";



GRANT SELECT("is_coach"),INSERT("is_coach"),UPDATE("is_coach") ON TABLE "public"."season_players" TO "authenticated";



GRANT SELECT,INSERT,MAINTAIN,UPDATE ON TABLE "public"."season_predictions" TO "authenticated";
GRANT ALL ON TABLE "public"."season_predictions" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE "public"."seasons" TO "authenticated";
GRANT ALL ON TABLE "public"."seasons" TO "service_role";



GRANT ALL ON TABLE "public"."shared_data_change_signals" TO "service_role";
GRANT SELECT ON TABLE "public"."shared_data_change_signals" TO "authenticated";



GRANT ALL ON TABLE "public"."sport_availability_notification_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."sport_availability_notification_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."sport_waitlist_entries" TO "service_role";
GRANT SELECT ON TABLE "public"."sport_waitlist_entries" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."v_match_prediction_flags" TO "authenticated";
GRANT ALL ON TABLE "public"."v_match_prediction_flags" TO "service_role";



GRANT ALL ON TABLE "public"."v_match_prediction_points" TO "service_role";
GRANT SELECT ON TABLE "public"."v_match_prediction_points" TO "authenticated";



GRANT ALL ON TABLE "public"."v_player_season_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."v_player_season_stats" TO "service_role";



GRANT ALL ON TABLE "public"."v_season_match_count" TO "authenticated";
GRANT ALL ON TABLE "public"."v_season_match_count" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."v_season_prediction_bonus" TO "authenticated";
GRANT ALL ON TABLE "public"."v_season_prediction_bonus" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."v_season_prediction_flags" TO "authenticated";
GRANT ALL ON TABLE "public"."v_season_prediction_flags" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."v_season_prediction_points" TO "authenticated";
GRANT ALL ON TABLE "public"."v_season_prediction_points" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."v_classement_general" TO "authenticated";
GRANT ALL ON TABLE "public"."v_classement_general" TO "service_role";



GRANT ALL ON TABLE "public"."v_scorer_standings" TO "authenticated";
GRANT ALL ON TABLE "public"."v_scorer_standings" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."v_statistics_players" TO "authenticated";
GRANT ALL ON TABLE "public"."v_statistics_players" TO "service_role";



GRANT ALL ON TABLE "public"."v_statistics_team_dynamic_base" TO "service_role";
GRANT SELECT ON TABLE "public"."v_statistics_team_dynamic_base" TO "authenticated";



GRANT ALL ON TABLE "public"."v_statistics_team_with_recent_results" TO "authenticated";
GRANT ALL ON TABLE "public"."v_statistics_team_with_recent_results" TO "service_role";



GRANT ALL ON TABLE "public"."v_statistics_team" TO "authenticated";
GRANT ALL ON TABLE "public"."v_statistics_team" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";








-- App-owned Storage configuration. The storage schema itself is managed
-- by Supabase and already exists before application migrations run.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types, type)
values
  ('app-assets', 'app-assets', true, 10485760, array['image/png','image/jpeg','image/webp'], 'STANDARD'),
  ('badge-images', 'badge-images', true, 5242880, array['image/jpeg','image/png','image/webp'], 'STANDARD'),
  ('profile-photos', 'profile-photos', false, 5242880, array['image/jpeg','image/png','image/webp'], 'STANDARD')
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  type = excluded.type;

drop policy if exists "badge_images_admin_delete" on storage.objects;
create policy "badge_images_admin_delete" on storage.objects for delete to authenticated
using ((bucket_id = 'badge-images') and (select private.is_match_staff()));

drop policy if exists "badge_images_admin_insert" on storage.objects;
create policy "badge_images_admin_insert" on storage.objects for insert to authenticated
with check ((bucket_id = 'badge-images') and (select private.is_match_staff()));

drop policy if exists "badge_images_admin_update" on storage.objects;
create policy "badge_images_admin_update" on storage.objects for update to authenticated
using ((bucket_id = 'badge-images') and (select private.is_match_staff()))
with check ((bucket_id = 'badge-images') and (select private.is_match_staff()));

drop policy if exists "profile_photos_active_read" on storage.objects;
create policy "profile_photos_active_read" on storage.objects for select to authenticated
using ((bucket_id = 'profile-photos') and private.is_active_profile());

drop policy if exists "profile_photos_admin_write" on storage.objects;
create policy "profile_photos_admin_write" on storage.objects for all to authenticated
using ((bucket_id = 'profile-photos') and (select private.is_admin()))
with check ((bucket_id = 'profile-photos') and (select private.is_admin()));

drop policy if exists "profile_photos_owner_delete" on storage.objects;
create policy "profile_photos_owner_delete" on storage.objects for delete to authenticated
using ((bucket_id = 'profile-photos') and (select private.is_active_profile()) and owner_id = (select auth.uid())::text);

drop policy if exists "profile_photos_owner_insert" on storage.objects;
create policy "profile_photos_owner_insert" on storage.objects for insert to authenticated
with check ((bucket_id = 'profile-photos') and (select private.is_active_profile()) and owner_id = (select auth.uid())::text and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "profile_photos_owner_update" on storage.objects;
create policy "profile_photos_owner_update" on storage.objects for update to authenticated
using ((bucket_id = 'profile-photos') and (select private.is_active_profile()) and owner_id = (select auth.uid())::text)
with check ((bucket_id = 'profile-photos') and (select private.is_active_profile()) and owner_id = (select auth.uid())::text and (storage.foldername(name))[1] = (select auth.uid())::text);

insert into public.club_settings (id, home_address)
values (true, null)
on conflict (id) do nothing;

-- Canonical cross-schema auth trigger.
-- public.handle_new_auth_user() is part of the public schema dump, but
-- its trigger lives on Supabase-managed auth.users and therefore is not
-- emitted by a public/private-only schema dump.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of email, raw_user_meta_data on auth.users
  for each row execute function public.handle_new_auth_user();
