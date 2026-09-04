-- Les groupes « Défenseurs / Milieux / Attaquants » d'un match entre nous sont
-- déduits de l'historique des compositions, qui est rangé par identité
-- canonique du joueur (public.players). L'application devait jusqu'ici
-- retrouver cette identité elle-même, en repassant par season_players — donc
-- uniquement pour les joueurs de l'effectif. Un invité, même quand c'est un
-- joueur du club qui n'est pas inscrit cette saison, n'avait aucune identité
-- exploitable et retombait dans « Autre ».
--
-- On expose l'identité canonique directement dans la composition, pour
-- l'effectif comme pour les invités. C'est la même cascade que le reste de la
-- réponse : le joueur de l'effectif d'abord, l'invité ensuite.

create or replace function public.get_internal_composition(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
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
      'player_id', coalesce(player.player_id, guest.player_id),
      'display_name', coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        nullif(btrim(guest.first_name), '')
      ),
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

revoke all on function public.get_internal_composition(uuid)
  from public, anon;
grant execute on function public.get_internal_composition(uuid)
  to authenticated, service_role;

comment on function public.get_internal_composition(uuid) is
  'Returns the internal-team composition to any active authenticated profile.';
