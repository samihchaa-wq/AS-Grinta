begin;

-- Un convoqué qui s'était désisté puis revient récupère sa place, et seul
-- le joueur noté comme son remplaçant retourne en liste d'attente. Quand sa
-- place avait été reprise par une correction manuelle de l'effectif,
-- personne n'est noté comme remplaçant : personne ne redescendait et
-- l'effectif dépassait le nombre de places (cas de Poulain pour le match du
-- 9 novembre : 15 convoqués pour 14 places s'il s'était remis présent).
--
-- Désormais, dans ce cas, si son retour dépasse le nombre de places, le
-- convoqué le plus haut dans la liste d'attente repasse en attente, comme
-- le ferait le recalcul de l'effectif, et il en est prévenu. Un convoqué
-- placé à la main par un admin n'est choisi qu'en dernier recours. Rien ne
-- change quand un remplaçant est noté, ni pour un match entre nous.

create or replace function private.restore_returning_convoked_player(
  p_match_id uuid,
  p_participant_id uuid,
  p_actor uuid,
  p_actor_kind text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_current_status public.sport_convocation_status;
  v_manual_override boolean;
  v_was_convoked boolean := false;
  v_promoted_id uuid;
  v_promoted_season_player_id uuid;
  v_limit integer;
  v_match_type text;
  v_other_convoked integer;
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

  -- Jamais convoqué pour ce match : il prend son rang dans la liste
  -- d'attente, comme un joueur qui répond pour la première fois.
  if not v_was_convoked then
    update public.match_sport_participants
    set convocation_manual_override = false,
        updated_at = now()
    where id = p_participant_id
      and convocation_manual_override;

    perform private.recompute_match_convocations_internal(p_match_id, false);
    return null;
  end if;

  -- Personne n'est noté comme remplaçant : sa place a été reprise par une
  -- correction manuelle de l'effectif. Si son retour dépasse le nombre de
  -- places, le convoqué le plus haut dans la liste d'attente repasse en
  -- attente, comme le ferait le recalcul de l'effectif. Un convoqué placé à
  -- la main par un admin n'est choisi qu'en dernier recours.
  if v_promoted_id is null then
    select workflow.squad_size_limit, match.match_type
    into v_limit, v_match_type
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    where workflow.match_id = p_match_id;

    if v_match_type is distinct from 'entre_nous' then
      select count(*)::integer
      into v_other_convoked
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.id <> p_participant_id
        and participant.is_eligible
        and participant.availability_status = 'available'
        and participant.convocation_status = 'convoked';

      if v_other_convoked >= v_limit then
        select candidate.id, candidate.season_player_id
        into v_promoted_id, v_promoted_season_player_id
        from public.match_sport_participants candidate
        join public.sport_waitlist_entries waitlist
          on waitlist.season_player_id = candidate.season_player_id
        where candidate.match_id = p_match_id
          and candidate.id <> p_participant_id
          and candidate.is_eligible
          and candidate.availability_status = 'available'
          and candidate.convocation_status = 'convoked'
        order by candidate.convocation_manual_override,
          waitlist.position,
          candidate.id
        limit 1
        for update of candidate;
      end if;
    end if;
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
$function$;

revoke all on function private.restore_returning_convoked_player(
  uuid, uuid, uuid, text
) from public, anon, authenticated;

comment on function private.restore_returning_convoked_player(
  uuid, uuid, uuid, text
) is
  'Places a player who answers available again after publication: a returning convoked player gets his place back, any other player takes his rank in the waitlist order. When nobody is recorded as his replacement and the squad overflows, the convoked player highest in the waitlist goes back to it.';

commit;
