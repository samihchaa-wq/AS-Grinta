-- Nouveau cycle du scrutin Homme du match :
--   * il s'ouvre automatiquement 1 h 45 après le coup d'envoi (ou dès la
--     validation du résultat si elle a lieu avant), à partir de la
--     composition publiée — plus besoin d'attendre la feuille de match ;
--   * il se ferme toujours 24 h après le coup d'envoi ;
--   * à la fermeture, le détail nominatif des votes est révélé à tout le monde.
--
-- Les candidats et les votants sont désormais les joueurs de la composition
-- publiée (repli sur les présents validés pour un match sans composition).
-- La validation/correction n'efface plus les votes déjà exprimés.

-- Candidats/votants du scrutin : membres de la composition publiée
-- (titulaires + remplaçants), sinon repli sur les présents validés.
create or replace function private.match_motm_candidate_participants(p_match_id uuid)
returns table (participant_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select participant.id
  from public.match_sport_participants participant
  where participant.match_id = p_match_id
    and case
      when exists (
        select 1 from public.match_composition_publications pub
        where pub.match_id = p_match_id
      ) then exists (
        select 1 from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
      else participant.final_presence_status = 'present'
    end;
$function$;

-- Heure d'ouverture : 1 h 45 après le coup d'envoi, avancée à l'heure de
-- validation si le résultat a été rentré avant.
create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $function$
  select least(
    match.kickoff_at + interval '1 hour 45 minutes',
    coalesce(
      (
        select min(version.created_at)
        from public.match_sport_finalization_versions version
        where version.match_id = p_match_id
      ),
      match.kickoff_at + interval '1 hour 45 minutes'
    )
  )
  from public.matches match
  where match.id = p_match_id;
$function$;

-- Version « d'ancrage » du scrutin : version de composition publiée si elle
-- existe, sinon version de feuille de match (toujours >= 1).
create or replace function private.match_motm_anchor_version(p_match_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (
      select max(pub.version)
      from public.match_composition_publications pub
      where pub.match_id = p_match_id
    ),
    (
      select max(version.version)
      from public.match_sport_finalization_versions version
      where version.match_id = p_match_id
    ),
    1
  );
$function$;

-- Un scrutin est possible s'il existe au moins un votant (joueur avec compte
-- actif dans la composition) et au moins un autre candidat.
create or replace function private.match_has_eligible_motm_ballot(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from private.match_motm_candidate_participants(p_match_id) voter_candidate
    join public.match_sport_participants voter
      on voter.id = voter_candidate.participant_id
    join public.season_players voter_player on voter_player.id = voter.season_player_id
    join public.profiles voter_profile on voter_profile.id = voter_player.profile_id
    join private.match_motm_candidate_participants(p_match_id) other_candidate
      on other_candidate.participant_id <> voter.id
    join public.match_sport_participants candidate
      on candidate.id = other_candidate.participant_id
    left join public.season_players candidate_player
      on candidate_player.id = candidate.season_player_id
    where voter_profile.status = 'active'
      and (
        candidate.guest_player_id is not null
        or candidate_player.profile_id is distinct from voter_profile.id
      )
  );
$function$;

-- Crée le scrutin (état « draft ») dès qu'une source de candidats existe,
-- sans effacer d'éventuels votes déjà présents. Idempotent.
create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_exists boolean;
  v_kickoff timestamptz;
  v_has_source boolean;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
begin
  select true, match.kickoff_at
  into v_exists, v_kickoff
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select match.kickoff_at into v_kickoff
  from public.matches match
  where match.id = p_match_id;
  if v_kickoff is null then
    return;
  end if;

  -- Aucune composition publiée ni feuille validée : rien à ouvrir.
  v_has_source := exists (
    select 1 from public.match_composition_publications pub
    where pub.match_id = p_match_id
  ) or exists (
    select 1 from public.match_sport_finalization_versions version
    where version.match_id = p_match_id
  );
  if not v_has_source then
    return;
  end if;

  v_opens_at := private.match_motm_opens_at(p_match_id);
  v_closes_at := v_kickoff + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);
  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    case when v_has_ballot then 'draft' else 'cancelled' end,
    case when v_has_ballot then v_opens_at else null end,
    case when v_has_ballot then v_closes_at else null end,
    null,
    0,
    0,
    now(),
    now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = case when v_has_ballot then 'draft' else 'cancelled' end,
      updated_at = now()
  where match_id = p_match_id;
end;
$function$;

-- Ferme le scrutin et calcule les résultats à partir des candidats de la
-- composition. Accepte les états « open » et « draft » (dépassement tardif).
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
  if v_election.state not in ('open', 'draft') then
    return v_election.state = 'closed';
  end if;
  if p_require_due
     and (v_election.closes_at is null or now() < v_election.closes_at) then
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
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  left join public.match_sport_motm_votes vote
    on vote.match_id = participant.match_id
   and vote.candidate_participant_id = participant.id
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
      opens_at = coalesce(opens_at, v_election.closes_at - interval '24 hours'),
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

