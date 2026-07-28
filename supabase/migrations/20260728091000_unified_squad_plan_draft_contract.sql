-- Keep the legacy unified squad-plan RPCs aligned with the explicit
-- draft -> convocation publication -> composition publication contract.

create or replace function private.save_match_squad_plan(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reason text := nullif(btrim(p_reason), '');
  v_squad_size_limit integer;
  v_decisions jsonb;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select workflow.squad_size_limit
  into v_squad_size_limit
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'season_player_id', participant.season_player_id,
        'status', case
          when input.zone = 'not_selected' then 'not_convoked'
          else 'convoked'
        end
      ) order by participant.season_player_id
    ),
    '[]'::jsonb
  )
  into v_decisions
  from jsonb_array_elements(p_entries) item
  cross join lateral (
    select
      (item ->> 'participant_id')::uuid as participant_id,
      (item ->> 'zone')::public.sport_composition_zone as zone
  ) input
  join public.match_sport_participants participant
    on participant.id = input.participant_id
   and participant.match_id = p_match_id
   and participant.is_eligible
   and participant.season_player_id is not null
   and participant.availability_status = 'available';

  perform private.save_match_effectif(
    p_match_id,
    v_squad_size_limit,
    v_decisions,
    coalesce(v_reason, 'Brouillon du plan de sélection unifié')
  );

  -- save_match_composition validates the participant convocation columns.
  -- Apply the private draft only inside this transaction, save the composition,
  -- then restore the player-visible publication before returning.
  create temporary table if not exists pg_temp.unified_convocation_snapshot (
    participant_id uuid primary key,
    convocation_status public.sport_convocation_status not null,
    convocation_manual_override boolean not null,
    waitlist_recommended_not_convoked boolean not null,
    waitlist_turn_should_consume boolean not null,
    waitlist_turn_state public.sport_waitlist_turn_state not null,
    waitlist_turn_updated_at timestamptz,
    updated_at timestamptz not null
  ) on commit drop;
  truncate table pg_temp.unified_convocation_snapshot;

  insert into pg_temp.unified_convocation_snapshot(
    participant_id,
    convocation_status,
    convocation_manual_override,
    waitlist_recommended_not_convoked,
    waitlist_turn_should_consume,
    waitlist_turn_state,
    waitlist_turn_updated_at,
    updated_at
  )
  select
    participant.id,
    participant.convocation_status,
    participant.convocation_manual_override,
    participant.waitlist_recommended_not_convoked,
    participant.waitlist_turn_should_consume,
    participant.waitlist_turn_state,
    participant.waitlist_turn_updated_at,
    participant.updated_at
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
  for update;

  update public.match_sport_participants participant
  set convocation_status = draft.status,
      convocation_manual_override = true,
      waitlist_recommended_not_convoked = false,
      waitlist_turn_should_consume = draft.status = 'not_convoked',
      waitlist_turn_state = case
        when participant.waitlist_turn_state = 'consumed'
          then 'consumed'::public.sport_waitlist_turn_state
        when draft.status = 'not_convoked'
          then 'pending'::public.sport_waitlist_turn_state
        else 'waived'::public.sport_waitlist_turn_state
      end,
      waitlist_turn_updated_at = now(),
      updated_at = now()
  from private.match_effectif_draft_entries draft
  where draft.match_id = p_match_id
    and participant.match_id = p_match_id
    and participant.season_player_id = draft.season_player_id
    and participant.is_eligible
    and participant.availability_status = 'available';

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
    and participant.availability_status <> 'available';

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

  v_result := private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    false,
    coalesce(v_reason, 'Brouillon du plan de sélection unifié')
  );

  update public.match_sport_participants participant
  set convocation_status = snapshot.convocation_status,
      convocation_manual_override = snapshot.convocation_manual_override,
      waitlist_recommended_not_convoked = snapshot.waitlist_recommended_not_convoked,
      waitlist_turn_should_consume = snapshot.waitlist_turn_should_consume,
      waitlist_turn_state = snapshot.waitlist_turn_state,
      waitlist_turn_updated_at = snapshot.waitlist_turn_updated_at,
      updated_at = snapshot.updated_at
  from pg_temp.unified_convocation_snapshot snapshot
  where participant.id = snapshot.participant_id;

  return v_result;
end;
$function$;

create or replace function private.publish_match_squad_plan(
  p_match_id uuid,
  p_formation_code text,
  p_entries jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reason text := nullif(btrim(p_reason), '');
  v_squad_size_limit integer;
  v_decisions jsonb;
begin
  perform private.save_match_squad_plan(
    p_match_id,
    p_formation_code,
    p_entries,
    coalesce(v_reason, 'Préparation du plan de sélection unifié')
  );

  select
    draft.squad_size_limit,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'season_player_id', entry.season_player_id,
          'status', entry.status
        ) order by entry.season_player_id
      ) filter (where entry.season_player_id is not null),
      '[]'::jsonb
    )
  into v_squad_size_limit, v_decisions
  from private.match_effectif_drafts draft
  left join private.match_effectif_draft_entries entry
    on entry.match_id = draft.match_id
  where draft.match_id = p_match_id
  group by draft.match_id, draft.squad_size_limit;

  if not found then
    raise exception 'Effectif draft not found' using errcode = 'P0002';
  end if;

  perform private.publish_match_effectif(
    p_match_id,
    v_squad_size_limit,
    v_decisions,
    coalesce(v_reason, 'Publication du plan de sélection unifié')
  );

  return private.publish_match_composition(
    p_match_id,
    false,
    coalesce(v_reason, 'Publication du plan de sélection unifié')
  );
end;
$function$;

comment on function public.admin_save_match_squad_plan(uuid, text, jsonb, text) is
  'Stores effectif and composition drafts atomically without changing player-visible publications.';
comment on function public.admin_publish_match_squad_plan(uuid, text, jsonb, text) is
  'Explicitly publishes the effectif draft and then the composition in one transaction.';
