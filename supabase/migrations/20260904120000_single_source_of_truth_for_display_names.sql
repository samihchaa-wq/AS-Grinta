-- Règle d'appellation unique.
--
-- L'ordre de priorité « surnom, sinon prénom du compte, sinon prénom de la
-- fiche d'effectif » était recopié à la main dans chaque fonction de lecture.
-- Rien ne garantissait que ces copies restent identiques : une seule oubliée
-- lors d'une évolution suffisait à faire apparaître un joueur sous deux noms
-- différents selon l'écran.
--
-- Cette migration crée les fonctions partagées qui portent désormais la règle,
-- et remplace chaque copie par un appel à ces fonctions. Le corps des fonctions
-- de lecture est repris tel quel : seule l'expression d'appellation change.
--
-- Deux effets voulus, en plus de la factorisation :
--
--   1. le tri d'une liste suit désormais le nom réellement affiché. Il était
--      calculé sur le surnom brut ; or un surnom non renseigné est enregistré
--      sous la forme d'une chaîne vide, pas d'un null. Tous les joueurs sans
--      surnom se retrouvaient donc regroupés en tête de liste dans un ordre
--      arbitraire au lieu d'être classés par prénom ;
--   2. une appellation introuvable renvoie null plutôt qu'une chaîne vide, ce
--      qui laisse le dernier repli explicite de l'appelant s'appliquer.

create or replace function public.person_display_name(
  p_surnom text,
  p_profile_first_name text,
  p_fallback_first_name text default null,
  p_fallback_last_name text default null
)
returns text
language sql
immutable
set search_path to ''
as $function$
  -- Priorité unique de l'application : surnom du compte, sinon prénom du
  -- compte, sinon prénom de repli (fiche d'effectif ou invité), sinon nom
  -- complet de repli. Un champ vide ou blanc vaut « non renseigné ».
  select coalesce(
    nullif(btrim(p_surnom), ''),
    nullif(btrim(p_profile_first_name), ''),
    nullif(btrim(p_fallback_first_name), ''),
    nullif(btrim(concat_ws(' ', p_fallback_first_name, p_fallback_last_name)), '')
  );
$function$;

comment on function public.person_display_name(text, text, text, text) is
  'Nom affiché d''une personne : surnom, sinon prénom du compte, sinon prénom de repli, sinon nom complet de repli. Source de vérité unique de l''appellation.';

create or replace function public.person_sort_key(
  p_surnom text,
  p_profile_first_name text,
  p_fallback_first_name text default null,
  p_fallback_last_name text default null
)
returns text
language sql
immutable
set search_path to ''
as $function$
  -- Une liste se classe comme elle se lit.
  select lower(public.person_display_name(
    p_surnom, p_profile_first_name, p_fallback_first_name, p_fallback_last_name
  ));
$function$;

comment on function public.person_sort_key(text, text, text, text) is
  'Clé de tri alignée sur public.person_display_name, pour qu''une liste soit classée sur le nom réellement affiché.';

create or replace function public.guest_display_name(
  p_first_name text,
  p_last_name text default null
)
returns text
language sql
immutable
set search_path to ''
as $function$
  -- Un invité n'a pas de compte, donc jamais de surnom.
  select btrim(concat_ws(' ', p_first_name, p_last_name));
$function$;

comment on function public.guest_display_name(text, text) is
  'Nom affiché d''un invité : prénom, éventuellement suivi de son nom. Un invité n''a pas de compte, donc pas de surnom.';

create or replace function public.guest_display_label(
  p_first_name text,
  p_last_name text default null
)
returns text
language sql
immutable
set search_path to ''
as $function$
  select public.guest_display_name(p_first_name, p_last_name) || ' (Invité)';
$function$;

comment on function public.guest_display_label(text, text) is
  'Nom affiché d''un invité, suivi de l''étiquette « (Invité) ».';

revoke all on function public.person_display_name(text, text, text, text)
  from public, anon;
revoke all on function public.person_sort_key(text, text, text, text)
  from public, anon;
revoke all on function public.guest_display_name(text, text)
  from public, anon;
revoke all on function public.guest_display_label(text, text)
  from public, anon;

grant execute on function public.person_display_name(text, text, text, text)
  to authenticated, service_role;
grant execute on function public.person_sort_key(text, text, text, text)
  to authenticated, service_role;
grant execute on function public.guest_display_name(text, text)
  to authenticated, service_role;
grant execute on function public.guest_display_label(text, text)
  to authenticated, service_role;


-- private.composition_snapshot : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."composition_snapshot"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'match_id', composition.match_id,
    'formation_code', composition.formation_code,
    'status', composition.status,
    'version', composition.version,
    'has_unpublished_changes', composition.has_unpublished_changes,
    'squad_size_exception_approved', composition.squad_size_exception_approved,
    'published_at', composition.published_at,
    'last_modified_at', composition.last_modified_at,
    'field_count', count(*) filter (where entry.zone = 'field'),
    'bench_count', count(*) filter (where entry.zone = 'bench'),
    'not_selected_count', count(*) filter (where entry.zone = 'not_selected'),
    'available_count', count(*) filter (where entry.zone = 'available'),
    'has_goalkeeper_warning', not coalesce(bool_or(
      entry.zone = 'field'
      and coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
    ), false),
    'entries', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'participant_id', participant.id,
          'season_player_id', participant.season_player_id,
          'guest_player_id', participant.guest_player_id,
          'display_name', case
            when guest.id is not null then
              public.guest_display_label(guest.first_name, guest.last_name)
            else public.person_display_name(profile.surnom, profile.first_name, player.first_name, player.last_name)
          end,
          'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
          'is_guest', guest.id is not null,
          'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
          'zone', entry.zone,
          'x', entry.x,
          'y', entry.y,
          'slot_label', entry.slot_label,
          'sort_order', entry.sort_order,
          'availability_status', participant.availability_status,
          'convocation_status', participant.convocation_status,
          'selection_status', participant.selection_status
        ) order by
          case entry.zone
            when 'field' then 1
            when 'bench' then 2
            when 'available' then 3
            else 4
          end,
          entry.sort_order,
          public.person_sort_key(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name)),
          participant.id
      ) filter (where entry.participant_id is not null),
      '[]'::jsonb
    )
  ) into v_result
  from public.match_compositions composition
  left join public.match_composition_entries entry
    on entry.match_id = composition.match_id
  left join public.match_sport_participants participant
    on participant.id = entry.participant_id
   and participant.match_id = entry.match_id
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  where composition.match_id = p_match_id
  group by composition.match_id;

  return v_result;
