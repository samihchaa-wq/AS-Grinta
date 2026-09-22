-- Automatic HDM voting stays anchored to the final validation for opening,
-- but its deadline is the scheduled kickoff plus exactly 24 hours.
-- This prevents a late post-match validation from extending the ballot.

create or replace function private.match_motm_closes_at(p_match_id uuid)
returns timestamptz
language sql
stable
set search_path = ''
as $function$
  select match.kickoff_at + interval '24 hours'
  from public.matches match
  where match.id = p_match_id;
$function$;

revoke all on function private.match_motm_closes_at(uuid)
  from public, anon, authenticated;

create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_exists boolean;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select private.match_motm_opens_at(p_match_id) into v_opens_at;
  select private.match_motm_closes_at(p_match_id) into v_closes_at;
  if v_opens_at is null
     or v_closes_at is null
     or v_closes_at <= v_opens_at then
    return;
  end if;

  if exists (
    select 1
    from public.matches match
    where match.id = p_match_id
      and match.status = 'annule'
  ) then
    return;
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  if not v_has_ballot then
    return;
  end if;

  v_version := private.match_motm_anchor_version(p_match_id);

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    'draft'::public.sport_vote_state,
    v_opens_at,
    v_closes_at,
    null,
    0,
    0,
    now(),
    now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = 'draft',
      updated_at = now()
  where match_id = p_match_id;
end;
$function$;

create or replace function private.trg_reset_match_motm_after_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_vote_state public.sport_vote_state;
begin
  perform private.ensure_match_motm_election(new.match_id);

  v_opens_at := private.match_motm_opens_at(new.match_id);
  v_closes_at := private.match_motm_closes_at(new.match_id);
  if v_opens_at is null or v_closes_at is null then
    return new;
  end if;

  if v_closes_at <= v_opens_at then
    update public.match_sport_motm_elections election
    set state = 'unavailable',
        opens_at = null,
        closes_at = null,
        closed_at = null,
        updated_at = now()
    where election.match_id = new.match_id
      and election.state in ('draft', 'open');

    update public.match_sport_workflows workflow
    set vote_state = 'unavailable',
        updated_at = now()
    where workflow.match_id = new.match_id
      and workflow.vote_state in ('draft', 'open');

    return new;
  end if;

  update public.match_sport_motm_elections election
  set opens_at = v_opens_at,
      closes_at = v_closes_at,
      updated_at = now()
  where election.match_id = new.match_id
    and election.state in ('draft', 'open');

  perform private.transition_match_motm_election(new.match_id);

  select election.state
  into v_vote_state
  from public.match_sport_motm_elections election
  where election.match_id = new.match_id;

  if v_vote_state is not null then
    update public.match_sport_workflows workflow
    set vote_state = v_vote_state,
        updated_at = now()
    where workflow.match_id = new.match_id
      and workflow.vote_state is distinct from v_vote_state;
  end if;

  if v_vote_state = 'closed' then
    delete from public.match_man_of_match
    where match_id = new.match_id;

    insert into public.match_man_of_match(match_id, season_player_id)
    select result.match_id, participant.season_player_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    where result.match_id = new.match_id
      and result.is_winner
      and participant.season_player_id is not null
    on conflict do nothing;
  end if;

  return new;
end;
$function$;

create or replace function private.admin_restart_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
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

  select private.match_motm_closes_at(p_match_id) into v_closes_at;

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

-- Repair every active automatic ballot to the canonical deadline. Existing
-- closed/cancelled results are deliberately left untouched.
update public.match_sport_motm_elections election
set closes_at = private.match_motm_closes_at(election.match_id),
    updated_at = now()
from public.matches match
where match.id = election.match_id
  and election.state in ('draft', 'open')
  and private.match_motm_closes_at(election.match_id) is not null
  and private.match_motm_closes_at(election.match_id) > election.opens_at
  and election.closes_at is distinct from private.match_motm_closes_at(election.match_id);

-- If a corrected deadline is already due, close it immediately through the
-- normal transition path so results/workflow state stay consistent.
select private.close_due_match_motm_elections(now());
