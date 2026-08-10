-- Photos des invités : expose photo_url dans le catalogue et permet à
-- l'admin de la définir (les écritures sur guest_players passent par une
-- fonction security definer).

create or replace function private.get_guest_players(
  p_include_archived boolean default false
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

  select jsonb_build_object(
    'guests', coalesce(jsonb_agg(
      jsonb_build_object(
        'guest_player_id', guest.id,
        'first_name', guest.first_name,
        'last_name', guest.last_name,
        'display_name',
          btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)',
        'photo_url', guest.photo_url,
        'is_goalkeeper', guest.is_goalkeeper,
        'is_reusable', guest.is_reusable,
        'archived_at', guest.archived_at,
        'created_at', guest.created_at,
        'updated_at', guest.updated_at
      )
      order by
        guest.is_reusable desc,
        lower(guest.first_name),
        lower(coalesce(guest.last_name, '')),
        guest.created_at
    ), '[]'::jsonb)
  )
  into v_result
  from public.guest_players guest
  where p_include_archived or guest.is_reusable;

  return v_result;
end;
$function$;

create or replace function public.admin_set_guest_photo(
  p_guest_player_id uuid,
  p_photo_url text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  update public.guest_players
  set photo_url = nullif(btrim(p_photo_url), ''),
      updated_by = (select auth.uid()),
      updated_at = now()
  where id = p_guest_player_id;

  if not found then
    raise exception 'Guest not found' using errcode = 'P0002';
  end if;
end;
$function$;

revoke execute on function public.admin_set_guest_photo(uuid, text) from public, anon;
grant execute on function public.admin_set_guest_photo(uuid, text) to authenticated, service_role;
