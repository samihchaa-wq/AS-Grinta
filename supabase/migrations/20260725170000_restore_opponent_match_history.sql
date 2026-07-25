begin;

create or replace function public.get_last_opponent_encounters(p_match_id uuid)
returns table (
  encounter_date date,
  grinta_score integer,
  opponent_score integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_opponent_id uuid;
  v_reference_date date;
begin
  if not public.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select m.opponent_id, m.match_date
  into v_opponent_id, v_reference_date
  from public.matches m
  where m.id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  return query
  with all_results as (
    select
      m.id,
      m.match_date,
      m.score_as_grinta::integer as score_as_grinta,
      m.score_adverse::integer as score_adverse
    from public.matches m
    where m.opponent_id = v_opponent_id
      and m.status in ('termine', 'archive')
      and m.score_as_grinta is not null
      and m.score_adverse is not null

    union all

    select
      h.id,
      h.match_date,
      h.score_as_grinta::integer as score_as_grinta,
      h.score_adverse::integer as score_adverse
    from public.historical_match_scores h
    where h.opponent_id = v_opponent_id
  ), deduplicated as (
    select distinct on (r.id)
      r.id,
      r.match_date,
      r.score_as_grinta,
      r.score_adverse
    from all_results r
    order by r.id, r.match_date desc
  )
  select
    d.match_date,
    d.score_as_grinta,
    d.score_adverse
  from deduplicated d
  where d.match_date < v_reference_date
  order by d.match_date desc, d.id desc
  limit 5;
end;
$$;

comment on function public.get_last_opponent_encounters(uuid) is
  'Returns the five latest completed matches against the opponent of a match, including compacted history.';

revoke execute on function public.get_last_opponent_encounters(uuid) from public, anon;
grant execute on function public.get_last_opponent_encounters(uuid) to authenticated, service_role;

commit;