end;
$$;


-- private.get_match_availability_board : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."get_match_availability_board"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'kickoff_at', match.kickoff_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'composition_published', exists (
      select 1
      from public.match_composition_publications publication
      where publication.match_id = match.id
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'display_name', case
          when guest.id is not null then public.guest_display_name(guest.first_name)
          else public.person_display_name(profile.surnom, profile.first_name, player.first_name)
        end,
        'is_guest', guest.id is not null,
        'status', participant.availability_status,
        'convocation_status', participant.convocation_status,
        'waitlist_position', waitlist.position,
        'promoted_from_participant_id', participant.promoted_from_participant_id
      )
      order by
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null) then 0
          when participant.availability_status = 'available' then 1
          when participant.availability_status = 'absent' then 2
          when participant.availability_status = 'no_response' then 3
          else 4
        end,
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null)
            then waitlist.position
        end desc nulls last,
        case
          when participant.convocation_status = 'not_convoked'
            and participant.availability_status = 'available'
            then waitlist.position
        end asc nulls last,
        lower(coalesce(player.first_name, guest.first_name, '')),
        participant.id
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
   and participant.is_eligible
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;


-- private.get_match_live_add_player_options : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."get_match_live_add_player_options"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_state public.match_live_state;
  v_roster jsonb;
  v_guests jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach, administrator or moderator role required' using errcode = '42501';
  end if;

  select match.season_id, session.state
  into v_season_id, v_state
  from public.matches match
  join public.match_live_sessions session on session.match_id = match.id
  where match.id = p_match_id;

  if not found then
    raise exception 'Open the live workspace before adding a player' using errcode = '22023';
  end if;
  if v_state not in ('not_started', 'running', 'paused', 'halftime') then
    raise exception 'Players can only be added while the live session is open' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', candidate.participant_id,
      'season_player_id', candidate.season_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', false
    ) order by lower(candidate.display_name), candidate.season_player_id
  ), '[]'::jsonb)
  into v_roster
  from (
    select
      player.id as season_player_id,
      participant.id as participant_id,
      coalesce(public.person_display_name(profile.surnom, profile.first_name, player.first_name, player.last_name), 'Joueur') as display_name,
      coalesce(profile.photo_url, player.photo_url) as photo_url,
      player.is_goalkeeper
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    left join public.match_sport_participants participant
      on participant.match_id = p_match_id
     and participant.season_player_id = player.id
    where player.season_id = v_season_id
      and player.is_active
      and (player.profile_id is null or profile.status = 'active')
      and not exists (
        select 1
        from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
  ) candidate;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', candidate.participant_id,
      'guest_player_id', candidate.guest_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', true
    ) order by lower(candidate.display_name), candidate.guest_player_id
  ), '[]'::jsonb)
  into v_guests
  from (
    select
      guest.id as guest_player_id,
      participant.id as participant_id,
      public.guest_display_label(guest.first_name, guest.last_name) as display_name,
      guest.photo_url,
      guest.is_goalkeeper
    from public.guest_players guest
    left join public.match_sport_participants participant
      on participant.match_id = p_match_id
     and participant.guest_player_id = guest.id
    where guest.is_reusable
      and guest.archived_at is null
      and not exists (
        select 1
        from public.match_composition_entries entry
        where entry.match_id = p_match_id
          and entry.participant_id = participant.id
          and entry.zone in ('field', 'bench')
      )
  ) candidate;

  return jsonb_build_object(
    'match_id', p_match_id,
    'session_state', v_state,
    'roster', v_roster,
    'guests', v_guests
  );
end;
$$;


-- private.get_match_motm_vote : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."get_match_motm_vote"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    'is_home', match.location = 'domicile',
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
      select jsonb_agg(candidate_json order by candidate_order desc, candidate_name, candidate_pid)
      from (
        select
          jsonb_build_object(
            'participant_id', participant.id,
            'season_player_id', participant.season_player_id,
            'guest_player_id', participant.guest_player_id,
            'display_name', case
              when guest.id is not null then
                public.guest_display_label(guest.first_name)
              else public.person_display_name(profile.surnom, profile.first_name, player.first_name)
            end,
            'is_guest', guest.id is not null,
            'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
            'is_self', player.profile_id = v_actor,
            'can_choose', guest.id is not null or player.profile_id is distinct from v_actor,
            'goals', coalesce(participant.final_goals, 0),
            'clean_sheet', case
              when coalesce(player.is_goalkeeper, guest.is_goalkeeper, false)
                   and finalization.score_adverse is not null
                then finalization.score_adverse = 0
              else null
            end,
            'votes_count', case when election.state = 'closed' then coalesce(result.votes_count, 0) else null end,
            'is_winner', case when election.state = 'closed' then coalesce(result.is_winner, false) else null end
          ) as candidate_json,
          case when election.state = 'closed' then coalesce(result.votes_count, 0) else 0 end as candidate_order,
          public.person_display_name(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name)) as candidate_name,
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
    ), '[]'::jsonb)
  ) into v_result
  from public.match_sport_motm_elections election
  join public.matches match on match.id = election.match_id
  join public.opponents opponent on opponent.id = match.opponent_id
  left join public.match_sport_finalizations finalization
    on finalization.match_id = election.match_id
  where election.match_id = p_match_id;

  return v_result;
end;
$$;


