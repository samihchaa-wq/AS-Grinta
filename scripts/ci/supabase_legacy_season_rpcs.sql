-- CI-only compatibility shim before 20260713193000_harden_rpc_execute_permissions.sql.
-- These staff season RPCs existed in the hosted historical schema but are not
-- created by the tracked chain until a later hardening migration. Recreate the
-- later secure contracts only in the disposable runner so the permission
-- migration can validate the intended grants without weakening authorization.

create or replace function public.open_or_create_season(p_name text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  season_name text := btrim(coalesce(p_name, ''));
  start_year integer;
  end_year integer;
  season_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if season_name !~ '^\d{4}-\d{4}$' then
    raise exception 'Le nom doit respecter le format 2026-2027' using errcode = '22023';
  end if;
  start_year := substring(season_name from 1 for 4)::integer;
  end_year := substring(season_name from 6 for 4)::integer;
  if end_year <> start_year + 1 or start_year < 2000 or start_year > 2100 then
    raise exception 'Saison invalide' using errcode = '22023';
  end if;
  select s.id into season_id from public.seasons s where s.name = season_name for update;
  update public.seasons set status = 'archived'
  where status = 'open' and (season_id is null or id <> season_id);
  if season_id is null then
    insert into public.seasons(name, status) values (season_name, 'open') returning id into season_id;
  else
    update public.seasons set status = 'open', season_predictions_locked_at = null where id = season_id;
  end if;
  return season_id;
end;
$$;

create or replace function public.set_season_status(p_season_id uuid, p_status text)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_status is null
     or p_status not in ('open', 'terminee', 'archived') then
    raise exception 'Statut de saison invalide' using errcode = '22023';
  end if;
  perform 1 from public.seasons where id = p_season_id for update;
  if not found then raise exception 'Season not found' using errcode = 'P0002'; end if;
  if p_status = 'open' then
    update public.seasons set status = 'archived' where status = 'open' and id <> p_season_id;
  end if;
  update public.seasons set status = p_status where id = p_season_id;
  return true;
end;
$$;

create or replace function public.set_season_predictions_lock(p_season_id uuid, p_locked boolean)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_locked is null then
    raise exception 'Season id and lock value are required' using errcode = '22023';
  end if;
  update public.seasons
  set season_predictions_locked_at = case when p_locked then now() else null end
  where id = p_season_id and status = 'open';
  if not found then raise exception 'Open season not found' using errcode = 'P0002'; end if;
  return true;
end;
$$;
