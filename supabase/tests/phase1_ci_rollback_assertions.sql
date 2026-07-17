\set ON_ERROR_STOP on

do $$
declare
  target regprocedure;
  view_options text[];
begin
  foreach target in array array[
    'public.featured_badges()'::regprocedure,
    'public.profile_badge_stars(uuid)'::regprocedure,
    'public.staff_list_historical_players()'::regprocedure,
    'public.staff_set_historical_profile(uuid,bigint)'::regprocedure
  ] loop
    if not has_function_privilege('anon', target, 'execute') then
      raise exception 'rollback must restore inherited anon execution on %', target;
    end if;
    if not has_function_privilege('authenticated', target, 'execute') then
      raise exception 'rollback must preserve authenticated execution on %', target;
    end if;
    if not has_function_privilege('service_role', target, 'execute') then
      raise exception 'rollback must preserve service_role execution on %', target;
    end if;
  end loop;

  select c.reloptions into view_options
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'v_statistics_players';

  if coalesce(view_options @> array['security_invoker=true'], false) then
    raise exception 'rollback must remove security_invoker=true';
  end if;

  if to_regclass('public.profile_badges_awarded_by_idx') is not null
     or to_regclass('public.profile_badges_badge_id_idx') is not null
     or to_regclass('public.season_awards_profile_id_idx') is not null then
    raise exception 'rollback must remove the three phase 1 indexes';
  end if;
end
$$;