-- private.get_published_match_composition : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."get_published_match_composition"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
  v_kickoff_at timestamptz;
  v_before_kickoff boolean;
  v_entries jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_participant record;
  v_field_count integer := 0;
  v_bench_count integer := 0;
  v_available_count integer := 0;
  v_not_selected_count integer := 0;
  v_latest_motm_version integer;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select publication.snapshot, match.kickoff_at
  into v_result, v_kickoff_at
  from public.match_composition_publications publication
  join public.matches match on match.id = publication.match_id
  where publication.match_id = p_match_id
  order by publication.version desc
  limit 1;

  if v_result is null then
    return null;
  end if;

  v_before_kickoff := now() < v_kickoff_at;

  select max(finalization_version) into v_latest_motm_version
  from public.match_sport_motm_results
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(v_result -> 'entries', '[]'::jsonb))
    order by coalesce((value ->> 'sort_order')::integer, 0)
  loop
    select
      participant.availability_status::text as availability_status,
      participant.convocation_status::text as convocation_status,
      participant.final_presence_status::text as final_presence_status,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      public.person_display_name(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name)) as display_name,
      exists (
        select 1 from public.match_sport_motm_results result
        where result.match_id = p_match_id
          and result.participant_id = participant.id
          and result.is_winner
          and result.finalization_version = v_latest_motm_version
      ) as is_motm
    into v_participant
    from public.match_sport_participants participant
    left join public.season_players player on player.id = participant.season_player_id
    left join public.profiles profile on profile.id = player.profile_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and participant.id = (v_entry ->> 'participant_id')::uuid;

    if found then
      v_entry := v_entry || jsonb_build_object(
        'availability_status', v_participant.availability_status,
        'convocation_status', v_participant.convocation_status,
        'photo_url', v_participant.photo_url,
        'goals', v_participant.goals,
        'is_motm', v_participant.is_motm,
        'display_name', coalesce(v_participant.display_name, v_entry ->> 'display_name')
      );
      if v_before_kickoff then
        -- La composition publiée montre ce que l'admin a décidé : un convoqué
        -- reste affiché à son poste même si sa disponibilité dit le contraire.
        if v_participant.convocation_status <> 'convoked'
           and (v_entry ->> 'zone') in ('field', 'bench', 'available') then
          v_entry := v_entry || jsonb_build_object(
            'zone', 'not_selected', 'x', null, 'y', null,
            'selection_status', 'not_selected'
          );
        end if;
      elsif v_participant.final_presence_status = 'present'
            and (v_entry ->> 'zone') in ('available', 'not_selected') then
        v_entry := v_entry || jsonb_build_object(
          'zone', 'bench', 'selection_status', 'substitute'
        );
      end if;
    end if;

    case v_entry ->> 'zone'
      when 'field' then v_field_count := v_field_count + 1;
      when 'bench' then v_bench_count := v_bench_count + 1;
      when 'available' then v_available_count := v_available_count + 1;
      else v_not_selected_count := v_not_selected_count + 1;
    end case;

    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  for v_participant in
    select
      participant.id,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      public.person_display_name(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name)) as display_name,
      coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
      exists (
        select 1 from public.match_sport_motm_results result
        where result.match_id = p_match_id
          and result.participant_id = participant.id
          and result.is_winner
          and result.finalization_version = v_latest_motm_version
      ) as is_motm
    from public.match_sport_participants participant
    left join public.season_players player on player.id = participant.season_player_id
    left join public.profiles profile on profile.id = player.profile_id
    left join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and participant.final_presence_status = 'present'
      and not exists (
        select 1 from jsonb_array_elements(v_entries)
        where (value ->> 'participant_id')::uuid = participant.id
      )
  loop
    v_entry := jsonb_build_object(
      'participant_id', v_participant.id,
      'season_player_id', v_participant.season_player_id,
      'guest_player_id', v_participant.guest_player_id,
      'display_name', v_participant.display_name,
      'photo_url', v_participant.photo_url,
      'goals', v_participant.goals,
      'is_motm', v_participant.is_motm,
      'is_goalkeeper', v_participant.is_goalkeeper,
      'is_guest', v_participant.guest_player_id is not null,
      'zone', 'bench',
      'selection_status', 'substitute',
      'availability_status', 'available',
      'convocation_status', 'convoked',
      'x', null, 'y', null,
      'sort_order', 999
    );
    v_bench_count := v_bench_count + 1;
    v_entries := v_entries || jsonb_build_array(v_entry);
  end loop;

  return v_result || jsonb_build_object(
    'entries', v_entries,
    'field_count', v_field_count,
    'bench_count', v_bench_count,
    'available_count', v_available_count,
    'not_selected_count', v_not_selected_count
  );
end;
$$;


-- private.get_sport_waitlist : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."get_sport_waitlist"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, (select auth.uid()));
  perform private.finalize_due_waitlist_turns_for_season(v_season_id);

  select jsonb_build_object(
    'season_id', season.id,
    'season_name', season.name,
    'entries', coalesce(jsonb_agg(
      jsonb_build_object(
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'display_name', public.person_display_name(profile.surnom, profile.first_name, player.first_name),
        'position', entry.position,
        'previous_season_attendance_count', entry.previous_season_attendance_count,
        'previous_season_match_count', entry.previous_season_match_count,
        'source', entry.source,
        'updated_at', entry.updated_at
      )
      order by entry.position
    ), '[]'::jsonb)
  )
  into v_result
  from public.seasons season
  left join public.sport_waitlist_entries entry on entry.season_id = season.id
  left join public.season_players player on player.id = entry.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  where season.id = v_season_id
  group by season.id, season.name;

  return v_result;
end;
$$;


