-- L'adresse d'un match est celle de l'équipe à domicile :
--   - match à l'extérieur → terrain de l'adversaire (mémorisé sur l'adversaire)
--   - match à domicile     → terrain d'AS Grinta (mémorisé globalement)
create table if not exists public.club_settings (
  id boolean primary key default true,
  home_address text,
  constraint club_settings_singleton check (id)
);
insert into public.club_settings (id) values (true) on conflict do nothing;

alter table public.club_settings enable row level security;
grant select on public.club_settings to authenticated;
drop policy if exists club_settings_read on public.club_settings;
create policy club_settings_read on public.club_settings
  for select to authenticated using (true);

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

  if v_address is not null then
    if v_location = 'domicile' then
      update public.club_settings set home_address = v_address where id;
    elsif v_opponent is not null then
      update public.opponents set address = v_address where id = v_opponent;
    end if;
  end if;
end;
$function$;

grant execute on function public.admin_set_match_address(uuid, text) to authenticated;
