\set ON_ERROR_STOP on

do $$
declare
  target regprocedure;
  role_name text;
  view_options text[];
begin
  foreach target in array array[
    'public.featured_badges()'::regprocedure,
    'public.profile_badge_stars(uuid)'::regprocedure,
    'public.staff_list_historical_players()'::regprocedure,
    'public.staff_set_historical_profile(uuid,bigint)'::regprocedure
  ] loop
    if not (select p.prosecdef from pg_proc p where p.oid = target) then
      raise exception '% must remain SECURITY DEFINER', target;
    end if;

    if has_function_privilege('anon', target, 'execute') then
      raise exception 'anon must not execute %', target;
    end if;

    foreach role_name in array array['authenticated', 'service_role'] loop
      if not has_function_privilege(role_name, target, 'execute') then
        raise exception '% must execute %', role_name, target;
      end if;
    end loop;
  end loop;

  select c.reloptions into view_options
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'v_statistics_players';

  if not coalesce(view_options @> array['security_invoker=true'], false) then
    raise exception 'v_statistics_players must use security_invoker=true';
  end if;
end
$$;
