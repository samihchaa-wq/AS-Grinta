-- Saisie du match : le score d'AS Grinta est choisi par l'admin (et non plus
-- déduit du nombre de buteurs). Les buteurs restent une attribution facultative
-- des buts : on peut en laisser sans buteur (buts non attribués).
--
-- Nouveau paramètre p_score_as_grinta (à la fin, valeur par défaut NULL pour ne
-- pas casser d'anciens appels : si NULL on retombe sur la somme des buts).
create or replace function public.finalize_match_postgame(
  p_match_id uuid,
  p_score_adverse integer,
  p_scorers jsonb,
  p_clean_sheet_player_id uuid default null::uuid,
  p_score_as_grinta integer default null::integer
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  item jsonb;
  match_season_id uuid;
  pid uuid;
  g integer;
  total_goals integer := 0;
  v_grinta integer;
begin
  if not public.is_admin() then
    raise exception 'Admin role required';
  end if;
  if p_score_adverse < 0 then
    raise exception 'Score adverse invalide';
  end if;

  select season_id into match_season_id
  from public.matches
  where id = p_match_id and status in ('a_venir', 'termine')
  for update;
  if match_season_id is null then
    raise exception 'Only upcoming or finished matches can be validated';
  end if;

  if jsonb_typeof(coalesce(p_scorers, '[]'::jsonb)) <> 'array' then
    raise exception 'Invalid scorers payload';
  end if;

  for item in
    select * from jsonb_array_elements(coalesce(p_scorers, '[]'::jsonb))
  loop
    pid := nullif(item->>'season_player_id', '')::uuid;
    g := coalesce((item->>'goals')::integer, 0);
    if pid is null then
      raise exception 'Invalid scorer identifier';
    end if;
    if g < 0 then
      raise exception 'Negative goals are not allowed';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = pid and sp.season_id = match_season_id
    ) then
      raise exception 'Scorer is not in the season squad';
    end if;
    total_goals := total_goals + g;
  end loop;

  -- Score AS Grinta : choisi si fourni, sinon somme des buts (compat).
  v_grinta := coalesce(p_score_as_grinta, total_goals);
  if v_grinta < 0 then
    raise exception 'Score AS Grinta invalide';
  end if;
  -- On ne peut pas attribuer plus de buts que le score.
  if total_goals > v_grinta then
    raise exception 'More goals attributed than the AS Grinta score';
  end if;

  if p_clean_sheet_player_id is not null then
    if p_score_adverse > 0 then
      raise exception 'Clean sheet is impossible when the opponent scored';
    end if;
    if not exists (
      select 1 from public.season_players sp
      where sp.id = p_clean_sheet_player_id
        and sp.season_id = match_season_id
        and sp.is_goalkeeper
    ) then
      raise exception 'Clean sheet must go to a goalkeeper of the squad';
    end if;
  end if;

  delete from public.match_player_stats where match_id = p_match_id;

  insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
  select p_match_id, s.season_player_id, s.goals, false
  from (
    select nullif(e->>'season_player_id', '')::uuid as season_player_id,
           sum(coalesce((e->>'goals')::integer, 0)) as goals
    from jsonb_array_elements(coalesce(p_scorers, '[]'::jsonb)) e
    group by 1
  ) s
  where s.goals > 0;

  if p_clean_sheet_player_id is not null then
    insert into public.match_player_stats(match_id, season_player_id, goals, clean_sheet)
    values (p_match_id, p_clean_sheet_player_id, 0, true)
    on conflict (match_id, season_player_id) do update set clean_sheet = true;
  end if;

  update public.matches
  set score_as_grinta = v_grinta,
      score_adverse = p_score_adverse,
      status = 'termine',
      result_validated_at = now(),
      updated_at = now()
  where id = p_match_id and status in ('a_venir', 'termine');

  return found;
end;
$function$;
