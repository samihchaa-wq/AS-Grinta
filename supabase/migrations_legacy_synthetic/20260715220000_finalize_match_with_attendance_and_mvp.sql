-- Enregistre le résultat, la feuille de match et l'homme du match dans une
-- seule transaction. Les buteurs, le gardien crédité du clean sheet et le HDM
-- doivent tous faire partie des joueurs déclarés présents.

create or replace function public.finalize_match_postgame_with_lineup(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_player_id uuid default null,
  p_score_as_grinta integer default null,
  p_present uuid[] default '{}'::uuid[],
  p_man_of_match_player_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_scorer jsonb;
  v_scorer_id uuid;
  v_mvp_players uuid[];
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  if p_present is null or cardinality(p_present) = 0 then
    raise exception 'At least one present player is required' using errcode = '22023';
  end if;

  if array_position(p_present, null) is not null then
    raise exception 'Present players cannot contain null values' using errcode = '22023';
  end if;

  if p_scorers is null or jsonb_typeof(p_scorers) <> 'array' then
    raise exception 'Scorers payload must be a JSON array' using errcode = '22023';
  end if;

  for v_scorer in select value from jsonb_array_elements(p_scorers)
  loop
    begin
      v_scorer_id := (v_scorer->>'season_player_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid scorer player id' using errcode = '22023';
    end;

    if not (v_scorer_id = any(p_present)) then
      raise exception 'Every scorer must be marked as present' using errcode = '22023';
    end if;
  end loop;

  if p_clean_sheet_player_id is not null
     and not (p_clean_sheet_player_id = any(p_present)) then
    raise exception 'The clean sheet goalkeeper must be marked as present'
      using errcode = '22023';
  end if;

  if p_man_of_match_player_id is not null
     and not (p_man_of_match_player_id = any(p_present)) then
    raise exception 'The man of the match must be marked as present'
      using errcode = '22023';
  end if;

  perform public.staff_set_match_attendance(p_match_id, p_present);

  v_mvp_players := case
    when p_man_of_match_player_id is null then '{}'::uuid[]
    else array[p_man_of_match_player_id]
  end;
  perform public.staff_set_match_mvp(p_match_id, v_mvp_players);

  return public.finalize_match_postgame(
    p_match_id,
    p_score_adverse,
    p_scorers,
    p_clean_sheet_player_id,
    p_score_as_grinta
  );
end;
$function$;

revoke all on function public.finalize_match_postgame_with_lineup(
  uuid, integer, jsonb, uuid, integer, uuid[], uuid
) from public, anon;

grant execute on function public.finalize_match_postgame_with_lineup(
  uuid, integer, jsonb, uuid, integer, uuid[], uuid
) to authenticated;

comment on function public.finalize_match_postgame_with_lineup(
  uuid, integer, jsonb, uuid, integer, uuid[], uuid
) is 'Enregistre atomiquement le résultat, les joueurs présents et le HDM.';
