begin;

do $$
declare
  view_options text[];
begin
  if has_function_privilege(
    'anon', 'public.featured_badges()', 'execute'
  ) then
    raise exception 'anon must not execute featured_badges()';
  end if;

  if has_function_privilege(
    'anon', 'public.profile_badge_stars(uuid)', 'execute'
  ) then
    raise exception 'anon must not execute profile_badge_stars(uuid)';
  end if;

  if has_function_privilege(
    'anon', 'public.staff_list_historical_players()', 'execute'
  ) then
    raise exception 'anon must not execute staff_list_historical_players()';
  end if;

  if has_function_privilege(
    'anon', 'public.staff_set_historical_profile(uuid,bigint)', 'execute'
  ) then
    raise exception 'anon must not execute staff_set_historical_profile(uuid,bigint)';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.featured_badges()', 'execute'
  ) then
    raise exception 'authenticated must execute featured_badges()';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.profile_badge_stars(uuid)', 'execute'
  ) then
    raise exception 'authenticated must execute profile_badge_stars(uuid)';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.staff_list_historical_players()', 'execute'
  ) then
    raise exception 'authenticated must execute staff_list_historical_players()';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.staff_set_historical_profile(uuid,bigint)', 'execute'
  ) then
    raise exception 'authenticated must execute staff_set_historical_profile(uuid,bigint)';
  end if;

  select c.reloptions
    into view_options
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'v_statistics_players';

  if not coalesce(view_options @> array['security_invoker=true'], false) then
    raise exception 'v_statistics_players must use security_invoker=true';
  end if;

  if has_table_privilege(
    'anon', 'public.v_statistics_players', 'select'
  ) then
    raise exception 'anon must not select v_statistics_players';
  end if;

  if not has_table_privilege(
    'authenticated', 'public.v_statistics_players', 'select'
  ) then
    raise exception 'authenticated must select v_statistics_players';
  end if;

  if to_regclass('public.profile_badges_awarded_by_idx') is null then
    raise exception 'profile_badges_awarded_by_idx is missing';
  end if;

  if to_regclass('public.profile_badges_badge_id_idx') is null then
    raise exception 'profile_badges_badge_id_idx is missing';
  end if;

  if to_regclass('public.season_awards_profile_id_idx') is null then
    raise exception 'season_awards_profile_id_idx is missing';
  end if;
end
$$;

rollback;
