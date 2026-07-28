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
          when input.zone = 'not_selected'
            then 'not_convoked'
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

  return private.save_match_composition(
    p_match_id,
    p_formation_code,
    p_entries,
    false,
    coalesce(v_reason, 'Brouillon du plan de sélection unifié')
  );
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
