create or replace function private.reset_match_motm_election(
  p_match_id uuid,
  p_finalization_version integer,
  p_opens_at timestamptz,
  p_actor uuid,
  p_reason text default null,
  p_action text default 'open_motm_vote'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_has_ballot boolean;
  v_state public.sport_vote_state;
  v_kickoff_at timestamptz;
  v_closes_at timestamptz;
begin
  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  select coalesce(match.kickoff_at, p_opens_at)
  into v_kickoff_at
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_closes_at := case
    when v_has_ballot then v_kickoff_at + interval '24 hours'
    else null
  end;
  v_state := case
    when not v_has_ballot then 'cancelled'::public.sport_vote_state
    when p_opens_at < v_closes_at then 'open'::public.sport_vote_state
    else 'closed'::public.sport_vote_state
  end;

  insert into public.match_sport_motm_elections as election (
    match_id,
    finalization_version,
    state,
    opens_at,
    closes_at,
    closed_at,
    total_votes,
    max_votes,
    created_at,
    updated_at
  ) values (
    p_match_id,
    p_finalization_version,
    v_state,
    case when v_has_ballot then p_opens_at else null end,
    v_closes_at,
    case when v_state = 'closed' then now() else null end,
    0,
    0,
    now(),
    now()
  )
  on conflict (match_id) do update
  set finalization_version = excluded.finalization_version,
      state = excluded.state,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      closed_at = excluded.closed_at,
      total_votes = 0,
      max_votes = 0,
      updated_at = now();

  update public.match_sport_workflows
  set vote_state = v_state,
      updated_by = coalesce(p_actor, updated_by),
      updated_at = now()
  where match_id = p_match_id;

  if p_actor is not null then
    insert into private.sport_admin_audit_log(
      match_id,
      action,
      actor_profile_id,
      reason,
      metadata
    ) values (
      p_match_id,
      p_action,
      p_actor,
      nullif(btrim(p_reason), ''),
      jsonb_build_object(
        'finalization_version', p_finalization_version,
        'state', v_state,
        'opens_at', case when v_has_ballot then p_opens_at else null end,
        'closes_at', v_closes_at,
        'closes_from', 'kickoff_at'
      )
    );
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'state', v_state,
    'opens_at', case when v_has_ballot then p_opens_at else null end,
    'closes_at', v_closes_at,
    'finalization_version', p_finalization_version
  );
end;
$$;

update public.match_sport_motm_elections election
set closes_at = coalesce(match.kickoff_at, election.opens_at) + interval '24 hours',
    updated_at = now()
from public.matches match
where match.id = election.match_id
  and election.state = 'open';

do $$
declare
  election record;
begin
  for election in
    select match_id
    from public.match_sport_motm_elections
    where state = 'open'
      and closes_at <= now()
  loop
    perform private.close_match_motm_election(election.match_id, false);
  end loop;
end;
$$;

comment on function private.reset_match_motm_election(
  uuid,
  integer,
  timestamptz,
  uuid,
  text,
  text
) is 'Opens MOTM voting after finalization and always closes it 24 hours after match kickoff.';
