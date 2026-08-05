begin;

create or replace function private.match_postgame_correction_closes_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  with anchor as (
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
    ) as closes_at
  ), election as (
    select e.state::text as state, e.closes_at, e.closed_at
    from public.match_sport_motm_elections e
    where e.match_id = p_match_id
  )
  select case
    when anchor.closes_at is null then null
    when election.state = 'closed' and election.closed_at is not null then
      least(
        anchor.closes_at,
        election.closed_at,
        coalesce(election.closes_at, anchor.closes_at)
      )
    when election.closes_at is not null then
      least(anchor.closes_at, election.closes_at)
    else anchor.closes_at
  end
  from anchor
  left join election on true;
$function$;

comment on function private.match_postgame_correction_closes_at(uuid) is
  'Deadline immuable des corrections post-match : au plus validation initiale + 24 h, et exactement la clôture HDM lorsqu elle survient plus tôt.';

create or replace function private.admin_restart_match_motm_vote(
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
  v_has_ballot boolean;
  v_version integer;
  v_state public.sport_vote_state;
  v_closes_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.matches match where match.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

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
  ) into v_closes_at;

  if v_closes_at is null or now() >= v_closes_at then
    raise exception 'MOTM vote cannot be restarted after the post-match window closes'
      using errcode = '22023';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_version := private.match_motm_anchor_version(p_match_id);
  v_state := (case when v_has_ballot then 'open' else 'cancelled' end)::public.sport_vote_state;

  insert into public.match_sport_motm_elections as election (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then now() else null end,
    case when v_has_ballot then v_closes_at else null end,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do update
  set finalization_version = excluded.finalization_version,
      state = excluded.state,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      closed_at = null,
      total_votes = 0,
      max_votes = 0,
      updated_at = now();

  update public.match_sport_workflows
  set vote_state = v_state, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_motm_vote', v_actor, v_reason,
    jsonb_build_object(
      'anchor_version', v_version,
      'state', v_state,
      'closes_at', v_closes_at
    )
  );

  return jsonb_build_object(
    'match_id', p_match_id,
    'state', v_state,
    'closes_at', case when v_has_ballot then v_closes_at else null end
  );
end;
$function$;

revoke all on function private.match_postgame_correction_closes_at(uuid)
  from public, anon, authenticated;

commit;