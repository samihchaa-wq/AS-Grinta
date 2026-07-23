-- Uniformisation des noms : le terrain de composition tronquait le nom au
-- premier mot côté client, ce qui mutilait un surnom en plusieurs mots
-- (« El Fenomeno » → « El ») et ne désambiguïsait pas deux mêmes prénoms.
--
-- On résout désormais le nom court côté serveur, comme partout ailleurs dans
-- l'app (statistiques, profil, listes admin) :
--   surnom s'il est renseigné, sinon prénom seul (repli sur prénom + nom).
-- Le client se contente d'afficher cette valeur telle quelle, sans la couper.

create or replace function private.composition_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
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
              nullif(btrim(profile.surnom), ''),
              nullif(btrim(player.first_name), ''),
              btrim(concat_ws(' ', player.first_name, player.last_name))
            )
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
          lower(coalesce(profile.surnom, player.first_name, guest.first_name)),
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
