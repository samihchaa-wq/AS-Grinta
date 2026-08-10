-- Publishing the live recap now also freezes and versions the composition
-- actually played, based on the final live workspace and corrected presence.

create or replace function private.publish_match_live_recap(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
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

  -- Finalization remains the single authority for score, attendance, goals,
  -- statistics, badges, prediction points and MOTM workflow.
  v_finalize_result := private.finalize_match_sport_postgame(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse,
    p_participants,
    p_reason
  );

  -- The live workspace already represents the last real on-field state.
  -- Reconcile it with corrected final presence, then publish that state as the
  -- post-match composition in the same transaction.
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

    -- Defensive fallback for a finalized participant that was not present in
    -- the original composition snapshot.
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
