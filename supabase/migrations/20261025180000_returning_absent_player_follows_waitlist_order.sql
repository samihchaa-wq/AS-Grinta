begin;

-- Un joueur qui s'était dit absent puis se dit présent, alors que l'effectif
-- est déjà publié, tombait directement en liste d'attente, quel que soit son
-- rang. Personne n'était déplacé, même un convoqué placé avant lui dans la
-- liste d'attente, donc censé y passer avant lui.
--
-- Un joueur qui n'avait pas encore répondu, lui, est placé selon son rang.
-- Le joueur revenu restait en outre « automatique » : la réponse suivante
-- de n'importe quel joueur, ou un enregistrement de l'effectif, le remettait
-- à son rang. Sa place dépendait donc de ce qui arrivait ensuite.
--
-- Désormais, un joueur qui revient sans avoir jamais eu de place pour ce
-- match est placé selon l'ordre de la liste d'attente, comme un joueur qui
-- répond pour la première fois. Si son rang lui donne une place, c'est le
-- convoqué le plus haut dans la liste qui passe en attente, et il en est
-- prévenu.
--
-- Rien ne change pour les deux autres cas :
-- - une décision figée par un admin reste figée ;
-- - un convoqué qui s'était désisté puis revient récupère sa place, et le
--   joueur monté à sa place retourne en liste d'attente.

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
  'Places a player who answers available again after publication: a returning convoked player gets his place back, any other player takes his rank in the waitlist order.';

commit;
