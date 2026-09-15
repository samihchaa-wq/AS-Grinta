begin;

-- ---------------------------------------------------------------------------
-- Le coach redevient un membre du club comme les autres.
--
-- Décision produit du 15 septembre 2026 : la case « Coach » ne retire plus
-- aucune fonctionnalité. Le coach reçoit toutes les notifications, répond aux
-- disponibilités, apparaît dans l'effectif du match dès qu'il se dit présent,
-- et vote comme n'importe quel convoqué.
--
-- Il reste en dehors de trois choses seulement, parce qu'il n'est pas un
-- joueur de rotation :
--   * la liste d'attente, l'ordre de passage et le quota de convoqués ;
--   * la composition d'équipe, le terrain, le banc et le Live ;
--   * les Statistiques Joueurs et les cibles du pari de saison.
--
-- La colonne match_sport_participants.is_eligible garde donc son sens actuel
-- (« joueur de rotation »). Le coach reste à false et chaque fonctionnalité
-- qui doit l'inclure le nomme désormais explicitement.
-- ---------------------------------------------------------------------------

create or replace function private.participant_is_coach(p_season_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.season_players player
    where player.id = p_season_player_id
      and player.is_coach
  );
$function$;

revoke execute on function private.participant_is_coach(uuid) from public, anon, authenticated;

comment on function private.participant_is_coach(uuid) is
  'True when the season player carries the sporting Coach attribute.';

-- ---------------------------------------------------------------------------
-- Convocations : le coach entre dans l'effectif dès qu'il se dit présent,
-- sans entrée de liste d'attente, sans tour à consommer et hors quota.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.recompute_match_convocations_internal(p_match_id uuid, p_reset_overrides boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- Le coach n'a pas d'entrée de liste d'attente : les deux mises à jour
  -- ci-dessus ne le touchent jamais. Sa seule réponse décide de sa présence
  -- dans l'effectif, et il n'y a aucune décision d'admin à prendre pour lui.
  update public.match_sport_participants participant
  set convocation_status = case
        when participant.availability_status = 'available'
          then 'convoked'::public.sport_convocation_status
        else 'not_applicable'::public.sport_convocation_status
      end,
      convocation_manual_override = false,
      waitlist_position_snapshot = null,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = false,
      waitlist_turn_state = 'not_applicable'::public.sport_waitlist_turn_state,
      updated_at = now()
  from public.season_players player
  where participant.match_id = p_match_id
    and player.id = participant.season_player_id
    and player.is_coach;

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

  -- Les compteurs restent ceux des joueurs de rotation : le coach ne prend
  -- la place de personne et ne fait pas bouger la limite d'effectif.
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
$function$;