-- Fait progresser un scrutin selon l'heure : draft -> open à l'ouverture,
-- puis -> closed à l'échéance.
create or replace function private.transition_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_election public.match_sport_motm_elections%rowtype;
begin
  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;
  if not found then
    return;
  end if;

  if v_election.state = 'draft'
     and v_election.closes_at is not null
     and now() >= v_election.closes_at then
    perform private.close_match_motm_election(p_match_id, false);
    return;
  end if;

  if v_election.state = 'draft'
     and v_election.opens_at is not null
     and now() >= v_election.opens_at
     and now() < v_election.closes_at then
    update public.match_sport_motm_elections
    set state = 'open', updated_at = now()
    where match_id = p_match_id;
    update public.match_sport_workflows
    set vote_state = 'open', updated_at = now()
    where match_id = p_match_id;
    return;
  end if;

  if v_election.state = 'open'
     and v_election.closes_at is not null
     and now() >= v_election.closes_at then
    perform private.close_match_motm_election(p_match_id, false);
  end if;
end;
$function$;

-- CRON : ouvre les scrutins dus (compo publiée + coup d'envoi + 1 h 45) et
-- ferme ceux arrivés à échéance.
create or replace function private.close_due_match_motm_elections()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row record;
  v_processed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  -- 1) Crée les scrutins manquants pour les matchs récents dont la fenêtre
  --    d'ouverture est atteinte (composition publiée ou feuille validée).
  for v_row in
    select match.id as match_id
    from public.matches match
    where match.kickoff_at + interval '1 hour 45 minutes' <= now()
      and match.kickoff_at > now() - interval '30 days'
      and not exists (
        select 1 from public.match_sport_motm_elections election
        where election.match_id = match.id
      )
      and (
        exists (
          select 1 from public.match_composition_publications pub
          where pub.match_id = match.id
        )
        or exists (
          select 1 from public.match_sport_finalization_versions version
          where version.match_id = match.id
        )
      )
  loop
    perform private.ensure_match_motm_election(v_row.match_id);
  end loop;

  -- 2) Fait progresser les scrutins non finalisés (draft à ouvrir, ouverts à
  --    fermer).
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

