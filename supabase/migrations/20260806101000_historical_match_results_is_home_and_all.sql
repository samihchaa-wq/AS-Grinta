-- Ajoute le lieu (domicile/extérieur) aux résultats historiques renvoyés par
-- get_historical_match_results, et ajoute une RPC pour récupérer tout
-- l'historique du club en une fois (utilisée par le calendrier « Défilé »).

drop function if exists private.get_historical_match_results(text);
drop function if exists public.get_historical_match_results(text);

create function private.get_historical_match_results(
  p_season_name text
)
returns table (
  id uuid,
  match_date date,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean
)
language plpgsql
stable
security definer
set search_path = ''
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
  select h.id, h.match_date, o.name, h.score_as_grinta, h.score_adverse, h.is_home
  from public.historical_match_scores h
  join public.opponents o on o.id = h.opponent_id
  where h.match_date >= v_start_date
    and h.match_date < v_end_date
  order by h.match_date desc, h.id desc;
end;
$function$;

revoke all on function private.get_historical_match_results(text) from public, anon;
grant execute on function private.get_historical_match_results(text) to authenticated, service_role;

create function public.get_historical_match_results(
  p_season_name text
)
returns table (
  id uuid,
  match_date date,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select * from private.get_historical_match_results(p_season_name);
$function$;

revoke all on function public.get_historical_match_results(text) from public, anon;
grant execute on function public.get_historical_match_results(text) to authenticated, service_role;

comment on function public.get_historical_match_results(text) is
  'Read-only compact match history for one YYYY-YYYY season; authorization is enforced by a private helper.';

-- Historique complet (toutes saisons confondues), pour le calendrier Défilé.

create function private.get_all_historical_match_results()
returns table (
  id uuid,
  match_date date,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select h.id, h.match_date, o.name, h.score_as_grinta, h.score_adverse, h.is_home
  from public.historical_match_scores h
  join public.opponents o on o.id = h.opponent_id
  order by h.match_date desc, h.id desc;
end;
$function$;

revoke all on function private.get_all_historical_match_results() from public, anon;
grant execute on function private.get_all_historical_match_results() to authenticated, service_role;

create function public.get_all_historical_match_results()
returns table (
  id uuid,
  match_date date,
  opponent_name text,
  score_as_grinta smallint,
  score_adverse smallint,
  is_home boolean
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select * from private.get_all_historical_match_results();
$function$;

revoke all on function public.get_all_historical_match_results() from public, anon;
grant execute on function public.get_all_historical_match_results() to authenticated, service_role;

comment on function public.get_all_historical_match_results() is
  'Read-only compact match history across every archived season; authorization is enforced by a private helper.';
