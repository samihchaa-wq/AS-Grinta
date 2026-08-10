-- Historique des placements réels, pour que les postes de référence des
-- joueurs suivent leur évolution au fil de la saison.
--
-- La simulation de composition part d'un socle figé dans l'application,
-- dérivé des compositions archivées du club jusqu'au 21 mai 2026. Cette
-- fonction lui apporte la suite : chaque titularisation enregistrée depuis,
-- avec sa position sur le terrain et sa date, pour que le poids des saisons
-- récentes fasse glisser le profil d'un joueur qui change de poste.
--
-- Le client passe la date de départ (`p_since`) afin que le raccord avec
-- l'archive reste défini à un seul endroit, côté application.
create or replace function private.get_player_position_history(
  p_since timestamptz
)
returns jsonb
language plpgsql
stable
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'player_id', identity.player_id,
        'x', entry.x,
        'y', entry.y,
        'kickoff_at', match.kickoff_at
      )
    ),
    '[]'::jsonb
  )
  into v_result
  from public.match_composition_entries entry
  join public.matches match on match.id = entry.match_id
  join public.match_sport_participants participant
    on participant.id = entry.participant_id
  left join public.season_players season_player
    on season_player.id = participant.season_player_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  cross join lateral (
    select coalesce(season_player.player_id, guest.player_id) as player_id
  ) identity
  where match.status in ('termine', 'archive')
    and match.kickoff_at >= p_since
    and entry.zone = 'field'::public.sport_composition_zone
    and entry.x is not null
    and entry.y is not null
    and identity.player_id is not null;

  return v_result;
end;
$function$;

create or replace function public.admin_get_player_position_history(
  p_since timestamptz
)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_player_position_history(p_since); $function$;

revoke execute on function private.get_player_position_history(timestamptz)
  from public, anon;
revoke execute on function public.admin_get_player_position_history(timestamptz)
  from public, anon;

grant execute on function private.get_player_position_history(timestamptz)
  to authenticated, service_role;
grant execute on function public.admin_get_player_position_history(timestamptz)
  to authenticated, service_role;

comment on function public.admin_get_player_position_history(timestamptz) is
  'Placements des titulaires sur les matchs terminés depuis p_since. Alimente '
  'les postes de référence de la simulation de composition. Réservé aux '
  'administrateurs.';