-- private.get_sport_waitlist_readonly : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."get_sport_waitlist_readonly"("p_season_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_season_id uuid;
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  v_season_id := private.resolve_open_sport_season(p_season_id);

  select jsonb_build_object(
    'season_id', season.id,
    'season_name', season.name,
    'entries', coalesce(jsonb_agg(
      jsonb_build_object(
        'season_player_id', player.id,
        'first_name', player.first_name,
        'last_name', player.last_name,
        'display_name', public.person_display_name(profile.surnom, profile.first_name, player.first_name),
        'position', entry.position,
        'previous_season_attendance_count', entry.previous_season_attendance_count,
        'previous_season_match_count', entry.previous_season_match_count,
        'source', entry.source,
        'updated_at', entry.updated_at
      )
      order by entry.position
    ), '[]'::jsonb)
  )
  into v_result
  from public.seasons season
  left join public.sport_waitlist_entries entry on entry.season_id = season.id
  left join public.season_players player on player.id = entry.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  where season.id = v_season_id
  group by season.id, season.name;

  return v_result;
end;
$$;


-- private.match_motm_result_notification_payloads : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260809232339_audit_priority_reliability_fixes.sql.
CREATE OR REPLACE FUNCTION "private"."match_motm_result_notification_payloads"("p_match_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_election_state public.sport_vote_state;
  v_winner_names text;
  v_winner_count integer := 0;
  v_winner_profile_ids uuid[] := array[]::uuid[];
  v_general_profile_ids uuid[] := array[]::uuid[];
  v_general_title text;
  v_general_message text;
  v_winner_title text;
  v_winner_message text;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select election.state
  into v_election_state
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;

  if v_election_state is distinct from 'closed'::public.sport_vote_state then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  select
    string_agg(winner.display_name, ', ' order by lower(winner.display_name)),
    count(*)::integer,
    coalesce(
      array_agg(distinct winner.profile_id)
        filter (where winner.profile_id is not null),
      array[]::uuid[]
    )
  into v_winner_names, v_winner_count, v_winner_profile_ids
  from (
    select
      case
        when guest.id is not null then
          public.guest_display_label(guest.first_name, guest.last_name)
        else coalesce(public.person_display_name(profile.surnom, profile.first_name, player.first_name, player.last_name), 'Joueur')
      end as display_name,
      profile.id as profile_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    left join public.season_players player
      on player.id = participant.season_player_id
    left join public.profiles profile
      on profile.id = player.profile_id
     and profile.status = 'active'
     and profile.notify_motm_vote
    left join public.guest_players guest
      on guest.id = participant.guest_player_id
    where result.match_id = p_match_id
      and result.is_winner
  ) winner;

  -- Aucun gagnant (par exemple aucun vote) : aucun push de résultat.
  if v_winner_count = 0 then
    return jsonb_build_object(
      'general_profile_ids', '[]'::jsonb,
      'winner_profile_ids', '[]'::jsonb
    );
  end if;

  -- Même population que l'ouverture du vote : joueurs candidats avec compte
  -- actif et préférence HDM activée. Les élus sont retirés du groupe collectif.
  select coalesce(array_agg(distinct profile.id), array[]::uuid[])
  into v_general_profile_ids
  from private.match_motm_candidate_participants(p_match_id) candidate
  join public.match_sport_participants participant
    on participant.id = candidate.participant_id
  join public.season_players player
    on player.id = participant.season_player_id
  join public.profiles profile
    on profile.id = player.profile_id
  where profile.status = 'active'
    and profile.notify_motm_vote
    and not (profile.id = any(v_winner_profile_ids));

  if v_winner_count = 1 then
    v_general_title := 'Homme du match';
    v_general_message := format('%s a été élu Homme du match !', v_winner_names);
    v_winner_title := 'Homme du match';
    v_winner_message := 'Bravo, tu as été élu Homme du match !';
  else
    v_general_title := 'Co-Hommes du match';
    v_general_message := format(
      '%s ont été élus co-Hommes du match !',
      v_winner_names
    );
    v_winner_title := 'Co-Homme du match';
    v_winner_message := 'Bravo, tu as été élu co-Homme du match !';
  end if;

  return jsonb_build_object(
    'general_profile_ids', to_jsonb(v_general_profile_ids),
    'winner_profile_ids', to_jsonb(v_winner_profile_ids),
    'general_title', v_general_title,
    'general_message', v_general_message,
    'winner_title', v_winner_title,
    'winner_message', v_winner_message
  );
end;
$$;


-- private.get_match_live_timeline : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260827160000_assists_live_capture.sql.
create or replace function private.get_match_live_timeline(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_exported boolean;
  v_events jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select session.exported into v_exported
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if not found or not coalesce(v_exported, false) then
    return null;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'event_type', event.event_type,
      'minute', event.minute,
      'half', event.half,
      'scorer_name', case
        when scorer_guest.id is not null then
          public.guest_display_label(scorer_guest.first_name)
        else public.person_display_name(scorer_profile.surnom, scorer_profile.first_name, scorer_player.first_name)
      end,
      'assist_name', case
        when assist_guest.id is not null then
          public.guest_display_label(assist_guest.first_name)
        else public.person_display_name(assist_profile.surnom, assist_profile.first_name, assist_player.first_name)
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_name', case
        when in_guest.id is not null then
          public.guest_display_label(in_guest.first_name)
        else public.person_display_name(in_profile.surnom, in_profile.first_name, in_player.first_name)
      end,
      'player_out_name', case
        when out_guest.id is not null then
          public.guest_display_label(out_guest.first_name)
        else public.person_display_name(out_profile.surnom, out_profile.first_name, out_player.first_name)
      end
    ) order by event.half, event.minute, event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants assist_p on assist_p.id = event.assist_participant_id
  left join public.season_players assist_player on assist_player.id = assist_p.season_player_id
  left join public.profiles assist_profile on assist_profile.id = assist_player.profile_id
  left join public.guest_players assist_guest on assist_guest.id = assist_p.guest_player_id
  left join public.match_sport_participants in_p on in_p.id = event.player_in_participant_id
  left join public.season_players in_player on in_player.id = in_p.season_player_id
  left join public.profiles in_profile on in_profile.id = in_player.profile_id
  left join public.guest_players in_guest on in_guest.id = in_p.guest_player_id
  left join public.match_sport_participants out_p on out_p.id = event.player_out_participant_id
  left join public.season_players out_player on out_player.id = out_p.season_player_id
  left join public.profiles out_profile on out_profile.id = out_player.profile_id
  left join public.guest_players out_guest on out_guest.id = out_p.guest_player_id
  where event.match_id = p_match_id;

  return jsonb_build_object('match_id', p_match_id, 'events', v_events);
end;
$function$;


-- private.match_live_snapshot : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260827160000_assists_live_capture.sql.
create or replace function private.match_live_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_session jsonb;
  v_events jsonb;
  v_counts jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', session.match_id,
    'state', session.state,
    'planned_duration_minutes', session.planned_duration_minutes,
    'half', session.half,
    'elapsed_seconds', session.elapsed_seconds,
    'running_since', session.running_since,
    'score_as_grinta', session.score_as_grinta,
    'score_adverse', session.score_adverse,
    'started_at', session.started_at,
    'finished_at', session.finished_at,
    'exported', session.exported,
    'exported_at', session.exported_at,
    'lineup_revision', session.lineup_revision,
    'true_elapsed_seconds',
      session.elapsed_seconds + case
        when session.state = 'running'
        then greatest(0, extract(epoch from now() - session.running_since))::integer
        else 0
      end,
    'display_minute',
      (session.elapsed_seconds + case
        when session.state = 'running'
        then greatest(0, extract(epoch from now() - session.running_since))::integer
        else 0
      end) / 60 + 1
  )
  into v_session
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  if v_session is null then
    return jsonb_build_object('match_id', p_match_id, 'state', null, 'session_exists', false);
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', event.id,
      'event_type', event.event_type,
      'minute', event.minute,
      'half', event.half,
      'scorer_participant_id', event.scorer_participant_id,
      'scorer_name', case
        when scorer_guest.id is not null then
          public.guest_display_label(scorer_guest.first_name)
        else public.person_display_name(scorer_profile.surnom, scorer_profile.first_name, scorer_player.first_name)
      end,
      'assist_participant_id', event.assist_participant_id,
      'assist_name', case
        when assist_guest.id is not null then
          public.guest_display_label(assist_guest.first_name)
        else public.person_display_name(assist_profile.surnom, assist_profile.first_name, assist_player.first_name)
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_participant_id', event.player_in_participant_id,
      'player_in_name', case
        when in_guest.id is not null then
          public.guest_display_label(in_guest.first_name)
        else public.person_display_name(in_profile.surnom, in_profile.first_name, in_player.first_name)
      end,
      'player_out_participant_id', event.player_out_participant_id,
      'player_out_name', case
        when out_guest.id is not null then
          public.guest_display_label(out_guest.first_name)
        else public.person_display_name(out_profile.surnom, out_profile.first_name, out_player.first_name)
      end,
      'is_opponent_own_goal', coalesce(event.is_opponent_own_goal, false),
      'created_at', event.created_at
    ) order by event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants assist_p on assist_p.id = event.assist_participant_id
  left join public.season_players assist_player on assist_player.id = assist_p.season_player_id
  left join public.profiles assist_profile on assist_profile.id = assist_player.profile_id
  left join public.guest_players assist_guest on assist_guest.id = assist_p.guest_player_id
  left join public.match_sport_participants in_p on in_p.id = event.player_in_participant_id
  left join public.season_players in_player on in_player.id = in_p.season_player_id
  left join public.profiles in_profile on in_profile.id = in_player.profile_id
  left join public.guest_players in_guest on in_guest.id = in_p.guest_player_id
  left join public.match_sport_participants out_p on out_p.id = event.player_out_participant_id
  left join public.season_players out_player on out_player.id = out_p.season_player_id
  left join public.profiles out_profile on out_profile.id = out_player.profile_id
  left join public.guest_players out_guest on out_guest.id = out_p.guest_player_id
  where event.match_id = p_match_id;

  select coalesce(jsonb_object_agg(participant_id, times_benched), '{}'::jsonb)
  into v_counts
  from (
    select
      participant.id as participant_id,
      (
        case when coalesce(session.starting_lineup_snapshot -> participant.id::text, 'null'::jsonb) = '"bench"'::jsonb
          then 1 else 0
        end
        + coalesce((
          select count(*)
          from public.match_live_events sub_event
          where sub_event.match_id = p_match_id
            and sub_event.event_type = 'substitution'
            and sub_event.player_out_participant_id = participant.id
        ), 0)
      ) as times_benched
    from public.match_sport_participants participant
    cross join public.match_live_sessions session
    where participant.match_id = p_match_id
      and session.match_id = p_match_id
      and (participant.is_eligible or participant.final_presence_status <> 'pending')
  ) counted
  where counted.times_benched > 0;

  return v_session
    || jsonb_build_object('session_exists', true)
    || jsonb_build_object('lineup', private.composition_snapshot(p_match_id))
    || jsonb_build_object('events', v_events)
    || jsonb_build_object('substitute_counts', v_counts);
