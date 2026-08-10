-- « Faits du match » : les mêmes noms courts que partout ailleurs.
--
-- La frise des faits de jeu composait ses noms à part, en collant prénom et
-- nom de la fiche d'effectif : elle affichait « François De La Bourdonnaye »
-- là où tout le reste de l'application dit « François », et ignorait aussi
-- bien le surnom que le prénom choisi sur le compte du joueur.
--
-- Elle reprend désormais exactement l'expression du Tableau Blanc
-- (match_live_snapshot) : surnom du compte, puis prénom du compte, puis
-- prénom de la fiche ; et « Prénom (Invité) » pour un invité.
--
-- La fonction est courte et entièrement reprise ici, contrairement aux
-- corrections ciblées des fonctions longues : il n'y a pas de corps volumineux
-- à préserver, et la réécrire rend la règle lisible d'un coup d'œil.

create or replace function private.get_match_live_timeline(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
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
          btrim(scorer_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(scorer_profile.surnom), ''),
          nullif(btrim(scorer_profile.first_name), ''),
          nullif(btrim(scorer_player.first_name), '')
        )
      end,
      'score_as_grinta_after', event.score_as_grinta_after,
      'score_adverse_after', event.score_adverse_after,
      'player_in_name', case
        when in_guest.id is not null then
          btrim(in_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(in_profile.surnom), ''),
          nullif(btrim(in_profile.first_name), ''),
          nullif(btrim(in_player.first_name), '')
        )
      end,
      'player_out_name', case
        when out_guest.id is not null then
          btrim(out_guest.first_name) || ' (Invité)'
        else coalesce(
          nullif(btrim(out_profile.surnom), ''),
          nullif(btrim(out_profile.first_name), ''),
          nullif(btrim(out_player.first_name), '')
        )
      end
    ) order by event.half, event.minute, event.created_at
  ), '[]'::jsonb)
  into v_events
  from public.match_live_events event
  left join public.match_sport_participants scorer_p on scorer_p.id = event.scorer_participant_id
  left join public.season_players scorer_player on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest on scorer_guest.id = scorer_p.guest_player_id
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
