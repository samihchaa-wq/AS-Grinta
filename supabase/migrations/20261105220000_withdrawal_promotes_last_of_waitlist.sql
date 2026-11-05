begin;

-- Quand un convoqué se désiste après la publication de l'effectif, le
-- remplaçant choisi était le PREMIER de la liste d'attente (n°1). Or la
-- règle de l'effectif est l'inverse : les derniers de la liste gardent leur
-- place en priorité, le n°1 est le premier à rester en attente.
--
-- Cas réel (09/11, Toulouse Métropole) : Julien César (n°1) et Alyoun
-- Cherfi (n°4) étaient en attente. Au désistement d'Olivier Millet, c'est
-- Julien César qui a été convoqué, alors que le recalcul de l'effectif
-- aurait convoqué Alyoun Cherfi. Un admin a dû corriger à la main.
--
-- Désormais, le remplaçant est le joueur en attente le plus bas dans la
-- liste, exactement celui que le recalcul automatique aurait convoqué.
-- Le reste de la fonction est inchangé.

create or replace function private.handle_convoked_withdrawal(
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

  -- Même ordre que private.recompute_match_convocations_internal : la place
  -- libérée revient au joueur en attente le plus bas dans la liste.
  select candidate.id, candidate.season_player_id
  into v_candidate_id, v_candidate_season_player_id
  from public.match_sport_participants candidate
  join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = candidate.season_player_id
  where candidate.match_id = p_match_id
    and candidate.is_eligible
    and candidate.availability_status = 'available'
    and candidate.convocation_status = 'not_convoked'
  order by waitlist.position desc, candidate.id
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
$function$;

revoke all on function private.handle_convoked_withdrawal(
  uuid, uuid, uuid, text
) from public, anon, authenticated;

commit;