end;
$function$;


-- private.get_match_sport_report : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260829000100_match_sport_report_read.sql.
create or replace function private.get_match_sport_report(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_live_state text;
  v_live_exported boolean;
  v_live_finished boolean;
  v_status text;
  v_closes_at timestamptz;
  v_is_validated boolean;
  v_season_id uuid;
  v_roster jsonb;
  v_guests jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() and not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status::text, match.season_id
  into v_status, v_season_id
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  v_base := private.match_sport_finalization_snapshot(p_match_id);
  if v_base is null then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;

  v_is_validated := coalesce((v_base ->> 'is_validated')::boolean, false);
  v_closes_at := private.match_postgame_correction_closes_at(p_match_id);

  select session.state::text, session.exported, session.state = 'finished'
  into v_live_state, v_live_exported, v_live_finished
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  -- Joueurs qu'on peut encore ajouter à l'effectif du compte rendu : ceux du
  -- roster sans participation ouverte, et les invités réutilisables.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'season_player_id', candidate.season_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', false
    ) order by lower(candidate.display_name), candidate.season_player_id
  ), '[]'::jsonb)
  into v_roster
  from (
    select
      player.id as season_player_id,
      coalesce(public.person_display_name(profile.surnom, profile.first_name, player.first_name, player.last_name), 'Joueur') as display_name,
      coalesce(profile.photo_url, player.photo_url) as photo_url,
      player.is_goalkeeper
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    where player.season_id = v_season_id
      and player.is_active
      and (player.profile_id is null or profile.status = 'active')
      and not exists (
        select 1
        from public.match_sport_participants participant
        where participant.match_id = p_match_id
          and participant.season_player_id = player.id
          and (
            participant.is_eligible
            or participant.final_presence_status <> 'pending'
          )
      )
  ) candidate;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'guest_player_id', guest.id,
      'display_name', btrim(concat_ws(' ', guest.first_name, guest.last_name)),
      'photo_url', guest.photo_url,
      'is_goalkeeper', guest.is_goalkeeper,
      'is_guest', true
    ) order by lower(guest.first_name), guest.id
  ), '[]'::jsonb)
  into v_guests
  from public.guest_players guest
  where guest.is_reusable
    and guest.archived_at is null
    and not exists (
      select 1
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.guest_player_id = guest.id
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    );

  return v_base || jsonb_build_object(
    'lineup', private.match_sport_report_lineup(p_match_id),
    'is_correction', v_is_validated,
    'correction_closes_at', v_closes_at,
    'is_editable', v_status <> 'archive'
      and (
        not v_is_validated
        or v_closes_at is null
        or now() < v_closes_at
      ),
    'live_state', v_live_state,
    'live_exported', coalesce(v_live_exported, false),
    'live_finished', coalesce(v_live_finished, false),
    'add_player_options', jsonb_build_object(
      'roster', v_roster,
      'guests', v_guests
    )
  );
end;
$function$;


