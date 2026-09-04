-- Initiale du nom de famille dans les compositions
--
-- Sans photo de profil, l'application affiche des initiales. Elle ne recevait
-- que le nom d'affichage (prénom ou surnom) : deux joueurs prénommés Julien
-- avaient donc exactement la même pastille. Les fonctions de composition
-- ajoutent « last_initial », l'initiale du nom de famille en majuscule, à côté
-- de « display_name ». On n'expose qu'une lettre : c'est tout ce dont
-- l'affichage a besoin, et le nom complet n'a pas à circuler.
--
-- L'effectif (private.get_match_convocations) envoie déjà « last_name » et
-- n'est pas modifié ici.
--
-- Chaque fonction est recréée à l'identique de la production, à cette seule
-- clé près.

-- Composition en préparation (écran Compo et Live).
CREATE OR REPLACE FUNCTION private.composition_snapshot(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
              btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
            else coalesce(
              nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
              nullif(btrim(player.first_name), ''),
              btrim(concat_ws(' ', player.first_name, player.last_name))
            )
          end,
          'last_initial', nullif(upper(left(coalesce(
            nullif(btrim(guest.last_name), ''),
            nullif(btrim(player.last_name), ''),
            nullif(btrim(profile.last_name), ''),
            ''
          ), 1)), ''),
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
          lower(coalesce(profile.surnom, profile.first_name, player.first_name, guest.first_name)),
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
$function$;

-- Composition publiée, vue par tout le monde.
CREATE OR REPLACE FUNCTION private.get_published_match_composition(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      coalesce(
        nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
      nullif(upper(left(coalesce(
        nullif(btrim(guest.last_name), ''),
        nullif(btrim(player.last_name), ''),
        nullif(btrim(profile.last_name), ''),
        ''
      ), 1)), '') as last_initial,
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
        'display_name', coalesce(v_participant.display_name, v_entry ->> 'display_name'),
        'last_initial', coalesce(v_participant.last_initial, v_entry ->> 'last_initial')
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
      coalesce(
        nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
      nullif(upper(left(coalesce(
        nullif(btrim(guest.last_name), ''),
        nullif(btrim(player.last_name), ''),
        nullif(btrim(profile.last_name), ''),
        ''
      ), 1)), '') as last_initial,
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
      'last_initial', v_participant.last_initial,
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
$function$;

-- Composition du compte rendu et des matchs déjà joués.
CREATE OR REPLACE FUNCTION private.match_sport_report_lineup(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      profile.last_name as profile_last_name,
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
              btrim(concat_ws(' ', resolved.guest_first_name, resolved.guest_last_name))
                || ' (Invité)'
            else coalesce(
              nullif(btrim(resolved.profile_surnom), ''),
              nullif(btrim(resolved.profile_first_name), ''),
              nullif(btrim(resolved.player_first_name), ''),
              btrim(concat_ws(' ', resolved.player_first_name, resolved.player_last_name))
            )
          end,
          'last_initial', nullif(upper(left(coalesce(
            nullif(btrim(resolved.guest_last_name), ''),
            nullif(btrim(resolved.player_last_name), ''),
            nullif(btrim(resolved.profile_last_name), ''),
            ''
          ), 1)), ''),
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
          lower(coalesce(
            resolved.profile_surnom, resolved.profile_first_name,
            resolved.player_first_name, resolved.guest_first_name
          )),
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

-- Match entre nous.
CREATE OR REPLACE FUNCTION public.get_internal_composition(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ),
      'last_initial', nullif(upper(left(coalesce(
        nullif(btrim(guest.last_name), ''),
        nullif(btrim(player.last_name), ''),
        nullif(btrim(profile.last_name), ''),
        ''
      ), 1)), ''),
      'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
      'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
      'is_guest', participant.guest_player_id is not null,
      'team_no', entry.team_no,
      'sort_order', coalesce(entry.sort_order, 999)
    )
    order by coalesce(entry.sort_order, 999),
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      )
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

-- Joueurs proposés à l'ajout pendant le Live.
CREATE OR REPLACE FUNCTION private.get_match_live_add_player_options(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      'last_initial', candidate.last_initial,
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
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        btrim(concat_ws(' ', player.first_name, player.last_name)),
        'Joueur'
      ) as display_name,
      nullif(upper(left(coalesce(
        nullif(btrim(player.last_name), ''),
        nullif(btrim(profile.last_name), ''),
        ''
      ), 1)), '') as last_initial,
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
      'last_initial', candidate.last_initial,
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
      btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)' as display_name,
      nullif(upper(left(coalesce(nullif(btrim(guest.last_name), ''), ''), 1)), '') as last_initial,
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
$function$;

-- Compte rendu en préparation et composition d'après-match.
CREATE OR REPLACE FUNCTION private.match_sport_finalization_snapshot(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
            nullif(btrim(player.first_name), ''),
            btrim(concat_ws(' ', player.first_name, player.last_name))
          )
        end,
        'last_initial', nullif(upper(left(coalesce(
          nullif(btrim(guest.last_name), ''),
          nullif(btrim(player.last_name), ''),
          nullif(btrim(profile.last_name), ''),
          ''
        ), 1)), ''),
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
        lower(coalesce(profile.surnom, profile.first_name, player.first_name, guest.first_name)),
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
