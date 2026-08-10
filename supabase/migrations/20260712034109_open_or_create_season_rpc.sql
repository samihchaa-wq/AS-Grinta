-- Ouvre (ou ré-ouvre) une saison par son nom et garantit qu'une seule saison
-- est ouverte à la fois. Réservé au staff.
create or replace function public.open_or_create_season(p_name text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name text := btrim(p_name);
  v_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;
  if v_name !~ '^\d{4}-\d{4}$' then
    raise exception 'Le nom doit respecter le format 2026-2027';
  end if;
  if substring(v_name from 6 for 4)::int <> substring(v_name from 1 for 4)::int + 1 then
    raise exception 'La saison doit couvrir deux années consécutives';
  end if;

  -- Une seule saison ouverte à la fois.
  update public.seasons set status = 'archived' where status = 'open';

  select id into v_id from public.seasons where name = v_name;
  if v_id is null then
    insert into public.seasons(name, status) values (v_name, 'open')
    returning id into v_id;
  else
    update public.seasons
      set status = 'open', season_predictions_locked_at = null
      where id = v_id;
  end if;
  return v_id;
end;
$$;

revoke execute on function public.open_or_create_season(text) from public, anon;
grant execute on function public.open_or_create_season(text) to authenticated;;