-- private.match_sport_finalization_snapshot : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260829000100_match_sport_report_read.sql.
create or replace function private.match_sport_finalization_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  with latest_publication as (
    select publication.version, publication.snapshot
    from public.match_composition_publications publication
    where publication.match_id = p_match_id
    order by publication.version desc
    limit 1
  ), planned_entries as (
    select
      (entry ->> 'participant_id')::uuid as participant_id,
      entry ->> 'zone' as planned_zone
    from latest_publication publication,
      lateral jsonb_array_elements(
        coalesce(publication.snapshot -> 'entries', '[]'::jsonb)
      ) entry
  )
  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'is_home', match.location = 'domicile',
    'kickoff_at', match.kickoff_at,
    'match_status', match.status,
    'is_validated', finalization.match_id is not null,
    'version', coalesce(finalization.version, 0),
    'score_as_grinta', coalesce(finalization.score_as_grinta, match.score_as_grinta, 0),
    'score_adverse', coalesce(finalization.score_adverse, match.score_adverse, 0),
    'composition_version', coalesce(finalization.composition_version, workflow.composition_version, 0),
    'presence_state', workflow.presence_state,
    'vote_state', workflow.vote_state,
    'validated_at', finalization.validated_at,
    'corrected_at', finalization.corrected_at,
    'goal_actions', private.match_sport_goal_actions_json(p_match_id),
    'participants', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'is_guest', participant.guest_player_id is not null,
        'display_name', case
          when guest.id is not null then
            public.guest_display_label(guest.first_name, guest.last_name)
          else public.person_display_name(profile.surnom, profile.first_name, player.first_name, player.last_name)
        end,
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'planned_zone', coalesce(planned.planned_zone, case participant.selection_status
          when 'starter' then 'field'
          when 'substitute' then 'bench'
          when 'not_selected' then 'not_selected'
          else 'available'
        end),
        'present', case
          when finalization.match_id is not null then participant.final_presence_status = 'present'
          else coalesce(planned.planned_zone in ('field', 'bench'), false)
        end,
        'final_presence_status', participant.final_presence_status,
        'final_selection_status', case
          when finalization.match_id is not null then participant.final_selection_status
          when planned.planned_zone = 'field' then 'starter'::public.sport_selection_status
          when planned.planned_zone = 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        'goals', participant.final_goals,
        'assists', participant.final_assists,
        'clean_sheet', participant.final_clean_sheet,
        'is_motm', exists (
          select 1
          from public.match_sport_motm_results result
          where result.match_id = p_match_id
            and result.participant_id = participant.id
            and result.is_winner
            and result.finalization_version = (
              select max(latest.finalization_version)
              from public.match_sport_motm_results latest
              where latest.match_id = p_match_id
            )
        )
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        public.person_sort_key(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name)),
        participant.id
    ) filter (
      where participant.id is not null
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  left join public.match_sport_participants participant on participant.match_id = match.id
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;


-- private.match_sport_goal_actions_json : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260829000100_match_sport_report_read.sql.
create or replace function private.match_sport_goal_actions_json(p_match_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', action.id,
        'ordinal', action.ordinal,
        'minute', action.minute,
        'team_side', action.team_side,
        'scorer_participant_id', action.scorer_participant_id,
        'scorer_name', case
          when scorer_guest.id is not null then
            public.guest_display_label(scorer_guest.first_name)
          else public.person_display_name(scorer_profile.surnom, scorer_profile.first_name, scorer_player.first_name)
        end,
        'assist_participant_id', action.assist_participant_id,
        'assist_kind', action.assist_kind,
        'assist_name', case
          when assist_guest.id is not null then
            public.guest_display_label(assist_guest.first_name)
          else public.person_display_name(assist_profile.surnom, assist_profile.first_name, assist_player.first_name)
        end,
        'is_own_goal', action.is_own_goal,
        'source', action.source,
        'source_live_event_id', action.source_live_event_id
      ) order by action.ordinal
    ),
    '[]'::jsonb
  )
  from public.match_sport_goal_actions action
  left join public.match_sport_participants scorer_p
    on scorer_p.id = action.scorer_participant_id
  left join public.season_players scorer_player
    on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile
    on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest
    on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants assist_p
    on assist_p.id = action.assist_participant_id
  left join public.season_players assist_player
    on assist_player.id = assist_p.season_player_id
  left join public.profiles assist_profile
    on assist_profile.id = assist_player.profile_id
  left join public.guest_players assist_guest
    on assist_guest.id = assist_p.guest_player_id
  where action.match_id = p_match_id;
$function$;


