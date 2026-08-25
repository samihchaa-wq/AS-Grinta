-- Make Supabase the single authority for persisted match odds.
-- Legacy odds parameters are kept in write RPC signatures for backward compatibility,
-- but they no longer influence public.match_odds.

create or replace function public.create_match_with_odds(
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  new_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_season_id is null or p_opponent_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Season, opponent, date and time are required' using errcode = '22023';
  end if;
  if p_location is null or p_location not in ('domicile', 'exterieur') then
    raise exception 'Invalid location' using errcode = '22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Match date is outside allowed bounds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.seasons s
    where s.id = p_season_id and s.status = 'open'
  ) then
    raise exception 'Open season not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.matches(
    season_id, opponent_id, match_date, match_time, location,
    planned_duration_minutes, status, created_by
  ) values (
    p_season_id, p_opponent_id, p_match_date, p_match_time, p_location,
    90, 'a_venir', (select auth.uid())
  ) returning id into new_id;

  -- trg_auto_match_odds_v4 persists the canonical server calculation.
  return new_id;
end;
$function$;

create or replace function public.update_match_with_odds(
  p_match_id uuid,
  p_season_id uuid,
  p_opponent_id uuid,
  p_match_date date,
  p_match_time time without time zone,
  p_location text,
  p_status text,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
  v_old_match_date date;
  v_old_match_time time without time zone;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode='42501';
  end if;
  if p_match_id is null or p_season_id is null or p_opponent_id is null or p_match_date is null or p_match_time is null then
    raise exception 'Match, saison, adversaire, date et heure requis.' using errcode='22023';
  end if;
  if p_location not in ('domicile','exterieur') then
    raise exception 'Lieu invalide.' using errcode='22023';
  end if;
  if p_status is distinct from 'a_venir' then
    raise exception 'Le statut se modifie via le workflow dédié du match.' using errcode='22023';
  end if;
  if p_match_date < date '2000-01-01' or p_match_date > date '2100-12-31' then
    raise exception 'Date de match hors limites.' using errcode='22023';
  end if;
  if not exists(select 1 from public.seasons s where s.id=p_season_id) then
    raise exception 'Saison introuvable.' using errcode='P0002';
  end if;
  if not exists(select 1 from public.opponents o where o.id=p_opponent_id) then
    raise exception 'Adversaire introuvable.' using errcode='P0002';
  end if;

  select match.id, match.match_date, match.match_time
  into v_match_id, v_old_match_date, v_old_match_time
  from public.matches match
  where match.id=p_match_id
  for update;
  if v_match_id is null then
    raise exception 'Match introuvable.' using errcode='P0002';
  end if;

  update public.matches
  set season_id=p_season_id,
      opponent_id=p_opponent_id,
      match_date=p_match_date,
      match_time=p_match_time,
      location=p_location,
      status='a_venir',
      predictions_closed_at=case
        when v_old_match_date is distinct from p_match_date
          or v_old_match_time is distinct from p_match_time
        then null
        else predictions_closed_at
      end,
      updated_at=now()
  where id=p_match_id;

  -- trg_auto_match_odds_v4 persists the canonical server calculation.
  return true;
end;
$function$;

create or replace function public.set_match_odds(
  p_match_id uuid,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.status = 'a_venir'
  ) then
    raise exception 'Upcoming match not found' using errcode = 'P0002';
  end if;

  -- Kept only as a compatibility RPC: caller-provided odds are intentionally ignored.
  perform public.upsert_match_odds_v4(p_match_id);
  return true;
end;
$function$;

create or replace function public.trigger_match_odds_v4()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status = 'a_venir' then
      perform public.upsert_match_odds_v4(new.id);
    end if;
  elsif new.status = 'a_venir' and (
    old.opponent_id is distinct from new.opponent_id
    or old.location is distinct from new.location
    or old.match_date is distinct from new.match_date
    or old.status is distinct from new.status
  ) then
    perform public.upsert_match_odds_v4(new.id);
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_auto_match_odds_v4 on public.matches;
create trigger trg_auto_match_odds_v4
after insert or update of opponent_id, location, match_date, status
on public.matches
for each row
execute function public.trigger_match_odds_v4();

-- Replace the preview RPC with a date-aware, backward-compatible signature.
drop function if exists public.preview_match_odds(uuid, text);
create function public.preview_match_odds(
  p_opponent_id uuid,
  p_location text,
  p_reference_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_opponent_id is null then
    raise exception 'Opponent id is required' using errcode = '22023';
  end if;
  if p_location is null or p_location not in ('domicile', 'exterieur') then
    raise exception 'Invalid location' using errcode = '22023';
  end if;
  if p_reference_date is null
     or p_reference_date < date '2000-01-01'
     or p_reference_date > date '2100-12-31' then
    raise exception 'Reference date is outside allowed bounds' using errcode = '22023';
  end if;
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  return public.calculate_match_odds_v5(p_opponent_id, p_reference_date);
end;
$function$;

revoke all on function public.preview_match_odds(uuid, text, date) from public, anon;
grant execute on function public.preview_match_odds(uuid, text, date) to authenticated, service_role;

-- Normalize every future match with the same authoritative write path now.
select public.recalculate_upcoming_match_odds_v4();
