-- Fix championship round numbering when a match is postponed.
--
-- A postponed championship match must be appended after the highest OTHER
-- championship round in the season. Friendlies/internal matches never count,
-- and the match being edited must not increment itself (J1 -> J2 when it is
-- the only championship fixture was the regression fixed here).

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
  -- it becomes J+1 of the highest OTHER championship round. Excluding the
  -- edited match prevents a lone/latest J from incrementing itself merely
  -- because its date moved later. Non-championship fixtures never count.
  if new.match_date is distinct from old.match_date
     and new.match_date > old.match_date then
    select coalesce(max(m.championship_round), 0) + 1
    into v_next
    from public.matches m
    where m.season_id = new.season_id
      and m.match_type = 'championnat'
      and m.id <> new.id;
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
