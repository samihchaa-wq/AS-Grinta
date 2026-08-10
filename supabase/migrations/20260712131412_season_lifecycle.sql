alter table public.seasons drop constraint if exists seasons_status_check;
alter table public.seasons
  add constraint seasons_status_check
  check (status = any (array['open'::text, 'terminee'::text, 'archived'::text]));

create or replace function public.set_season_status(
  p_season_id uuid,
  p_status text
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;
  if p_status not in ('open', 'terminee', 'archived') then
    raise exception 'Statut de saison invalide';
  end if;

  if p_status = 'open' then
    update public.seasons
      set status = 'archived'
      where status = 'open' and id <> p_season_id;
  end if;

  update public.seasons set status = p_status where id = p_season_id;
  return true;
end;
$$;

revoke execute on function public.set_season_status(uuid, text) from public, anon;
grant execute on function public.set_season_status(uuid, text) to authenticated;;
