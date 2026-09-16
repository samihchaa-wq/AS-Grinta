-- La photo d'un invité n'arrivait pas jusqu'à la liste des invités du match.
--
-- Le catalogue des invités (private.get_guest_players) renvoie déjà
-- « photo_url » : la pastille y affiche donc la photo. La liste des invités
-- ajoutés à un match, elle, ne recevait jamais cette clé, et le même invité
-- restait sur une icône générique juste au-dessus de sa propre photo.
--
-- La fonction est recréée à l'identique de la production, à cette seule clé
-- près. La cascade est la même que partout ailleurs : ici seul l'invité porte
-- une photo, il n'y a ni profil ni ligne d'effectif derrière lui.

create or replace function private.get_match_guests(p_match_id uuid)
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

  if not exists (
    select 1 from public.match_sport_workflows workflow
    where workflow.match_id = p_match_id
  ) then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'match_id', p_match_id,
    'guests', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'guest_player_id', guest.id,
        'first_name', guest.first_name,
        'last_name', guest.last_name,
        'display_name',
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)',
        'photo_url', guest.photo_url,
        'is_goalkeeper', guest.is_goalkeeper,
        'is_reusable', guest.is_reusable,
        'archived_at', guest.archived_at,
        'selection_status', participant.selection_status,
        'created_at', participant.created_at
      )
      order by lower(guest.first_name), lower(coalesce(guest.last_name, ''))
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.match_sport_participants participant
  join public.guest_players guest on guest.id = participant.guest_player_id
  where participant.match_id = p_match_id
    and participant.is_eligible;

  return v_result;
end;
$function$;
