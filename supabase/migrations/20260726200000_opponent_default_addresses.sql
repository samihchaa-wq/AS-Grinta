begin;

drop function if exists public.admin_set_match_address(uuid, text);

create function public.admin_set_match_address(
  p_match_id uuid,
  p_address text,
  p_remember_as_default boolean default false
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_address text := nullif(btrim(p_address), '');
  v_opponent uuid;
  v_location text;
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
  returning opponent_id, location into v_opponent, v_location;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if coalesce(p_remember_as_default, false) and v_address is not null then
    if v_location = 'domicile' then
      update public.club_settings set home_address = v_address where id;
    elsif v_opponent is not null then
      update public.opponents set address = v_address where id = v_opponent;
    end if;
  end if;
end;
$function$;

revoke all on function public.admin_set_match_address(uuid, text, boolean)
from public, anon;
grant execute on function public.admin_set_match_address(uuid, text, boolean)
to authenticated;

update public.opponents
set address = case lower(btrim(name))
  when 'toac foot loisir 1' then '20 Chemin de Garric, 31200 Toulouse, France'
  when 'toac foot loisir 2' then '20 Chemin de Garric, 31200 Toulouse, France'
  when 'as hersoise' then '8 bis Rue Claudius Rougenet, 31500 Toulouse, France'
  when 'amical olympique cornebarrieu' then 'Rte du Stade, 31700 Cornebarrieu, France'
  when 'positive vibration' then 'Boulevard Als Cambiots, 31130 Balma, France'
  when 'rouffiac tolosan fc' then 'Chemin des Garrosses, 31180 Rouffiac-Tolosan, France'
  else address
end
where lower(btrim(name)) in (
  'toac foot loisir 1',
  'toac foot loisir 2',
  'as hersoise',
  'amical olympique cornebarrieu',
  'positive vibration',
  'rouffiac tolosan fc'
);

commit;
