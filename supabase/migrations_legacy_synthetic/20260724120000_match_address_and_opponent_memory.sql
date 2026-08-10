-- Adresse du lieu de match. Stockée sur le match ; mémorisée sur l'adversaire
-- pour préremplir les prochaines rencontres contre la même équipe.
alter table public.matches add column if not exists address text;
alter table public.opponents add column if not exists address text;

grant select (address) on public.matches to authenticated;
grant select (address) on public.opponents to authenticated;

create or replace function public.admin_set_match_address(
  p_match_id uuid,
  p_address text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_address text := nullif(btrim(p_address), '');
  v_opponent uuid;
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
  returning opponent_id into v_opponent;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_address is not null and v_opponent is not null then
    update public.opponents set address = v_address where id = v_opponent;
  end if;
end;
$function$;

grant execute on function public.admin_set_match_address(uuid, text) to authenticated;
