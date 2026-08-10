-- Participants d'un match sportif : inclure TOUT l'effectif actif.
--
-- sync_match_sport_workflow ne créait des participants que pour les joueurs
-- ayant un compte actif (`join public.profiles ... status = 'active'`). Les
-- joueurs de l'effectif sans compte n'étaient donc jamais participants d'un
-- match : impossible de les convoquer, de les placer en composition ou de les
-- marquer présents — alors qu'ils font partie de l'effectif (et de la liste
-- d'attente). On aligne la synchronisation sur l'effectif complet : tout
-- season_player actif de la saison devient participant, avec ou sans compte.

create or replace function private.sync_match_sport_workflow(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_kickoff_at timestamptz;
  v_match_status text;
  v_config jsonb;
  v_open_hours integer := 144;
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

  if coalesce(v_config ->> 'availability_open_hours_before', '') ~ '^[0-9]+$' then
    v_open_hours := greatest(1, least(720, (v_config ->> 'availability_open_hours_before')::integer));
  end if;
  if coalesce(v_config ->> 'usual_squad_size', '') ~ '^[0-9]+$' then
    v_default_squad_size := greatest(1, least(30, (v_config ->> 'usual_squad_size')::integer));
  end if;

  v_opens_at := v_kickoff_at - make_interval(hours => v_open_hours);
  v_computed_state := case
    when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
    when now() >= v_opens_at then 'open'::public.sport_availability_state
    else 'pending'::public.sport_availability_state
  end;

  insert into public.match_sport_workflows as workflow (
    match_id, availability_state, availability_opens_at, availability_opened_at,
    squad_size_limit, created_by, updated_by
  ) values (
    p_match_id, v_computed_state, v_opens_at,
    case when v_computed_state = 'open' then now() else null end,
    v_default_squad_size, v_actor, v_actor
  )
  on conflict (match_id) do update
  set availability_opens_at = excluded.availability_opens_at,
      availability_state = case
        when now() >= v_kickoff_at then 'closed'::public.sport_availability_state
        when workflow.availability_state = 'open' then 'open'::public.sport_availability_state
        when now() >= v_opens_at then 'open'::public.sport_availability_state
        else 'pending'::public.sport_availability_state
      end,
      availability_opened_at = case
        when workflow.availability_opened_at is not null then workflow.availability_opened_at
        when now() >= v_opens_at and now() < v_kickoff_at then now()
        else null
      end,
      updated_by = v_actor,
      updated_at = now()
  returning availability_state, availability_opened_at
  into v_saved_state, v_opened_at;

  -- Synchronisation de tout l'effectif permanent actif (compte ou non). Les
  -- invités restent liés au match indépendamment.
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
    );

  insert into public.match_sport_participants as participant (
    match_id, season_player_id, is_eligible
  )
  select p_match_id, player.id, true
  from public.season_players player
  where player.season_id = v_season_id
    and player.is_active
  on conflict (match_id, season_player_id) do update
  set is_eligible = true,
      updated_at = case
        when participant.is_eligible then participant.updated_at
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
$function$;
