-- Uniformise l'appellation des joueurs dans le module sportif :
-- surnom si présent, sinon prénom — jamais le nom de famille.
-- Corrige le vote Homme du match, qui affichait « Prénom Nom ».

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
            btrim(guest.first_name) || ' (Invité)'
          else coalesce(nullif(btrim(player_profile.surnom), ''), btrim(player.first_name))
        end,
        'is_guest', guest.id is not null,
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'is_self', player.profile_id = v_actor,
        'can_choose', guest.id is not null or player.profile_id is distinct from v_actor,
        'votes_count', case when election.state = 'closed' then coalesce(result.votes_count, 0) else null end,
        'is_winner', case when election.state = 'closed' then coalesce(result.is_winner, false) else null end
      ) order by
        case when election.state = 'closed' then coalesce(result.votes_count, 0) else 0 end desc,
        lower(coalesce(nullif(btrim(player_profile.surnom), ''), player.first_name, guest.first_name)),
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
  left join public.profiles player_profile on player_profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join public.match_sport_motm_results result
    on result.match_id = participant.match_id
   and result.participant_id = participant.id
  where election.match_id = p_match_id
  group by election.match_id, match.id, opponent.name, finalization.match_id;

  return v_result;
end;
$function$;
