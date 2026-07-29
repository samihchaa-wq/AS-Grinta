-- Tous les joueurs disponibles restent convoqués par défaut, quelle que soit
-- la limite. Seul l'admin peut désormais déplacer manuellement un joueur en
-- liste d'attente (via save_match_effectif, qui gère déjà correctement la
-- rotation de liste d'attente pour ses décisions explicites). L'ancienne
-- exclusion automatique basée sur la limite est supprimée.
create or replace function private.recompute_match_convocations_internal(p_match_id uuid, p_reset_overrides boolean DEFAULT false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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

  -- Non disponibles ou inéligibles : jamais convoqués.
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
      or participant.availability_status <> 'available'
    );

  -- Disponibles et non décidés manuellement : toujours convoqués, sans
  -- exclusion automatique liée à la limite de l'effectif.
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
    count(*) filter (where participant.convocation_status = 'convoked')::integer,
    count(*) filter (where participant.convocation_status = 'not_convoked')::integer
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

-- Corrige immédiatement les matchs à venir déjà affectés par l'ancienne
-- exclusion automatique (joueurs disponibles, non décidés manuellement,
-- actuellement en liste d'attente uniquement à cause de la limite).
update public.match_sport_participants participant
set convocation_status = 'convoked',
    waitlist_recommended_not_convoked = false,
    waitlist_turn_should_consume = false,
    waitlist_turn_state = case
      when participant.waitlist_turn_state in ('consumed', 'waived')
        then participant.waitlist_turn_state
      else 'not_applicable'::public.sport_waitlist_turn_state
    end,
    updated_at = now()
from public.matches match
where participant.match_id = match.id
  and match.status = 'a_venir'
  and participant.is_eligible
  and participant.availability_status = 'available'
  and participant.convocation_status = 'not_convoked'
  and not participant.convocation_manual_override;
