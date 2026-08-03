create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_exists boolean;
  v_kickoff timestamptz;
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

  select match.kickoff_at into v_kickoff
  from public.matches match
  where match.id = p_match_id
    and match.status <> 'annule';
  if v_kickoff is null then
    return;
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  if not v_has_ballot then
    return;
  end if;

  v_opens_at := private.match_motm_opens_at(p_match_id);
  v_closes_at := v_kickoff + interval '24 hours';
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
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = 'draft',
      updated_at = now()
  where match_id = p_match_id;
end;
$function$;

create or replace function private.close_due_match_motm_elections()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_processed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select match.id as match_id
    from public.matches match
    where match.status <> 'annule'
      and match.kickoff_at + interval '2 hours' <= now()
      and match.kickoff_at > now() - interval '30 days'
      and not exists (
        select 1
        from public.match_sport_motm_elections election
        where election.match_id = match.id
      )
    order by match.kickoff_at, match.id
  loop
    perform private.ensure_match_motm_election(v_row.match_id);
  end loop;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state in ('draft', 'open')
    order by election.closes_at nulls last, election.match_id
    for update skip locked
  loop
    perform private.transition_match_motm_election(v_row.match_id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;