-- private.match_sport_report_lineup : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260829000100_match_sport_report_read.sql.
create or replace function private.match_sport_report_lineup(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_has_finalization boolean;
  v_start_zones jsonb;
  v_start_entries jsonb;
  v_start_formation text;
  v_formation_code text;
  v_live_started boolean;
  v_has_placement boolean;
  v_result jsonb;
begin
  select exists (
    select 1
    from public.match_sport_finalizations finalization
    where finalization.match_id = p_match_id
  ) into v_has_finalization;

  select
    session.starting_lineup_snapshot,
    session.starting_lineup_entries,
    session.starting_formation_code,
    session.started_at is not null
  into v_start_zones, v_start_entries, v_start_formation, v_live_started
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  select composition.formation_code
  into v_formation_code
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  select exists (
    select 1
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.zone in ('field', 'bench')
  ) into v_has_placement;

  with resolved as (
    select
      participant.id as participant_id,
      participant.season_player_id,
      participant.guest_player_id,
      participant.availability_status,
      participant.convocation_status,
      participant.selection_status,
      player.is_goalkeeper as player_goalkeeper,
      guest.is_goalkeeper as guest_goalkeeper,
      guest.id as guest_id,
      guest.first_name as guest_first_name,
      guest.last_name as guest_last_name,
      guest.photo_url as guest_photo,
      profile.surnom as profile_surnom,
      profile.first_name as profile_first_name,
      profile.photo_url as profile_photo,
      player.first_name as player_first_name,
      player.last_name as player_last_name,
      player.photo_url as player_photo,
      entry.zone::text as current_zone,
      entry.x as current_x,
      entry.y as current_y,
      entry.slot_label as current_slot,
      coalesce(entry.sort_order, 900) as current_sort,
      v_start_entries -> participant.id::text as start_entry,
      case
        when v_has_finalization then
          case
            -- Un joueur rattaché après la validation n'a encore aucun statut :
            -- il rejoint le banc plutôt que la liste des joueurs retirés.
            when participant.final_presence_status = 'pending' then 'bench'
            when participant.final_presence_status <> 'present' then 'not_selected'
            when participant.final_selection_status = 'starter' then 'field'
            else 'bench'
          end
        when coalesce(v_start_entries, '{}'::jsonb) ? participant.id::text then
          v_start_entries -> participant.id::text ->> 'zone'
        when coalesce(v_start_zones, '{}'::jsonb) ? participant.id::text then
          v_start_zones ->> participant.id::text
        when coalesce(v_live_started, false) then
          -- Joueur ajouté après le coup d'envoi : il fait partie de l'effectif
          -- du compte rendu, sur le banc.
          case
            when entry.zone in ('field', 'bench') then 'bench'
            else 'not_selected'
          end
        when v_has_placement then coalesce(entry.zone::text, 'not_selected')
        else 'bench'
      end as zone,
      case
        when v_has_finalization then 'finalization'
        when coalesce(v_start_entries, '{}'::jsonb) ? participant.id::text then 'kickoff'
        else 'composition'
      end as zone_source
    from public.match_sport_participants participant
    left join public.match_composition_entries entry
      on entry.match_id = p_match_id
     and entry.participant_id = participant.id
    left join public.season_players player
      on player.id = participant.season_player_id
    left join public.profiles profile
      on profile.id = player.profile_id
    left join public.guest_players guest
      on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and (
        participant.is_eligible
        or participant.final_presence_status <> 'pending'
      )
  )
  select jsonb_build_object(
    'match_id', p_match_id,
    'formation_code', case
      when v_has_finalization then coalesce(v_formation_code, v_start_formation)
      else coalesce(v_start_formation, v_formation_code)
    end,
    'status', 'draft',
    'version', 0,
    'has_unpublished_changes', true,
    'squad_size_exception_approved', false,
    'entries', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'participant_id', resolved.participant_id,
          'season_player_id', resolved.season_player_id,
          'guest_player_id', resolved.guest_player_id,
          'is_guest', resolved.guest_id is not null,
          'display_name', case
            when resolved.guest_id is not null then
              public.guest_display_label(resolved.guest_first_name, resolved.guest_last_name)
            else public.person_display_name(resolved.profile_surnom, resolved.profile_first_name, resolved.player_first_name, resolved.player_last_name)
          end,
          'photo_url', coalesce(
            resolved.profile_photo, resolved.player_photo, resolved.guest_photo
          ),
          'is_goalkeeper', coalesce(
            resolved.player_goalkeeper, resolved.guest_goalkeeper, false
          ),
          'zone', resolved.zone,
          'x', case
            when resolved.zone <> 'field' then null
            when resolved.zone_source = 'kickoff'
              then coalesce((resolved.start_entry ->> 'x')::double precision, resolved.current_x)
            else resolved.current_x
          end,
          'y', case
            when resolved.zone <> 'field' then null
            when resolved.zone_source = 'kickoff'
              then coalesce((resolved.start_entry ->> 'y')::double precision, resolved.current_y)
            else resolved.current_y
          end,
          'slot_label', case
            when resolved.zone_source = 'kickoff'
              then coalesce(resolved.start_entry ->> 'slot_label', resolved.current_slot)
            else resolved.current_slot
          end,
          'sort_order', case
            when resolved.zone_source = 'kickoff'
              then coalesce((resolved.start_entry ->> 'sort_order')::integer, resolved.current_sort)
            else resolved.current_sort
          end,
          'availability_status', resolved.availability_status,
          'convocation_status', resolved.convocation_status,
          'selection_status', resolved.selection_status
        ) order by
          case resolved.zone
            when 'field' then 1
            when 'bench' then 2
            else 3
          end,
          resolved.current_sort,
          public.person_sort_key(resolved.profile_surnom, resolved.profile_first_name, coalesce(nullif(btrim(resolved.player_first_name), ''), resolved.guest_first_name)),
          resolved.participant_id
      ),
      '[]'::jsonb
    )
  )
  into v_result
  from resolved;

  return v_result;
end;
$function$;


-- private.match_live_report_goal_actions_json : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260831000500_live_report_handoff.sql.
create or replace function private.match_live_report_goal_actions_json(
  p_match_id uuid
)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', null,
        'ordinal', projected.ordinal,
        'minute', projected.minute,
        'team_side', projected.team_side,
        'scorer_participant_id', projected.scorer_participant_id,
        'scorer_name', projected.scorer_name,
        'assist_participant_id', projected.assist_participant_id,
        'assist_kind', projected.assist_kind,
        'assist_name', projected.assist_name,
        'is_own_goal', projected.is_own_goal,
        'source', 'live',
        'source_live_event_id', projected.source_live_event_id
      ) order by projected.ordinal
    ),
    '[]'::jsonb
  )
  from (
    select
      (row_number() over (
        order by event.half, event.minute, event.created_at, event.id
      ) - 1)::integer as ordinal,
      least(greatest(event.minute, 0), 90)::smallint as minute,
      case when event.event_type = 'goal_them'
        then 'opponent' else 'as_grinta' end as team_side,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false) then null
        else event.scorer_participant_id
      end as scorer_participant_id,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false) then null
        when scorer_guest.id is not null then
          public.guest_display_label(scorer_guest.first_name)
        else public.person_display_name(scorer_profile.surnom, scorer_profile.first_name, scorer_player.first_name)
      end as scorer_name,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          or event.scorer_participant_id is null then null
        else event.assist_participant_id
      end as assist_participant_id,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false) then 'none'
        when event.scorer_participant_id is null then 'unknown'
        when event.assist_participant_id is not null then 'player'
        -- Le Live ne distingue pas « aucune passe » de « passe oubliée ».
        else 'unknown'
      end as assist_kind,
      case
        when event.event_type <> 'goal_us'
          or coalesce(event.is_opponent_own_goal, false)
          or event.scorer_participant_id is null then null
        when assist_guest.id is not null then
          public.guest_display_label(assist_guest.first_name)
        else public.person_display_name(assist_profile.surnom, assist_profile.first_name, assist_player.first_name)
      end as assist_name,
      event.event_type = 'goal_us'
        and coalesce(event.is_opponent_own_goal, false) as is_own_goal,
      event.id as source_live_event_id
    from public.match_live_events event
    left join public.match_sport_participants scorer_p
      on scorer_p.id = event.scorer_participant_id
     and scorer_p.match_id = event.match_id
    left join public.season_players scorer_player
      on scorer_player.id = scorer_p.season_player_id
    left join public.profiles scorer_profile
      on scorer_profile.id = scorer_player.profile_id
    left join public.guest_players scorer_guest
      on scorer_guest.id = scorer_p.guest_player_id
    left join public.match_sport_participants assist_p
      on assist_p.id = event.assist_participant_id
     and assist_p.match_id = event.match_id
    left join public.season_players assist_player
      on assist_player.id = assist_p.season_player_id
    left join public.profiles assist_profile
      on assist_profile.id = assist_player.profile_id
    left join public.guest_players assist_guest
      on assist_guest.id = assist_p.guest_player_id
    where event.match_id = p_match_id
      and event.event_type in ('goal_us', 'goal_them')
  ) projected;
