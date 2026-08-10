-- P0: harden match and odds RPCs and restore the participant-count contract.

create or replace function public.match_prediction_participant_count(p_match_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.matches m where m.id = p_match_id) then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return (
    select count(*)::integer
    from public.match_predictions mp
    where mp.match_id = p_match_id and mp.is_filled
  );
end;
$$;

create or replace function public.get_or_create_opponent(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_name text := btrim(coalesce(p_name, ''));
  opponent_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if length(normalized_name) < 2 or length(normalized_name) > 100 then
    raise exception 'Opponent name must contain between 2 and 100 characters' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(normalized_name), 0));

  select o.id into opponent_id
  from public.opponents o
  where lower(btrim(o.name)) = lower(normalized_name)
  limit 1;

  if opponent_id is null then
    insert into public.opponents(name)
    values (normalized_name)
    returning id into opponent_id;
  end if;

  return opponent_id;
end;
$$;

create or replace function public.preview_match_odds(p_opponent_id uuid, p_location text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
  if not exists (select 1 from public.opponents o where o.id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;
  return public.calculate_match_odds_v4(p_opponent_id, p_location);
end;
$$;

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
set search_path = ''
as $$
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
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds' using errcode = '22023';
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

  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul,
    odds_victoire_adverse, computed_at
  ) values (
    new_id, round(p_win, 2), round(p_draw, 2), round(p_loss, 2), now()
  );

  return new_id;
end;
$$;

create or replace function public.set_match_odds(
  p_match_id uuid,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.status = 'a_venir'
  ) then
    raise exception 'Upcoming match not found' using errcode = 'P0002';
  end if;

  insert into public.match_odds(
    match_id, odds_victoire_as_grinta, odds_nul,
    odds_victoire_adverse, computed_at
  ) values (
    p_match_id, round(p_win, 2), round(p_draw, 2), round(p_loss, 2), now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();

  return true;
end;
$$;

create or replace function public.close_match_predictions(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  update public.matches
  set predictions_closed_at = now(), updated_at = now()
  where id = p_match_id
    and status = 'a_venir'
    and predictions_closed_at is null;
  if not found then
    raise exception 'Open upcoming match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;

create or replace function public.archive_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  update public.matches
  set status = 'archive', updated_at = now()
  where id = p_match_id and status <> 'archive';
  if not found then
    raise exception 'Non-archived match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;

create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  delete from public.matches
  where id = p_match_id and status = 'a_venir';
  if not found then
    raise exception 'Only an upcoming match can be deleted' using errcode = 'P0002';
  end if;
  return true;
end;
$$;

revoke execute on function public.match_prediction_participant_count(uuid) from public, anon;
revoke execute on function public.get_or_create_opponent(text) from public, anon;
revoke execute on function public.preview_match_odds(uuid, text) from public, anon;
revoke execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) from public, anon;
revoke execute on function public.set_match_odds(uuid, numeric, numeric, numeric) from public, anon;
revoke execute on function public.close_match_predictions(uuid) from public, anon;
revoke execute on function public.archive_match(uuid) from public, anon;
revoke execute on function public.delete_match(uuid) from public, anon;

grant execute on function public.match_prediction_participant_count(uuid) to authenticated, service_role;
grant execute on function public.get_or_create_opponent(text) to authenticated, service_role;
grant execute on function public.preview_match_odds(uuid, text) to authenticated, service_role;
grant execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric) to authenticated, service_role;
grant execute on function public.set_match_odds(uuid, numeric, numeric, numeric) to authenticated, service_role;
grant execute on function public.close_match_predictions(uuid) to authenticated, service_role;
grant execute on function public.archive_match(uuid) to authenticated, service_role;
grant execute on function public.delete_match(uuid) to authenticated, service_role;
