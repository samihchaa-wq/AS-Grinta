begin;

create or replace function private.match_postgame_correction_closes_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (
      select finalization.validated_at + interval '24 hours'
      from public.match_sport_finalizations finalization
      where finalization.match_id = p_match_id
    ),
    (
      select match.result_validated_at + interval '24 hours'
      from public.matches match
      where match.id = p_match_id
    )
  );
$function$;

comment on function private.match_postgame_correction_closes_at(uuid) is
  'Echéance immuable : première validation du compte rendu + exactement 24 heures.';

create or replace function private.admin_cancel_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_version integer;
  v_state public.sport_vote_state;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  select election.finalization_version, election.state
  into v_version, v_state
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;
  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;

  if v_state in ('draft', 'open') then
    raise exception 'Le vote HDM se ferme automatiquement exactement 24 h après la validation du compte rendu.'
      using errcode = '22023';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;
  update public.match_sport_motm_elections
  set state = 'cancelled', closes_at = null, closed_at = null,
      total_votes = 0, max_votes = 0, updated_at = now()
  where match_id = p_match_id;
  update public.match_sport_workflows
  set vote_state = 'cancelled', updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'cancel_motm_vote', v_actor, v_reason,
    jsonb_build_object('finalization_version', v_version)
  );

  return jsonb_build_object('match_id', p_match_id, 'state', 'cancelled');
end;
$function$;

commit;