-- ---------------------------------------------------------------------------
-- Disponibilité : la réponse du coach met à jour son effectif.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.set_my_match_availability(p_match_id uuid, p_status text, p_private_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_is_coach boolean;
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

  select participant.id, participant.is_eligible, player.is_coach,
    participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_is_eligible, v_is_coach, v_old_status, v_old_comment,
    v_workflow_state,
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

    -- Le coach répond comme tout le monde, mais il n'occupe aucune place de
    -- la rotation : sa réponse le pose dans l'effectif ou l'en retire sans
    -- jamais faire monter ni redescendre un joueur de la liste d'attente.
    if v_is_coach then
      perform private.recompute_match_convocations_internal(p_match_id, false);
    elsif v_is_eligible then
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
$function$;

-- ---------------------------------------------------------------------------
-- Effectif : le coach présent apparaît dans la liste, repéré par is_coach,
-- et reste hors des compteurs qui pilotent la limite de convoqués.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.get_match_convocations(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          'photo_url', row.photo_url,
          'is_guest', row.guest_player_id is not null,
          'is_coach', row.is_coach,
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
      ) filter (
        where row.participant_id is not null
          and (row.is_eligible or row.is_coach)
      ) as items
    from (
      select
        participant.id as participant_id,
        participant.season_player_id,
        participant.guest_player_id,
        participant.is_eligible,
        coalesce(player.is_coach, false) as is_coach,
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
        coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
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
$function$;

-- ---------------------------------------------------------------------------
-- Tableau des disponibilités : le coach y figure comme tout le monde.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.get_match_availability_board(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
        'is_coach', coalesce(player.is_coach, false),
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
   and (
     participant.is_eligible
     or private.participant_is_coach(participant.season_player_id)
   )
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
$function$;

-- ---------------------------------------------------------------------------
-- Le coach voit sa propre convocation comme n'importe quel convoqué.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.get_my_match_availability(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    'is_coach', player.is_coach,
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
      when workflow.convocation_state = 'published'
        and (participant.is_eligible or player.is_coach)
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
$function$;

-- ---------------------------------------------------------------------------
-- Ouverture des disponibilités : le coach est notifié comme les joueurs.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.process_sport_availability_notifications(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      and (participant.is_eligible or player.is_coach)
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
$function$;

-- ---------------------------------------------------------------------------
-- Relance manuelle d'un admin : le coach peut en être la cible.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.send_sport_availability_reminder(p_match_id uuid, p_season_player_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_row record;
  v_event_id bigint;
  v_created integer := 0;
  v_skipped_recent integer := 0;
  v_skipped_no_subscription integer := 0;
  v_target_count integer := 0;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if private.is_feature_enabled('notifications_paused') then
    raise exception 'Les notifications sont désactivées.' using errcode = '55000';
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
      and (participant.is_eligible or player.is_coach)
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

    if not exists (
      select 1
      from public.push_subscriptions subscription
      where subscription.profile_id = v_row.profile_id
    ) then
      v_skipped_no_subscription := v_skipped_no_subscription + 1;
      continue;
    end if;

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
      'skipped_recent_count', v_skipped_recent,
      'skipped_no_subscription_count', v_skipped_no_subscription
    )
  );

  return jsonb_build_object(
    'target_count', v_target_count,
    'created_count', v_created,
    'skipped_recent_count', v_skipped_recent,
    'skipped_no_subscription_count', v_skipped_no_subscription
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Suivi des relances : le coach sans réponse y apparaît, donc un admin
-- peut le relancer comme n'importe quel joueur.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.get_sport_availability_reminder_summary(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        )
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
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        )
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
$function$;

-- ---------------------------------------------------------------------------
-- Un admin peut corriger la disponibilité du coach comme celle d'un joueur.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.override_match_availability(p_match_id uuid, p_season_player_id uuid, p_status text, p_private_comment text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and (
      participant.is_eligible
      or private.participant_is_coach(participant.season_player_id)
    )
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

    -- Le coach n'occupe aucune place de la rotation : le faire entrer ou
    -- sortir de l'effectif ne promeut ni ne redescend personne.
    if private.participant_is_coach(p_season_player_id) then
      perform private.recompute_match_convocations_internal(p_match_id, false);
    elsif v_convocation_state = 'published'
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
$function$;

-- ---------------------------------------------------------------------------
-- Changement de match : la réponse du coach est remise à zéro comme
-- celle des joueurs, et il reçoit la notification de changement.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.handle_match_notification_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_in_old_window boolean := false;
  v_date_changed boolean := false;
  v_old_opens_at timestamptz;
  v_mode text := 'automatic';
  v_new_opens_at timestamptz;
  v_new_state public.sport_availability_state;
begin
  select workflow.availability_opens_at, workflow.availability_schedule_mode
  into v_old_opens_at, v_mode
  from public.match_sport_workflows workflow
  where workflow.match_id = old.id;

  v_old_opens_at := coalesce(v_old_opens_at, private.match_features_open_at(old.kickoff_at));
  v_mode := coalesce(v_mode, 'automatic');

  if old.kickoff_at is not null then
    v_in_old_window := now() >= v_old_opens_at and now() < old.kickoff_at;
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
      if v_mode = 'automatic' then
        v_new_opens_at := private.match_features_open_at(new.kickoff_at);
      else
        v_new_opens_at := v_old_opens_at;
        if v_new_opens_at >= new.kickoff_at then
          v_mode := 'automatic';
          v_new_opens_at := private.match_features_open_at(new.kickoff_at);
        end if;
      end if;

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
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        );

      update public.match_sport_workflows workflow
      set availability_opens_at = v_new_opens_at,
          availability_schedule_mode = v_mode,
          availability_state = v_new_state,
          availability_opened_at = case
            when v_new_state = 'open' then coalesce(workflow.availability_opened_at, now())
            else null
          end,
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
$function$;

