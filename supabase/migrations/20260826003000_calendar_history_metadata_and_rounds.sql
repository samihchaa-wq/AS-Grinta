-- Preserve match identity in the calendar after full time and prepare richer
-- historical imports (SportEasy or any future source).

alter table public.matches
  add column if not exists championship_round integer;

alter table public.matches
  drop constraint if exists matches_championship_round_check;
alter table public.matches
  add constraint matches_championship_round_check
  check (championship_round is null or championship_round > 0);

comment on column public.matches.championship_round is
  'Persistent championship match number (J1, J2, ...). A postponed championship match is appended after the current highest J.';

-- Existing modern championship rows predate the automatic numbering. Give
-- them deterministic numbers before enabling the uniqueness invariant.
with ranked as (
  select
    m.id,
    row_number() over (
      partition by m.season_id
      order by m.match_date, m.match_time, m.id
    )::integer as championship_round
  from public.matches m
  where m.match_type = 'championnat'
)
update public.matches m
set championship_round = ranked.championship_round
from ranked
where ranked.id = m.id
  and m.championship_round is null;

create unique index if not exists matches_season_championship_round_uidx
  on public.matches(season_id, championship_round)
  where match_type = 'championnat' and championship_round is not null;

create or replace function private.assign_match_championship_round()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_next integer;
begin
  if new.match_type <> 'championnat' then
    new.championship_round := null;
    return new;
  end if;

  -- Serialize numbering per season. The season row is a natural lock that
  -- avoids two simultaneous creations receiving the same J number.
  perform 1
  from public.seasons s
  where s.id = new.season_id
  for update;

  if tg_op = 'INSERT' then
    if new.championship_round is null then
      select coalesce(max(m.championship_round), 0) + 1
      into v_next
      from public.matches m
      where m.season_id = new.season_id
        and m.match_type = 'championnat';
      new.championship_round := v_next;
    end if;
    return new;
  end if;

  -- Entering a championship or moving to another season always appends the
  -- match to that season's championship sequence.
  if old.match_type is distinct from 'championnat'
     or old.season_id is distinct from new.season_id then
    select coalesce(max(m.championship_round), 0) + 1
    into v_next
    from public.matches m
    where m.season_id = new.season_id
      and m.match_type = 'championnat'
      and m.id <> new.id;
    new.championship_round := v_next;
    return new;
  end if;

  -- Business rule: when a championship match is postponed to a later date,
  -- it no longer keeps its former J number. It becomes J+1 of the current
  -- highest J (including its own former number when it was the latest one).
  if new.match_date is distinct from old.match_date
     and new.match_date > old.match_date then
    select coalesce(max(m.championship_round), 0) + 1
    into v_next
    from public.matches m
    where m.season_id = new.season_id
      and m.match_type = 'championnat';
    new.championship_round := v_next;
    return new;
  end if;

  if new.championship_round is null then
    new.championship_round := old.championship_round;
  end if;

  if new.championship_round is null then
    select coalesce(max(m.championship_round), 0) + 1
    into v_next
    from public.matches m
    where m.season_id = new.season_id
      and m.match_type = 'championnat'
      and m.id <> new.id;
    new.championship_round := v_next;
  end if;

  return new;
end;
$function$;

revoke all on function private.assign_match_championship_round() from public, anon, authenticated;

drop trigger if exists trg_assign_match_championship_round on public.matches;
create trigger trg_assign_match_championship_round
before insert or update of season_id, match_type, match_date, championship_round
on public.matches
for each row
execute function private.assign_match_championship_round();

-- Historical rows deliberately keep these fields nullable: the existing
-- archive does not know them reliably, and missing information must never be
-- invented. A richer import can fill them later.
alter table public.historical_match_scores
  add column if not exists match_time time without time zone,
  add column if not exists address text,
  add column if not exists match_type text,
  add column if not exists championship_round integer;

alter table public.historical_match_scores
  drop constraint if exists historical_match_scores_match_type_check;
alter table public.historical_match_scores
  add constraint historical_match_scores_match_type_check
  check (
    match_type is null
    or match_type = any (array['amical'::text, 'championnat'::text, 'entre_nous'::text])
  );

