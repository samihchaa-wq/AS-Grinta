-- Collective Man of the Match vote for the optional sports-management module.
-- The ballot is tied to the validated final-attendance version. A correction
-- invalidates every previous ballot/result and opens a fresh 24-hour window.

create table public.match_sport_motm_elections (
  match_id uuid primary key references public.match_sport_workflows(match_id) on delete restrict,
  finalization_version integer not null check (finalization_version >= 1),
  state public.sport_vote_state not null default 'draft',
  opens_at timestamptz,
  closes_at timestamptz,
  closed_at timestamptz,
  total_votes integer not null default 0 check (total_votes >= 0),
  max_votes integer not null default 0 check (max_votes >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (state = 'open' and opens_at is not null and closes_at is not null and closed_at is null)
    or (state = 'closed' and opens_at is not null and closes_at is not null and closed_at is not null)
    or (state in ('draft', 'cancelled', 'unavailable'))
  ),
  check (closes_at is null or opens_at is null or closes_at > opens_at)
);

create table public.match_sport_motm_votes (
  match_id uuid not null references public.match_sport_motm_elections(match_id) on delete restrict,
  voter_profile_id uuid not null references public.profiles(id) on delete restrict,
  candidate_participant_id uuid not null,
  finalization_version integer not null check (finalization_version >= 1),
  cast_at timestamptz not null default now(),
  primary key (match_id, voter_profile_id),
  foreign key (candidate_participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict
);

create table public.match_sport_motm_results (
  match_id uuid not null references public.match_sport_motm_elections(match_id) on delete restrict,
  participant_id uuid not null,
  finalization_version integer not null check (finalization_version >= 1),
  votes_count integer not null default 0 check (votes_count >= 0),
  is_winner boolean not null default false,
  computed_at timestamptz not null default now(),
  primary key (match_id, participant_id),
  foreign key (participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict
);

comment on table public.match_sport_motm_elections is
  'Twenty-four-hour collective MOTM ballot tied to one validated final-attendance version.';
comment on table public.match_sport_motm_votes is
  'Secret and immutable ballot: one permanent present player, one candidate, one vote.';
comment on table public.match_sport_motm_results is
  'Closed-ballot totals. Ties deliberately produce several winners.';

create index match_sport_motm_elections_due_idx
  on public.match_sport_motm_elections(state, closes_at)
  where state = 'open';
create index match_sport_motm_votes_candidate_idx
  on public.match_sport_motm_votes(match_id, candidate_participant_id);
create index match_sport_motm_results_winner_idx
  on public.match_sport_motm_results(match_id, is_winner)
  where is_winner;

alter table public.match_sport_motm_elections enable row level security;
alter table public.match_sport_motm_votes enable row level security;
alter table public.match_sport_motm_results enable row level security;

revoke all on table public.match_sport_motm_elections from public, anon, authenticated;
revoke all on table public.match_sport_motm_votes from public, anon, authenticated;
revoke all on table public.match_sport_motm_results from public, anon, authenticated;
grant select, insert, update on table public.match_sport_motm_elections to service_role;
grant select, insert, delete on table public.match_sport_motm_votes to service_role;
grant select, insert, delete on table public.match_sport_motm_results to service_role;

create or replace function private.match_has_eligible_motm_ballot(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.match_sport_participants voter
    join public.season_players voter_player on voter_player.id = voter.season_player_id
    join public.profiles voter_profile on voter_profile.id = voter_player.profile_id
    join public.match_sport_participants candidate
      on candidate.match_id = voter.match_id
     and candidate.final_presence_status = 'present'
    left join public.season_players candidate_player
      on candidate_player.id = candidate.season_player_id
    where voter.match_id = p_match_id
      and voter.final_presence_status = 'present'
      and voter.season_player_id is not null
      and voter_profile.status = 'active'
      and (
        candidate.guest_player_id is not null
        or candidate_player.profile_id is distinct from voter_profile.id
      )
  );
$function$;

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
as $function$
declare
  v_has_ballot boolean;
  v_state public.sport_vote_state;
  v_closes_at timestamptz;
begin
  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_state := case
    when v_has_ballot then 'open'::public.sport_vote_state
    else 'cancelled'::public.sport_vote_state
  end;
  v_closes_at := case when v_has_ballot then p_opens_at + interval '24 hours' else null end;

  insert into public.match_sport_motm_elections as election (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    p_finalization_version,
    v_state,
    case when v_has_ballot then p_opens_at else null end,
    v_closes_at,
    null,
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
      closed_at = null,
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
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id,
      p_action,
      p_actor,
      nullif(btrim(p_reason), ''),
      jsonb_build_object(
        'finalization_version', p_finalization_version,
        'state', v_state,
        'opens_at', case when v_has_ballot then p_opens_at else null end,
        'closes_at', v_closes_at
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
$function$;

create or replace function private.trg_reset_match_motm_after_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.reset_match_motm_election(
    new.match_id,
    new.version,
    new.created_at,
    new.created_by,
    case when new.validation_kind = 'correction'
      then 'Feuille de match corrigée : scrutin réinitialisé'
      else 'Feuille de match validée : scrutin ouvert'
    end,
    case when new.validation_kind = 'correction'
      then 'reset_motm_vote_after_correction'
      else 'open_motm_vote'
    end
  );
  return new;
end;
$function$;

create trigger trg_reset_match_motm_after_finalization
after insert on public.match_sport_finalization_versions
for each row execute function private.trg_reset_match_motm_after_finalization();

create or replace function private.close_match_motm_election(
  p_match_id uuid,
  p_require_due boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_election public.match_sport_motm_elections%rowtype;
  v_total integer := 0;
  v_max integer := 0;
begin
  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;

  if not found then
    return false;
  end if;
  if v_election.state <> 'open' then
    return v_election.state = 'closed';
  end if;
  if p_require_due and now() < v_election.closes_at then
    return false;
  end if;

  delete from public.match_sport_motm_results where match_id = p_match_id;

  insert into public.match_sport_motm_results(
    match_id, participant_id, finalization_version, votes_count, is_winner
  )
  select
    participant.match_id,
    participant.id,
    v_election.finalization_version,
    count(vote.voter_profile_id)::integer,
    false
  from public.match_sport_participants participant
  left join public.match_sport_motm_votes vote
    on vote.match_id = participant.match_id
   and vote.candidate_participant_id = participant.id
   and vote.finalization_version = v_election.finalization_version
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present'
  group by participant.match_id, participant.id;

  select coalesce(sum(result.votes_count), 0), coalesce(max(result.votes_count), 0)
  into v_total, v_max
  from public.match_sport_motm_results result
  where result.match_id = p_match_id;

  update public.match_sport_motm_results
  set is_winner = v_max > 0 and votes_count = v_max,
      computed_at = now()
  where match_id = p_match_id;

  delete from public.match_man_of_match where match_id = p_match_id;
  insert into public.match_man_of_match(match_id, season_player_id)
  select result.match_id, participant.season_player_id
  from public.match_sport_motm_results result
  join public.match_sport_participants participant
    on participant.id = result.participant_id
   and participant.match_id = result.match_id
  where result.match_id = p_match_id
    and result.is_winner
    and participant.season_player_id is not null
  on conflict do nothing;

  update public.match_sport_motm_elections
  set state = 'closed',
      closed_at = now(),
      total_votes = v_total,
      max_votes = v_max,
      updated_at = now()
  where match_id = p_match_id;

  update public.match_sport_workflows
  set vote_state = 'closed',
      updated_at = now()
  where match_id = p_match_id;

  return true;
end;
$function$;

create or replace function private.close_due_match_motm_elections()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row record;
  v_closed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state = 'open'
      and election.closes_at <= now()
    order by election.closes_at, election.match_id
    for update skip locked
  loop
    if private.close_match_motm_election(v_row.match_id, false) then
      v_closed := v_closed + 1;
    end if;
  end loop;

  return v_closed;
end;
$function$;

create or replace function private.get_match_motm_vote(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_election public.match_sport_motm_elections%rowtype;
  v_voter_participant_id uuid;
  v_has_voted boolean := false;
  v_can_vote boolean := false;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  perform private.close_match_motm_election(p_match_id, true);

  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;

  if not found then
    return null;
  end if;

  select participant.id into v_voter_participant_id
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present'
    and profile.id = v_actor
    and profile.status = 'active'
  order by participant.id
  limit 1;

  v_has_voted := exists (
    select 1 from public.match_sport_motm_votes vote
    where vote.match_id = p_match_id
      and vote.voter_profile_id = v_actor
      and vote.finalization_version = v_election.finalization_version
  );

  v_can_vote := v_election.state = 'open'
    and now() >= v_election.opens_at
    and now() < v_election.closes_at
    and v_voter_participant_id is not null
    and not v_has_voted
    and exists (
      select 1
      from public.match_sport_participants candidate
      left join public.season_players candidate_player
        on candidate_player.id = candidate.season_player_id
      where candidate.match_id = p_match_id
        and candidate.final_presence_status = 'present'
        and (
          candidate.guest_player_id is not null
          or candidate_player.profile_id is distinct from v_actor
        )
    );

  select jsonb_build_object(
    'match_id', election.match_id,
    'opponent_name', opponent.name,
    'score_as_grinta', finalization.score_as_grinta,
    'score_adverse', finalization.score_adverse,
    'state', election.state,
    'opens_at', election.opens_at,
    'closes_at', election.closes_at,
    'closed_at', election.closed_at,
    'finalization_version', election.finalization_version,
    'has_voted', v_has_voted,
    'can_vote', v_can_vote,
    'is_eligible_voter', v_voter_participant_id is not null,
    'total_votes', case when election.state = 'closed' then election.total_votes else null end,
    'max_votes', case when election.state = 'closed' then election.max_votes else null end,
    'candidates', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else btrim(concat_ws(' ', player.first_name, player.last_name))
        end,
        'is_guest', guest.id is not null,
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'is_self', player.profile_id = v_actor,
        'can_choose', guest.id is not null or player.profile_id is distinct from v_actor,
        'votes_count', case when election.state = 'closed' then coalesce(result.votes_count, 0) else null end,
        'is_winner', case when election.state = 'closed' then coalesce(result.is_winner, false) else null end
      ) order by
        case when election.state = 'closed' then coalesce(result.votes_count, 0) else 0 end desc,
        lower(coalesce(player.first_name, guest.first_name)),
        participant.id
    ) filter (where participant.id is not null), '[]'::jsonb)
  ) into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_finalizations finalization on finalization.match_id = election.match_id
  left join public.match_sport_participants participant
    on participant.match_id = election.match_id
   and participant.final_presence_status = 'present'
  left join public.season_players player on player.id = participant.season_player_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join public.match_sport_motm_results result
    on result.match_id = participant.match_id
   and result.participant_id = participant.id
  where election.match_id = p_match_id
  group by election.match_id, match.id, opponent.name, finalization.match_id;

  return v_result;
end;
$function$;

create or replace function private.cast_match_motm_vote(
  p_match_id uuid,
  p_candidate_participant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_election public.match_sport_motm_elections%rowtype;
  v_voter_participant_id uuid;
  v_candidate_profile_id uuid;
  v_cast_at timestamptz := now();
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  perform private.close_match_motm_election(p_match_id, true);

  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;

  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;
  if v_election.state <> 'open'
     or v_cast_at < v_election.opens_at
     or v_cast_at >= v_election.closes_at then
    raise exception 'MOTM vote is closed' using errcode = '22023';
  end if;

  select participant.id into v_voter_participant_id
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where participant.match_id = p_match_id
    and participant.final_presence_status = 'present'
    and profile.id = v_actor
    and profile.status = 'active'
  order by participant.id
  limit 1;

  if v_voter_participant_id is null then
    raise exception 'Only a permanently registered present player can vote'
      using errcode = '42501';
  end if;

  select player.profile_id into v_candidate_profile_id
  from public.match_sport_participants candidate
  left join public.season_players player on player.id = candidate.season_player_id
  where candidate.id = p_candidate_participant_id
    and candidate.match_id = p_match_id
    and candidate.final_presence_status = 'present';

  if not found then
    raise exception 'Candidate must be a present match participant' using errcode = '22023';
  end if;
  if v_candidate_profile_id = v_actor then
    raise exception 'A player cannot vote for himself' using errcode = '22023';
  end if;

  begin
    insert into public.match_sport_motm_votes(
      match_id, voter_profile_id, candidate_participant_id,
      finalization_version, cast_at
    ) values (
      p_match_id, v_actor, p_candidate_participant_id,
      v_election.finalization_version, v_cast_at
    );
  exception
    when unique_violation then
      raise exception 'MOTM vote is immutable and has already been cast'
        using errcode = '23505';
  end;

  return jsonb_build_object(
    'accepted', true,
    'cast_at', v_cast_at,
    'closes_at', v_election.closes_at
  );
end;
$function$;

create or replace function private.admin_cancel_match_motm_vote(
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
  v_version integer;
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

  select finalization_version into v_version
  from public.match_sport_motm_elections
  where match_id = p_match_id
  for update;
  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
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
  v_version integer;
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

  select finalization.version into v_version
  from public.match_sport_finalizations finalization
  where finalization.match_id = p_match_id;
  if not found then
    raise exception 'Final attendance must be validated first' using errcode = '22023';
  end if;

  return private.reset_match_motm_election(
    p_match_id,
    v_version,
    now(),
    v_actor,
    v_reason,
    'restart_motm_vote'
  );
end;
$function$;

create or replace function public.get_match_motm_vote(p_match_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.get_match_motm_vote(p_match_id);
$function$;

create or replace function public.cast_match_motm_vote(
  p_match_id uuid,
  p_candidate_participant_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.cast_match_motm_vote(p_match_id, p_candidate_participant_id);
$function$;

create or replace function public.admin_cancel_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.admin_cancel_match_motm_vote(p_match_id, p_reason);
$function$;

create or replace function public.admin_restart_match_motm_vote(
  p_match_id uuid,
  p_reason text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.admin_restart_match_motm_vote(p_match_id, p_reason);
$function$;

revoke all on function private.match_has_eligible_motm_ballot(uuid) from public, anon, authenticated;
revoke all on function private.reset_match_motm_election(uuid, integer, timestamptz, uuid, text, text)
  from public, anon, authenticated;
revoke all on function private.close_match_motm_election(uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.close_due_match_motm_elections()
  from public, anon, authenticated;
revoke all on function private.get_match_motm_vote(uuid) from public, anon, authenticated;
revoke all on function private.cast_match_motm_vote(uuid, uuid) from public, anon, authenticated;
revoke all on function private.admin_cancel_match_motm_vote(uuid, text)
  from public, anon, authenticated;
revoke all on function private.admin_restart_match_motm_vote(uuid, text)
  from public, anon, authenticated;

revoke all on function public.get_match_motm_vote(uuid) from public, anon;
revoke all on function public.cast_match_motm_vote(uuid, uuid) from public, anon;
revoke all on function public.admin_cancel_match_motm_vote(uuid, text) from public, anon;
revoke all on function public.admin_restart_match_motm_vote(uuid, text) from public, anon;
grant execute on function public.get_match_motm_vote(uuid) to authenticated;
grant execute on function public.cast_match_motm_vote(uuid, uuid) to authenticated;
grant execute on function public.admin_cancel_match_motm_vote(uuid, text) to authenticated;
grant execute on function public.admin_restart_match_motm_vote(uuid, text) to authenticated;

select cron.schedule(
  'sports-close-motm-votes',
  '* * * * *',
  $$select private.close_due_match_motm_elections();$$
);