$function$;


-- public.get_internal_composition : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260831010000_internal_match_jersey_pairing.sql.
create or replace function public.get_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_team1_name text;
  v_team2_name text;
  v_team1_jersey text;
  v_team2_jersey text;
  v_entries jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select match_type into v_match_type
  from public.matches
  where id = p_match_id;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;

  select
    comp.team1_name,
    comp.team2_name,
    comp.team1_jersey,
    comp.team2_jersey
  into
    v_team1_name,
    v_team2_name,
    v_team1_jersey,
    v_team2_jersey
  from public.match_internal_compositions comp
  where comp.match_id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'season_player_id', participant.season_player_id,
      'guest_player_id', participant.guest_player_id,
      'display_name', public.person_display_name(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name)),
      'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
      'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
      'is_guest', participant.guest_player_id is not null,
      'team_no', entry.team_no,
      'sort_order', coalesce(entry.sort_order, 999)
    )
    order by coalesce(entry.sort_order, 999),
      public.person_display_name(profile.surnom, profile.first_name, coalesce(nullif(btrim(player.first_name), ''), guest.first_name))
  ), '[]'::jsonb)
  into v_entries
  from public.match_sport_participants participant
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.match_internal_composition_entries entry
    on entry.match_id = p_match_id
   and entry.participant_id = participant.id
  where participant.match_id = p_match_id
    and participant.convocation_status = 'convoked';

  return jsonb_build_object(
    'match_id', p_match_id,
    'team1_name', coalesce(v_team1_name, 'Équipe 1'),
    'team2_name', coalesce(v_team2_name, 'Équipe 2'),
    'team1_jersey', coalesce(v_team1_jersey, 'orange'),
    'team2_jersey', coalesce(v_team2_jersey, 'blue'),
    'entries', v_entries
  );
end;
$function$;


-- private.get_match_convocations : appellation factorisée, corps inchangé par ailleurs.
-- Dernière définition connue : 20260903140000_effectif_photo_falls_back_to_season_player.sql.
create or replace function private.get_match_convocations(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
      and workflow.convocation_state = 'draft'
  ) then
    perform private.recompute_match_convocations_internal(p_match_id, false);
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', coalesce(opponent.name, 'Match entre nous'),
    'kickoff_at', match.kickoff_at,
    'season_id', match.season_id,
    'squad_size_limit', workflow.squad_size_limit,
    'published_squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'has_unpublished_changes', false,
    'late_withdrawal_cutoff_at', workflow.late_withdrawal_cutoff_at,
    'available_count', coalesce(players.available_count, 0),
    'convoked_count', coalesce(players.convoked_count, 0),
    'not_convoked_count', coalesce(players.not_convoked_count, 0),
    'players', coalesce(players.items, '[]'::jsonb)
  )
  into v_result
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join lateral (
    select
      count(*) filter (
        where row.is_eligible
          and (
            (row.season_player_id is not null and row.availability_status = 'available')
            or row.guest_player_id is not null
          )
      )::integer as available_count,
      count(*) filter (
        where row.is_eligible
          and row.convocation_status = 'convoked'
          and (
            row.availability_status = 'available'
            or row.guest_player_id is not null
          )
      )::integer as convoked_count,
      count(*) filter (
        where row.is_eligible
          and row.season_player_id is not null
          and row.availability_status = 'available'
          and row.convocation_status = 'not_convoked'
      )::integer as not_convoked_count,
      jsonb_agg(
        jsonb_build_object(
          'participant_id', row.participant_id,
          'season_player_id', row.season_player_id,
          'guest_player_id', row.guest_player_id,
          'first_name', row.first_name,
          'last_name', row.last_name,
          'display_name', row.display_name,
          'photo_url', row.photo_url,
          'is_guest', row.guest_player_id is not null,
          'is_goalkeeper', row.is_goalkeeper,
          'availability_status', row.availability_status,
          'availability_updated_at', row.availability_updated_at,
          'convocation_status', row.convocation_status,
          'published_convocation_status', row.convocation_status,
          'manual_override', row.convocation_manual_override,
          'waitlist_position', row.waitlist_position,
          'waitlist_position_snapshot', row.waitlist_position_snapshot,
          'current_season_waitlist_count', row.current_season_waitlist_count,
          'recommended_not_convoked', row.waitlist_recommended_not_convoked,
          'turn_should_consume', row.waitlist_turn_should_consume,
          'turn_state', row.waitlist_turn_state,
          'promoted_after_withdrawal_at', row.promoted_after_withdrawal_at
        )
        order by row.availability_order, row.waitlist_position,
          lower(row.first_name), lower(coalesce(row.last_name, ''))
      ) filter (where row.participant_id is not null and row.is_eligible) as items
    from (
      select
        participant.id as participant_id,
        participant.season_player_id,
        participant.guest_player_id,
        participant.is_eligible,
        coalesce(player.first_name, guest.first_name) as first_name,
        coalesce(player.last_name, guest.last_name) as last_name,
        case
          when guest.id is not null then public.guest_display_label(guest.first_name)
          else public.person_display_name(profile.surnom, profile.first_name, player.first_name)
        end as display_name,
        coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
        coalesce(player.is_goalkeeper, guest.is_goalkeeper, false) as is_goalkeeper,
        participant.availability_status,
        participant.availability_updated_at,
        participant.convocation_status,
        participant.convocation_manual_override,
        waitlist.position as waitlist_position,
        participant.waitlist_position_snapshot,
        coalesce(waitlist.manual_waitlist_count, 0) as current_season_waitlist_count,
        participant.waitlist_recommended_not_convoked,
        participant.waitlist_turn_should_consume,
        participant.waitlist_turn_state,
        participant.promoted_after_withdrawal_at,
        case
          when participant.guest_player_id is not null then 0
          when participant.availability_status = 'available' then 0
          when participant.availability_status = 'no_response' then 1
          when participant.availability_status = 'absent' then 2
          else 3
        end as availability_order
      from public.match_sport_participants participant
      left join public.season_players player
        on player.id = participant.season_player_id
      left join public.profiles profile on profile.id = player.profile_id
      left join public.guest_players guest
        on guest.id = participant.guest_player_id
      left join public.sport_waitlist_entries waitlist
        on waitlist.season_player_id = participant.season_player_id
       and waitlist.season_id = match.season_id
      where participant.match_id = match.id
    ) row
  ) players on true
  where match.id = p_match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;