alter table public.historical_match_scores
  drop constraint if exists historical_match_scores_championship_round_check;
alter table public.historical_match_scores
  add constraint historical_match_scores_championship_round_check
  check (championship_round is null or championship_round > 0);

comment on column public.historical_match_scores.match_time is
  'Kickoff time from the historical source when known.';
comment on column public.historical_match_scores.address is
  'Historical venue/address from the source when known.';
comment on column public.historical_match_scores.match_type is
  'Historical match type when known: championnat, amical or entre_nous.';
comment on column public.historical_match_scores.championship_round is
  'Historical championship match number (J1, J2, ...) when known.';

-- Return the new metadata through the existing read-only history RPCs.
-- Return types change, so PostgreSQL requires drop/recreate rather than
-- CREATE OR REPLACE.
drop function if exists public.get_all_historical_match_results();
drop function if exists public.get_historical_match_results(text);
drop function if exists private.get_all_historical_match_results();
drop function if exists private.get_historical_match_results(text);

create function private.get_all_historical_match_results()
returns table (
  id uuid,
  match_date date,
  match_time time without time zone,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean,
  address text,
  match_type text,
  championship_round integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select
    h.id,
    h.match_date,
    h.match_time,
    o.name,
    h.score_as_grinta,
    h.score_adverse,
    h.is_home,
    h.address,
    h.match_type,
    h.championship_round
  from public.historical_match_scores h
  join public.opponents o on o.id = h.opponent_id
  order by h.match_date desc, h.match_time desc nulls last, h.id desc;
end;
$function$;

create function private.get_historical_match_results(p_season_name text)
returns table (
  id uuid,
  match_date date,
  match_time time without time zone,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean,
  address text,
  match_type text,
  championship_round integer
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_start_year integer;
  v_end_year integer;
  v_start_date date;
  v_end_date date;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if p_season_name is null or p_season_name !~ '^[0-9]{4}-[0-9]{4}$' then
    raise exception 'Invalid season name' using errcode = '22023';
  end if;

  v_start_year := substring(p_season_name from 1 for 4)::integer;
  v_end_year := substring(p_season_name from 6 for 4)::integer;
  if v_end_year <> v_start_year + 1 then
    raise exception 'Invalid season range' using errcode = '22023';
  end if;

  v_start_date := make_date(v_start_year, 7, 1);
  v_end_date := make_date(v_end_year, 7, 1);

  return query
  select
    h.id,
    h.match_date,
    h.match_time,
    o.name,
    h.score_as_grinta,
    h.score_adverse,
    h.is_home,
    h.address,
    h.match_type,
    h.championship_round
  from public.historical_match_scores h
  join public.opponents o on o.id = h.opponent_id
  where h.match_date >= v_start_date
    and h.match_date < v_end_date
  order by h.match_date desc, h.match_time desc nulls last, h.id desc;
end;
$function$;

revoke all on function private.get_all_historical_match_results() from public, anon;
revoke all on function private.get_historical_match_results(text) from public, anon;
grant execute on function private.get_all_historical_match_results() to authenticated, service_role;
grant execute on function private.get_historical_match_results(text) to authenticated, service_role;

create function public.get_all_historical_match_results()
returns table (
  id uuid,
  match_date date,
  match_time time without time zone,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean,
  address text,
  match_type text,
  championship_round integer
)
language sql
stable
set search_path to ''
as $function$
  select * from private.get_all_historical_match_results();
$function$;

create function public.get_historical_match_results(p_season_name text)
returns table (
  id uuid,
  match_date date,
  match_time time without time zone,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean,
  address text,
  match_type text,
  championship_round integer
)
language sql
stable
set search_path to ''
as $function$
  select * from private.get_historical_match_results(p_season_name);
$function$;

revoke all on function public.get_all_historical_match_results() from public, anon;
revoke all on function public.get_historical_match_results(text) from public, anon;
grant execute on function public.get_all_historical_match_results() to authenticated, service_role;
grant execute on function public.get_historical_match_results(text) to authenticated, service_role;
