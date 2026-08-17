-- P3-06: update an internal match and its address in one server transaction.
-- Keep the four-argument overload temporarily for cached PWA compatibility.

create or replace function public.update_internal_match(
  p_match_id uuid,
  p_season_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_address text
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_address text := nullif(btrim(p_address), '');
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null or p_season_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, date et heure requis.' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode = '22023';
  end if;
  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'Address cannot exceed 300 characters' using errcode = '22023';
  end if;

  select m.status
  into v_status
  from public.matches m
  where m.id = p_match_id
    and m.match_type = 'entre_nous'
  for update;

  if v_status is null then
    raise exception 'Match entre nous introuvable.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.seasons s where s.id = p_season_id) then
    raise exception 'Saison introuvable.' using errcode = 'P0002';
  end if;

  update public.matches
  set season_id = p_season_id,
      match_date = p_match_date,
      match_time = p_match_time,
      address = v_address,
      updated_at = now()
  where id = p_match_id;

  if v_status = 'a_venir' then
    perform private.configure_match_sport_workflow(p_match_id, 30);
  end if;

  return true;
end;
$function$;

revoke all on function public.update_internal_match(uuid, uuid, date, time without time zone, text) from public;
revoke all on function public.update_internal_match(uuid, uuid, date, time without time zone, text) from anon;
grant execute on function public.update_internal_match(uuid, uuid, date, time without time zone, text) to authenticated;
grant execute on function public.update_internal_match(uuid, uuid, date, time without time zone, text) to service_role;
