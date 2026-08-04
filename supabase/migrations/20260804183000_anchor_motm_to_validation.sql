begin;

-- The product lifecycle now anchors MOTM exclusively to the initial validated
-- post-match recap. Older implementations could pre-create/open an election at
-- kickoff + 1h45 and close it at kickoff + 24h. Preserve any ballots already
-- stored, but stop an unvalidated election from remaining voteable.
update public.match_sport_motm_elections election
set state = 'draft'::public.sport_vote_state,
    opens_at = null,
    closes_at = null,
    closed_at = null,
    updated_at = now()
where election.state in ('draft', 'open')
  and not exists (
    select 1
    from public.match_sport_finalizations finalization
    where finalization.match_id = election.match_id
  );

update public.match_sport_workflows workflow
set vote_state = 'draft'::public.sport_vote_state,
    updated_at = now()
where exists (
    select 1
    from public.match_sport_motm_elections election
    where election.match_id = workflow.match_id
      and election.state = 'draft'
      and election.opens_at is null
      and election.closes_at is null
  );

-- Existing non-final elections that already have a validated recap use the
-- validation timestamp as the sole start time and receive a full 24h window.
update public.match_sport_motm_elections election
set opens_at = finalization.validated_at,
    closes_at = finalization.validated_at + interval '24 hours',
    updated_at = now()
from public.match_sport_finalizations finalization
where finalization.match_id = election.match_id
  and election.state in ('draft', 'open');

-- Finalization must overwrite the historical kickoff-based schedule rather
-- than keeping the earliest opening time. Keep the latest synchronization
-- behavior for workflow state and permanent MOTM results.
create or replace function private.trg_reset_match_motm_after_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_opens_at timestamptz;
  v_vote_state public.sport_vote_state;
begin
  perform private.ensure_match_motm_election(new.match_id);

  v_opens_at := private.match_motm_opens_at(new.match_id);
  if v_opens_at is null then
    return new;
  end if;

  update public.match_sport_motm_elections election
  set opens_at = v_opens_at,
      closes_at = v_opens_at + interval '24 hours',
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

-- Bring already-finalized active elections to the correct state immediately.
do $do$
declare
  v_row record;
begin
  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    join public.match_sport_finalizations finalization
      on finalization.match_id = election.match_id
    where election.state in ('draft', 'open')
    order by election.match_id
  loop
    perform private.transition_match_motm_election(v_row.match_id);
  end loop;
end
$do$;

commit;
