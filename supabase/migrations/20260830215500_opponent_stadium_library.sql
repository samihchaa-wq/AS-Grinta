alter table public.opponents
  add column if not exists stadium_name text;

alter table public.opponents
  drop constraint if exists opponents_stadium_name_length_check;

alter table public.opponents
  add constraint opponents_stadium_name_length_check
  check (
    stadium_name is null
    or (
      char_length(btrim(stadium_name)) between 1 and 120
      and stadium_name = btrim(stadium_name)
    )
  );

comment on column public.opponents.stadium_name is
  'Nom du stade/terrain actuellement utilisé par cet adversaire. Les matchs conservent leur propre snapshot d’adresse.';

-- Les adresses historiques importées utilisent souvent le format
-- "Nom du stade - rue - CP - ville". On récupère uniquement ce libellé
-- lorsqu’il est explicite ; les adresses simples restent sans nom de stade.
update public.opponents
set stadium_name = btrim(split_part(address, ' - ', 1))
where stadium_name is null
  and address is not null
  and position(' - ' in address) > 0
  and nullif(btrim(split_part(address, ' - ', 1)), '') is not null;

create or replace function public.admin_save_opponent_stadium(
  p_opponent_id uuid,
  p_name text,
  p_stadium_name text default null,
  p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_stadium_name text := nullif(btrim(p_stadium_name), '');
  v_address text := nullif(btrim(p_address), '');
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'Opponent name must contain between 2 and 120 characters'
      using errcode = '22023';
  end if;

  if v_stadium_name is not null and char_length(v_stadium_name) > 120 then
    raise exception 'Stadium name cannot exceed 120 characters'
      using errcode = '22023';
  end if;

  if v_address is not null and char_length(v_address) > 300 then
    raise exception 'Address cannot exceed 300 characters'
      using errcode = '22023';
  end if;

  if p_opponent_id is null then
    insert into public.opponents(name, stadium_name, address)
    values (v_name, v_stadium_name, v_address)
    returning id into v_id;
  else
    update public.opponents
    set name = v_name,
        stadium_name = v_stadium_name,
        address = v_address
    where id = p_opponent_id
    returning id into v_id;

    if not found then
      raise exception 'Opponent not found' using errcode = 'P0002';
    end if;
  end if;

  return v_id;
end;
$function$;

create or replace function public.admin_delete_unused_opponent(
  p_opponent_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.matches where opponent_id = p_opponent_id
    union all
    select 1 from public.historical_match_scores where opponent_id = p_opponent_id
  ) then
    raise exception 'Opponent is used by match history and cannot be deleted'
      using errcode = '23503';
  end if;

  delete from public.opponents where id = p_opponent_id;
  return found;
end;
$function$;

revoke all on function public.admin_save_opponent_stadium(uuid, text, text, text) from public;
revoke all on function public.admin_save_opponent_stadium(uuid, text, text, text) from anon;
grant execute on function public.admin_save_opponent_stadium(uuid, text, text, text) to authenticated;

revoke all on function public.admin_delete_unused_opponent(uuid) from public;
revoke all on function public.admin_delete_unused_opponent(uuid) from anon;
grant execute on function public.admin_delete_unused_opponent(uuid) to authenticated;
