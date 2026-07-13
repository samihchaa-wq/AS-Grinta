-- The match insert trigger creates an initial odds row. Replace that row with
-- the validated values supplied by Flutter instead of inserting a duplicate.

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
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();

  return new_id;
end;
$$;

revoke execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric)
  from public, anon;
grant execute on function public.create_match_with_odds(uuid, uuid, date, time without time zone, text, numeric, numeric, numeric)
  to authenticated, service_role;
