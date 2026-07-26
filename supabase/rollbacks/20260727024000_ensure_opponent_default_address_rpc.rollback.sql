begin;

drop function if exists public.admin_set_match_address(uuid, text, boolean);

create function public.admin_set_match_address(
  p_match_id uuid,
  p_address text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_opponent_id uuid;
  v_location text;
  v_address text := nullif(btrim(p_address), '');
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'Address cannot exceed 300 characters' using errcode = '22023';
  end if;

  update public.matches
  set address = v_address
  where id = p_match_id
  returning opponent_id, location into v_opponent_id, v_location;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_address is null then
    return;
  end if;

  if v_location = 'domicile' then
    update public.club_settings set home_address = v_address where id;
  elsif v_opponent_id is not null then
    update public.opponents set address = v_address where id = v_opponent_id;
  end if;
end;
$function$;

revoke all on function public.admin_set_match_address(uuid, text)
  from public, anon;
grant execute on function public.admin_set_match_address(uuid, text)
  to authenticated, service_role;

commit;