-- ---------------------------------------------------------------------------
-- Composition publiée : le coach convoqué reçoit la notification.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.notify_composition_published(p_match_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_status text;
  v_match_type text;
  v_kickoff_at timestamptz;
  v_first boolean;
  v_profile_ids uuid[];
begin
  select m.status, m.match_type, m.kickoff_at
  into v_status, v_match_type, v_kickoff_at
  from public.matches m
  where m.id = p_match_id;

  if not found or v_status <> 'a_venir' or v_kickoff_at is null then
    return false;
  end if;
  if now() >= v_kickoff_at then
    return false;
  end if;

  if v_match_type = 'entre_nous' then
    -- Aucun ancien client, sauvegarde papier ou RPC historique ne peut
    -- consommer la notification : seul V5 pose ce marqueur transactionnel.
    if coalesce(
      pg_catalog.current_setting(
        'as_grinta.internal_visual_publish',
        true
      ),
      ''
    ) <> '1' then
      return false;
    end if;

    if not private.internal_composition_visual_is_complete(p_match_id) then
      return false;
    end if;
  end if;

  insert into public.push_notification_log(match_id, kind, sent_at)
  values (p_match_id, 'composition_published', now())
  on conflict (match_id, kind) do nothing;

  get diagnostics v_first = row_count;
  if not v_first then
    return false;
  end if;

  if v_match_type = 'entre_nous' then
    -- « Tous » signifie tous les profils actifs qui ont conservé le réglage
    -- de notification de composition activé, pas seulement les convoqués.
    select array_agg(profile.id order by profile.id)
    into v_profile_ids
    from public.profiles profile
    where profile.status = 'active'
      and profile.notify_composition;
  else
    select array_agg(distinct player.profile_id)
    into v_profile_ids
    from public.match_sport_participants participant
    join public.season_players player
      on player.id = participant.season_player_id
    join public.profiles profile
      on profile.id = player.profile_id
    where participant.match_id = p_match_id
      and (participant.is_eligible or player.is_coach)
      and participant.convocation_status = 'convoked'
      and profile.status = 'active'
      and profile.notify_composition;
  end if;

  if v_profile_ids is null or cardinality(v_profile_ids) = 0 then
    return false;
  end if;

  return private.dispatch_composition_published_push(p_match_id, v_profile_ids);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Ciblage des pushs sportifs : le coach compte parmi les destinataires.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.internal_sport_push_dispatch(p_kind text, p_match_id uuid, p_profile_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  select m.id, m.kickoff_at, nullif(btrim(o.name), '') as opponent_name
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
      'body', case
        when v_match.opponent_name is null then format(
          'Dispo pour le match entre nous du %s à %s ?',
          v_date, v_time
        )
        else format(
          'Dispo pour le match du %s contre %s à %s ?',
          v_date, v_match.opponent_name, v_time
        )
      end,
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-availability-open'
    )
    when 'availability_manual' then jsonb_build_object(
      'title', 'Tu n''as pas répondu 👀',
      'body', case
        when v_match.opponent_name is null then
          'Pense à indiquer si tu es dispo pour le match entre nous !'
        else format(
          'Pense à indiquer si tu es dispo pour le match contre %s !',
          v_match.opponent_name
        )
      end,
      'url', 'matches/' || p_match_id || '/lineup?section=effectif',
      'tag', 'sport-' || p_match_id || '-availability-manual'
    )
    else jsonb_build_object(
      'title', 'Tu es convoqué',
      'body', case
        when v_match.opponent_name is null then format(
          'Tu es convoqué pour le match entre nous du %s.',
          v_date
        )
        else format(
          'Tu es convoqué pour le match du %s contre %s.',
          v_date, v_match.opponent_name
        )
      end,
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
          and (participant.is_eligible or player.is_coach)
          and player.profile_id = subscription.profile_id
      ))
      or (p_kind = 'availability_manual' and exists (
        select 1
        from public.match_sport_participants participant
        join public.season_players player on player.id = participant.season_player_id
        where participant.match_id = p_match_id
          and (participant.is_eligible or player.is_coach)
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
              and (participant.is_eligible or player.is_coach)
              and participant.convocation_status = 'convoked'
              and workflow.convocation_state = 'published'
              and player.profile_id = subscription.profile_id
          ))
    );

  return jsonb_build_object('payload', v_payload, 'subscriptions', v_subscriptions);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Pushs de match : le coach est destinataire des changements de match,
