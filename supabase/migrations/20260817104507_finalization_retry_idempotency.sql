begin;

do $do$
declare
  v_def text;
  v_new text;
  v_marker text := $marker$  select coalesce(array_agg(participant.season_player_id), '{}'::uuid[])$marker$;
  v_guard text := $guard$  -- AS_GRINTA_FINALIZATION_RETRY_IDEMPOTENCY_V1
  -- Un paquet rejoué après perte de l'accusé réseau ne doit pas fabriquer une
  -- correction : même score, même composition, mêmes participants et même motif
  -- => on renvoie l'état courant sans aucune écriture supplémentaire.
  if v_existing_version > 0
     and exists (
       select 1
       from public.match_sport_finalizations finalization
       where finalization.match_id = p_match_id
         and finalization.version = v_existing_version
         and finalization.score_as_grinta = p_score_as_grinta
         and finalization.score_adverse = p_score_adverse
         and finalization.composition_version = v_composition_version
     )
     and not exists (
       select 1
       from pg_temp.sport_final_input input
       join public.match_sport_participants participant
         on participant.id = input.participant_id
       where participant.match_id = p_match_id
         and (
           participant.final_presence_status is distinct from case
             when input.present then 'present'::public.sport_final_presence_status
             else 'actual_absent'::public.sport_final_presence_status
           end
           or participant.final_selection_status is distinct from input.final_selection_status
           or participant.final_goals is distinct from input.goals
           or participant.final_clean_sheet is distinct from input.clean_sheet
         )
     )
     and (
       select audit.reason
       from private.sport_admin_audit_log audit
       where audit.match_id = p_match_id
         and audit.action in ('validate_final_attendance', 'correct_final_attendance')
       order by audit.id desc
       limit 1
     ) is not distinct from v_reason
  then
    return private.match_sport_finalization_snapshot(p_match_id)
      || jsonb_build_object('validation_kind', 'unchanged');
  end if;
$guard$;
begin
  select pg_get_functiondef(
    'private.finalize_match_sport_postgame(uuid,integer,integer,jsonb,text)'::regprocedure
  ) into v_def;

  if position('AS_GRINTA_FINALIZATION_RETRY_IDEMPOTENCY_V1' in v_def) = 0 then
    if position(v_marker in v_def) = 0 then
      raise exception 'Unable to locate finalization idempotency insertion point';
    end if;

    v_new := replace(v_def, v_marker, v_guard || E'\n\n' || v_marker);
    if v_new = v_def then
      raise exception 'Unable to patch finalization retry idempotency';
    end if;

    execute v_new;
  end if;
end;
$do$;

comment on function private.finalize_match_sport_postgame(uuid,integer,integer,jsonb,text) is
  'Finalise/corrige un match sport. Un retry strictement identique à la dernière finalisation est un no-op idempotent.';

commit;
