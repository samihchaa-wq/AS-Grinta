-- P0: make match finalization strict, atomic and unambiguous.

create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_player_id uuid default null,
  p_score_as_grinta integer default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  item jsonb;
  match_season_id uuid;
  scorer_id uuid;
  scorer_goals integer;
  total_goals integer := 0;
  scorer_count integer := 0;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta < 0 or p_score_as_grinta > 99
     or p_score_adverse < 0 or p_score_adverse > 99 then
    raise exception 'Scores must be between 0 and 99' using errcode = '22023';
  end if;

  if p_scorers is null or jsonb_typeof(p_scorers) <> 'array' then
    raise exception 'Scorers payload must be a JSON array' using errcode = '22023';
  end if;

  if jsonb_array_length(p_scorers) > 30 then
    raise exception 'Too many scorer entries' using errcode = '22023';
  end if;

  select m.season_id
  into match_season_id
  from public.matches m
  where m.id = p_match_id
    and m.status in ('a_venir', 'termine')
  for update;

  if not found then
    raise exception 'Only upcoming or finished matches can be validated' using errcode = 'P0002';
  end if;

  for item in
    select value from jsonb_array_elements(p_scorers)
  loop
    scorer_count := scorer_count + 1;

    if jsonb_typeof(item) <> 'object' then
      raise exception 'Each scorer entry must be an object' using errcode = '22023';
    end if;

    if not (item ? 'season_player_id') or not (item ? 'goals')
       or exists (
         select 1
         from jsonb_object_keys(item) as key
         where key not in ('season_player_id', 'goals')
       ) then
      raise exception 'Invalid scorer entry schema' using errcode = '22023';
    end if;

    if jsonb_typeof(item->'season_player_id') <> 'string'
       or jsonb_typeof(item->'goals') <> 'number'
       or (item->>'goals') !~ '^[0-9]+$' then
      raise exception 'Invalid scorer entry types' using errcode = '22023';
    end if;

    begin
      scorer_id := (item->>'season_player_id')::uuid;
      scorer_goals := (item->>'goals')::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid scorer entry values' using errcode = '22023';
    end;

    if scorer_goals < 1 or scorer_goals > 99 then
      raise exception 'Scorer goals must be between 1 and 99' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from public.season_players sp
      where sp.id = scorer_id
        and sp.season_id = match_season_id
        and sp.is_active
    ) then
      raise exception 'Scorer is not an active player in the match season' using errcode = '22023';
    end if;

    total_goals := total_goals + scorer_goals;
    if total_goals > 99 or total_goals > p_score_as_grinta then
      raise exception 'Attributed goals exceed the AS Grinta score' using errcode = '22023';
    end if;
  end loop;

  if p_score_as_grinta = 0 and scorer_count > 0 then
    raise exception 'A score of zero cannot contain scorers' using errcode = '22023';
  end if;

  if p_clean_sheet_player_id is not null then
    if p_score_adverse <> 0 then
      raise exception 'Clean sheet is impossible when the opponent scored' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from public.season_players sp
      where sp.id = p_clean_sheet_player_id
        and sp.season_id = match_season_id
        and sp.is_goalkeeper
        and sp.is_active
    ) then
      raise exception 'Clean sheet must belong to an active goalkeeper in the match season' using errcode = '22023';
    end if;
  end if;

  delete from public.match_player_stats
  where match_id = p_match_id;

  insert into public.match_player_stats(
    match_id,
    season_player_id,
    goals,
    clean_sheet
  )
  select
    p_match_id,
    (entry->>'season_player_id')::uuid,
    sum((entry->>'goals')::integer),
    false
  from jsonb_array_elements(p_scorers) as entry
  group by (entry->>'season_player_id')::uuid;

  if p_clean_sheet_player_id is not null then
    insert into public.match_player_stats(
      match_id,
      season_player_id,
      goals,
      clean_sheet
    )
    values (
      p_match_id,
      p_clean_sheet_player_id,
      0,
      true
    )
    on conflict (match_id, season_player_id) do update
    set clean_sheet = true;
  end if;

  update public.matches
  set score_as_grinta = p_score_as_grinta,
      score_adverse = p_score_adverse,
      status = 'termine',
      predictions_closed_at = coalesce(predictions_closed_at, now()),
      result_validated_at = now(),
      updated_at = now()
  where id = p_match_id;

  return true;
end;
$$;

-- Remove the legacy overload that inferred the team score from scorer rows.
drop function if exists public.finalize_match_postgame(uuid, integer, jsonb, uuid);

revoke execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid, integer)
  from public, anon;
grant execute on function public.finalize_match_postgame(uuid, integer, jsonb, uuid, integer)
  to authenticated, service_role;