-- À la validation / correction : ouvre (ou avance l'ouverture du) scrutin
-- sans jamais effacer les votes déjà exprimés.
create or replace function private.trg_reset_match_motm_after_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_opens_at timestamptz;
begin
  perform private.ensure_match_motm_election(new.match_id);

  v_opens_at := private.match_motm_opens_at(new.match_id);
  update public.match_sport_motm_elections election
  set opens_at = least(coalesce(election.opens_at, v_opens_at), v_opens_at),
      updated_at = now()
  where election.match_id = new.match_id
    and election.state in ('draft', 'open');

  perform private.transition_match_motm_election(new.match_id);
  return new;
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

  perform private.ensure_match_motm_election(p_match_id);
  perform private.transition_match_motm_election(p_match_id);

  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;

  if not found then
    return null;
  end if;

  select participant.id into v_voter_participant_id
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where profile.id = v_actor
    and profile.status = 'active'
  order by participant.id
  limit 1;

  v_has_voted := exists (
    select 1 from public.match_sport_motm_votes vote
    where vote.match_id = p_match_id
      and vote.voter_profile_id = v_actor
  );

  v_can_vote := v_election.state = 'open'
    and v_election.opens_at is not null
    and now() >= v_election.opens_at
    and now() < v_election.closes_at
    and v_voter_participant_id is not null
    and not v_has_voted
    and exists (
      select 1
      from private.match_motm_candidate_participants(p_match_id) candidate
      join public.match_sport_participants participant
        on participant.id = candidate.participant_id
      left join public.season_players candidate_player
        on candidate_player.id = participant.season_player_id
      where participant.id <> v_voter_participant_id
        and (
          participant.guest_player_id is not null
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
    'candidates', coalesce((
      select jsonb_agg(candidate_json order by candidate_order, candidate_name, candidate_pid)
      from (
        select
          jsonb_build_object(
            'participant_id', participant.id,
            'season_player_id', participant.season_player_id,
            'guest_player_id', participant.guest_player_id,
            'display_name', case
              when guest.id is not null then
                btrim(guest.first_name) || ' (Invité)'
              else coalesce(nullif(btrim(profile.surnom), ''), btrim(player.first_name))
            end,
            'is_guest', guest.id is not null,
            'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
            'is_self', player.profile_id = v_actor,
            'can_choose', guest.id is not null or player.profile_id is distinct from v_actor,
            'votes_count', case when election.state = 'closed' then coalesce(result.votes_count, 0) else null end,
            'is_winner', case when election.state = 'closed' then coalesce(result.is_winner, false) else null end
          ) as candidate_json,
          case when election.state = 'closed' then coalesce(result.votes_count, 0) else 0 end as candidate_order,
          coalesce(nullif(btrim(profile.surnom), ''), player.first_name, guest.first_name) as candidate_name,
          participant.id as candidate_pid
        from private.match_motm_candidate_participants(p_match_id) candidate
        join public.match_sport_participants participant
          on participant.id = candidate.participant_id
        left join public.season_players player on player.id = participant.season_player_id
        left join public.profiles profile on profile.id = player.profile_id
        left join public.guest_players guest on guest.id = participant.guest_player_id
        left join public.match_sport_motm_results result
          on result.match_id = participant.match_id
         and result.participant_id = participant.id
      ) candidates
    ), '[]'::jsonb),
    'ballots', case when election.state = 'closed' then coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'voter_name', coalesce(nullif(btrim(voter_profile.surnom), ''), btrim(voter_player.first_name)),
          'candidate_participant_id', vote.candidate_participant_id,
          'candidate_name', case
            when candidate_guest.id is not null then
              btrim(candidate_guest.first_name) || ' (Invité)'
            else coalesce(nullif(btrim(candidate_profile.surnom), ''), btrim(candidate_player.first_name))
          end
        )
        order by coalesce(nullif(btrim(voter_profile.surnom), ''), btrim(voter_player.first_name))
      )
      from public.match_sport_motm_votes vote
      join public.profiles voter_profile on voter_profile.id = vote.voter_profile_id
      left join public.season_players voter_player
        on voter_player.profile_id = voter_profile.id
      join public.match_sport_participants candidate
        on candidate.id = vote.candidate_participant_id
       and candidate.match_id = vote.match_id
      left join public.season_players candidate_player
        on candidate_player.id = candidate.season_player_id
      left join public.profiles candidate_profile
        on candidate_profile.id = candidate_player.profile_id
      left join public.guest_players candidate_guest
        on candidate_guest.id = candidate.guest_player_id
      where vote.match_id = p_match_id
    ), '[]'::jsonb) else null end
  ) into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  left join public.match_sport_finalizations finalization
    on finalization.match_id = election.match_id
  where election.match_id = p_match_id;

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
  v_candidate_ok boolean;
  v_cast_at timestamptz := now();
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  perform private.ensure_match_motm_election(p_match_id);
  perform private.transition_match_motm_election(p_match_id);

  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;

  if not found then
    raise exception 'MOTM vote is unavailable' using errcode = 'P0002';
  end if;
  if v_election.state <> 'open'
     or v_election.opens_at is null
     or v_cast_at < v_election.opens_at
     or v_cast_at >= v_election.closes_at then
    raise exception 'MOTM vote is closed' using errcode = '22023';
  end if;

  select participant.id into v_voter_participant_id
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player on player.id = participant.season_player_id
  join public.profiles profile on profile.id = player.profile_id
  where profile.id = v_actor
    and profile.status = 'active'
  order by participant.id
  limit 1;

  if v_voter_participant_id is null then
    raise exception 'Only a registered player from the lineup can vote'
      using errcode = '42501';
  end if;

  select true, candidate_player.profile_id
  into v_candidate_ok, v_candidate_profile_id
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  left join public.season_players candidate_player
    on candidate_player.id = participant.season_player_id
  where participant.id = p_candidate_participant_id;

  if not coalesce(v_candidate_ok, false) then
    raise exception 'Candidate must be part of the published lineup' using errcode = '22023';
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

  update public.match_sport_motm_elections
  set total_votes = total_votes + 1, updated_at = now()
  where match_id = p_match_id;

  return jsonb_build_object(
    'accepted', true,
    'cast_at', v_cast_at,
    'closes_at', v_election.closes_at
  );
end;
$function$;

-- Relance admin : rouvre un scrutin de zéro (24 h à partir de maintenant),
-- sans exiger une feuille de match validée.
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
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.matches match where match.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  delete from public.match_sport_motm_votes where match_id = p_match_id;
  delete from public.match_sport_motm_results where match_id = p_match_id;
  delete from public.match_man_of_match where match_id = p_match_id;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  v_version := private.match_motm_anchor_version(p_match_id);
  v_state := case when v_has_ballot then 'open' else 'cancelled' end;

  insert into public.match_sport_motm_elections as election (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    v_state,
    case when v_has_ballot then now() else null end,
    case when v_has_ballot then now() + interval '24 hours' else null end,
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
  set vote_state = v_state, updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'restart_motm_vote', v_actor, v_reason,
    jsonb_build_object('anchor_version', v_version, 'state', v_state)
  );

  return jsonb_build_object('match_id', p_match_id, 'state', v_state);
end;
$function$;

revoke all on function private.match_motm_candidate_participants(uuid) from public, anon, authenticated;
revoke all on function private.match_motm_opens_at(uuid) from public, anon, authenticated;
revoke all on function private.match_motm_anchor_version(uuid) from public, anon, authenticated;
revoke all on function private.ensure_match_motm_election(uuid) from public, anon, authenticated;
revoke all on function private.transition_match_motm_election(uuid) from public, anon, authenticated;

comment on function private.get_match_motm_vote(uuid) is
  'MOTM vote opening 1h45 after kickoff (or at validation) from the published lineup, closing 24h after kickoff, revealing every ballot.';
