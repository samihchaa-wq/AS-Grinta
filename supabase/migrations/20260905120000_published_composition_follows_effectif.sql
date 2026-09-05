-- La composition publiée suit l'effectif, sans nouvelle publication
--
-- Problème : l'effectif d'un match bouge jusqu'au coup d'envoi, mais la feuille
-- que voient les joueurs, elle, restait figée sur la dernière publication.
-- Un joueur qui se désistait libérait bien sa place. En revanche celui qui
-- entrait dans l'effectif après coup — remplaçant promu automatiquement depuis
-- la liste d'attente, invité ajouté, joueur redevenu disponible — n'apparaissait
-- nulle part. La feuille affichée était donc incomplète, sans que personne ne
-- puisse s'en apercevoir.
--
-- Désormais, avant le coup d'envoi :
--   * un joueur qui n'est plus convoqué laisse son emplacement vide, et
--     personne ne prend sa place automatiquement (règle inchangée) ;
--   * un joueur convoqué après la publication apparaît sur le banc, qu'il soit
--     absent de la feuille ou qu'il y figure hors effectif.
--
-- Un joueur que l'administrateur avait délibérément laissé hors feuille tout en
-- le convoquant n'est pas touché : la convocation enregistrée dans le snapshot
-- au moment de la publication permet de distinguer les deux situations.
--
-- Après le coup d'envoi, rien ne change : la présence réellement constatée reste
-- la seule règle.

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
  v_snapshot_convocation text;
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
      -- Convocation telle qu'elle était au moment de la publication : elle
      -- distingue un joueur volontairement laissé hors feuille d'un joueur
      -- convoqué après coup.
      v_snapshot_convocation := coalesce(
        v_entry ->> 'convocation_status', 'convoked'
      );
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
          -- Le joueur qui quitte l'effectif libère sa place : elle reste vide,
          -- personne n'est déplacé pour la combler.
          v_entry := v_entry || jsonb_build_object(
            'zone', 'not_selected', 'x', null, 'y', null,
            'selection_status', 'not_selected'
          );
        elsif v_participant.convocation_status = 'convoked'
              and v_snapshot_convocation <> 'convoked'
              and (v_entry ->> 'zone') in ('not_selected', 'available') then
          -- Le joueur entré dans l'effectif après la feuille apparaît sur le
          -- banc. Un convoqué que l'admin avait déjà écarté de la feuille, lui,
          -- y reste : sa convocation n'a pas changé depuis la publication.
          v_entry := v_entry || jsonb_build_object(
            'zone', 'bench', 'x', null, 'y', null,
            'selection_status', 'substitute'
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
      participant.availability_status::text as availability_status,
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
      and case
        when v_before_kickoff then
          participant.is_eligible
          and participant.convocation_status = 'convoked'
        else participant.final_presence_status = 'present'
      end
      and not exists (
        select 1 from jsonb_array_elements(v_entries)
        where (value ->> 'participant_id')::uuid = participant.id
      )
    order by participant.id
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
      'availability_status', case
        when v_before_kickoff then v_participant.availability_status
        else 'available'
      end,
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

