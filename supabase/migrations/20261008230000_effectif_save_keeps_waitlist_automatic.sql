begin;

-- Enregistrer l'effectif figeait jusqu'ici la décision de chaque joueur
-- disponible, même ceux que l'admin n'avait pas touchés. Ces joueurs sortaient
-- de la liste d'attente automatique : un joueur qui répondait ensuite devait
-- se partager les seules places restantes, quel que soit son rang.
--
-- Désormais, seule une décision réellement prise par l'admin est figée :
-- - l'application nouvelle envoie « changed » pour chaque joueur ;
-- - un ancien client qui ne l'envoie pas voit figer uniquement les joueurs
--   dont le statut diffère de celui que le serveur avait calculé.
-- Une décision déjà figée le reste. Tous les autres joueurs disponibles sont
-- recalculés selon l'ordre de la liste d'attente.

create or replace function private.publish_match_effectif(
  p_match_id uuid,
  p_squad_size_limit integer,
  p_decisions jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
    status public.sport_convocation_status not null,
    changed boolean
  ) on commit drop;
  truncate table pg_temp.effectif_input;

  begin
    insert into pg_temp.effectif_input(season_player_id, status, changed)
    select
      (item ->> 'season_player_id')::uuid,
      (item ->> 'status')::public.sport_convocation_status,
      case jsonb_typeof(item -> 'changed')
        when 'boolean' then (item ->> 'changed')::boolean
        else null
      end
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

  -- Seules les décisions de l'admin sont figées. Les autres restent
  -- automatiques : le recalcul qui suit les place selon la liste d'attente.
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
    and participant.is_eligible
    and (
      participant.convocation_manual_override
      or coalesce(
        input.changed,
        participant.convocation_status is distinct from input.status
      )
    );

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
$function$;

commit;
