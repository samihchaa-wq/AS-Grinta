-- Suite : un présent réel dont la compo publiée le classait « non retenu » ou
-- « à placer » (ex. ajouté après la publication) doit apparaître en remplaçant
-- sur la feuille d'un match terminé, pas seulement s'il est totalement absent
-- du snapshot.

create or replace function private.get_published_match_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
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
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
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
        if v_participant.season_player_id is not null
           and v_participant.availability_status <> 'available' then
          v_entry := v_entry || jsonb_build_object(
            'zone', 'not_selected', 'x', null, 'y', null,
            'selection_status', 'not_selected'
          );
        elsif v_participant.convocation_status <> 'convoked'
              and (v_entry ->> 'zone') in ('field', 'bench', 'available') then
          v_entry := v_entry || jsonb_build_object(
            'zone', 'not_selected', 'x', null, 'y', null,
            'selection_status', 'not_selected'
          );
        end if;
      elsif v_participant.final_presence_status = 'present'
            and (v_entry ->> 'zone') in ('available', 'not_selected') then
        -- Match joué : un présent réel non prévu devient remplaçant.
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

  -- Présents réels totalement absents du snapshot : ajoutés en remplaçants.
  for v_participant in
    select
      participant.id,
      participant.season_player_id,
      participant.guest_player_id,
      coalesce(participant.final_goals, 0) as goals,
      coalesce(profile.photo_url, player.photo_url, guest.photo_url) as photo_url,
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ) as display_name,
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
$function$;