-- et de l'ouverture du vote Homme du match puisqu'il y vote.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.internal_push_dispatch(p_kind text, p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    m.match_type,
    nullif(btrim(o.name), '') as opponent_name
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

  if p_kind = 'prediction_j5' and v_match.match_type = 'entre_nous' then
    return jsonb_build_object(
      'payload', '{}'::jsonb,
      'subscriptions', '[]'::jsonb
    );
  end if;

  v_date := to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM');
  v_time := private.match_notification_time_label(v_match.kickoff_at);

  if p_kind = 'prediction_j5' then
    v_payload := jsonb_build_object(
      'title', 'Pronostic',
      'body', case
        when v_match.opponent_name is null then format(
          'Pense à pronostiquer pour le match entre nous du %s.',
          v_date
        )
        else format(
          'Pense à pronostiquer pour le match du %s contre %s.',
          v_date,
          v_match.opponent_name
        )
      end,
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
        'body', case
          when v_match.opponent_name is null then format(
            'Le match entre nous du %s à %s est annulé.',
            v_date, v_time
          )
          else format(
            'Le match du %s contre %s à %s est annulé.',
            v_date, v_match.opponent_name, v_time
          )
        end,
        'url', 'matches/' || p_match_id || '/lineup?section=info',
        'tag', 'match-' || p_match_id || '-cancelled'
      )
      when 'match_rescheduled_date' then jsonb_build_object(
        'title', 'Match reporté',
        'body', case
          when private.match_features_open_at(v_match.kickoff_at) <= now()
            then case
              when v_match.opponent_name is null then format(
                'Le match entre nous est reporté au %s à %s. Es-tu disponible ?',
                v_date, v_time
              )
              else format(
                'Le match contre %s est reporté au %s à %s. Es-tu disponible ?',
                v_match.opponent_name, v_date, v_time
              )
            end
          else case
            when v_match.opponent_name is null then format(
              'Le match entre nous est reporté au %s à %s.',
              v_date, v_time
            )
            else format(
              'Le match contre %s est reporté au %s à %s.',
              v_match.opponent_name, v_date, v_time
            )
          end
        end,
        'url', 'matches/' || p_match_id || '/lineup?section=effectif',
        'tag', 'match-' || p_match_id || '-rescheduled-date'
      )
      else jsonb_build_object(
        'title', 'Horaire du match modifié',
        'body', case
          when v_match.opponent_name is null then format(
            'Le match entre nous du %s aura finalement lieu à %s.',
            v_date, v_time
          )
          else format(
            'Le match du %s contre %s aura finalement lieu à %s.',
            v_date, v_match.opponent_name, v_time
          )
        end,
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
          and (participant.is_eligible or player.is_coach)
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
      and private.match_motm_voter_participant(p_match_id, profile.id) is not null;

  else
    raise exception 'Unknown notification kind: %', p_kind using errcode = '22023';
  end if;

  return jsonb_build_object(
    'payload', v_payload,
    'subscriptions', coalesce(v_subscriptions, '[]'::jsonb)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Homme du match : le coach convoqué vote comme les joueurs du match, et
-- n'apparaît jamais parmi les candidats puisqu'il n'entre pas sur le terrain.
-- La règle est isolée ici pour que la lecture, le vote et la notification
-- désignent exactement les mêmes votants.
-- ---------------------------------------------------------------------------

create or replace function private.match_motm_voter_participant(
  p_match_id uuid,
  p_profile_id uuid
)
returns uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select participant.id
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where participant.match_id = p_match_id
    and profile.id = p_profile_id
    and profile.status = 'active'
    and (
      participant.id in (
        select candidate.participant_id
        from private.match_motm_candidate_participants(p_match_id) candidate
      )
      or (player.is_coach and participant.convocation_status = 'convoked')
    )
  order by participant.id
  limit 1;
$function$;

revoke execute on function private.match_motm_voter_participant(uuid, uuid)
  from public, anon, authenticated;

comment on function private.match_motm_voter_participant(uuid, uuid) is
  'Ballot holder for a match: a player from the lineup, or the convoked coach.';

-- ---------------------------------------------------------------------------
-- Lecture du vote : le coach convoqué est un votant.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.get_match_motm_vote(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  v_voter_participant_id := private.match_motm_voter_participant(
    p_match_id, v_actor
  );

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
$function$;

-- ---------------------------------------------------------------------------
-- Dépôt du vote : même règle de votant que la lecture.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.cast_match_motm_vote(p_match_id uuid, p_candidate_participant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  v_voter_participant_id := private.match_motm_voter_participant(
    p_match_id, v_actor
  );

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
$function$;

-- ---------------------------------------------------------------------------
-- Ajout d'un joueur en cours de Live : le coach n'est jamais proposé,
-- puisqu'il n'entre ni sur le terrain ni sur le banc.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.get_match_live_add_player_options(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      'last_initial', candidate.last_initial,
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
      nullif(upper(left(coalesce(
        nullif(btrim(player.last_name), ''),
        nullif(btrim(profile.last_name), ''),
        ''
      ), 1)), '') as last_initial,
      coalesce(profile.photo_url, player.photo_url) as photo_url,
      player.is_goalkeeper
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    left join public.match_sport_participants participant
      on participant.match_id = p_match_id
     and participant.season_player_id = player.id
    where player.season_id = v_season_id
      and player.is_active
      and not player.is_coach
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
      'last_initial', candidate.last_initial,
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
      nullif(upper(left(coalesce(nullif(btrim(guest.last_name), ''), ''), 1)), '') as last_initial,
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

-- ---------------------------------------------------------------------------
-- Garde-fou : le Live refuse un coach même si la demande arrive quand même.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.add_match_live_players(p_match_id uuid, p_players jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

      -- Un coach n'entre jamais sur la feuille de match. Sans ce refus,
      -- l'ajout le basculerait en joueur de rotation et le ferait apparaître
      -- dans les statistiques joueurs.
      if private.participant_is_coach(v_season_player_id) then
        raise exception 'A coach cannot be added to the live lineup'
          using errcode = '22023';
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

-- ---------------------------------------------------------------------------
-- Rattrapage des matchs à venir.
--
-- Les coachs qui avaient déjà répondu restent sur leur réponse : elle suffit
-- désormais à les poser dans l'effectif, sans attendre qu'ils recliquent.
-- Les matchs passés ne sont pas touchés : leur historique reste tel qu'il a
-- été joué et validé.
-- ---------------------------------------------------------------------------

update public.match_sport_participants participant
set convocation_status = case
      when participant.availability_status = 'available'
        then 'convoked'::public.sport_convocation_status
      else 'not_applicable'::public.sport_convocation_status
    end,
    convocation_manual_override = false,
    waitlist_position_snapshot = null,
    waitlist_recommended_not_convoked = false,
    waitlist_turn_should_consume = false,
    waitlist_turn_state = 'not_applicable'::public.sport_waitlist_turn_state,
    updated_at = now()
from public.season_players player
join public.matches match on match.status = 'a_venir'
where player.id = participant.season_player_id
  and player.is_coach
  and match.id = participant.match_id
  and (
    participant.convocation_status is distinct from case
      when participant.availability_status = 'available'
        then 'convoked'::public.sport_convocation_status
      else 'not_applicable'::public.sport_convocation_status
    end
    or participant.convocation_manual_override
    or participant.waitlist_position_snapshot is not null
    or participant.waitlist_turn_state
       is distinct from 'not_applicable'::public.sport_waitlist_turn_state
  );

-- Un coach ne doit jamais rester accroché à la rotation.
delete from public.sport_waitlist_entries entry
using public.season_players player
where player.id = entry.season_player_id
  and player.is_coach;

commit;
