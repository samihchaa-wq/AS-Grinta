-- Test-only compatibility helpers. Production is not affected.
-- The local Supabase image does not always preinstall pgTAP. Install it in the
-- isolated CI database and keep it outside public so application security tests
-- can switch between anon/authenticated roles safely.
create extension if not exists pgtap with schema extensions;
alter extension pgtap set schema extensions;

create or replace function public.like(
  p_value text,
  p_pattern text,
  p_description text
)
returns text
language sql
as $function$
  select extensions.ok(p_value like p_pattern, p_description);
$function$;

-- Historical tests use the three-argument form as
-- throws_ok(sql, SQLSTATE, description). Native pgTAP interprets its third
-- argument as an exact error message. Keep these assertions focused on the
-- stable security contract: the expected SQLSTATE.
create or replace function public.throws_ok(
  p_sql text,
  p_expected_state text,
  p_description text
)
returns text
language plpgsql
as $function$
begin
  execute p_sql;
  return extensions.ok(false, p_description);
exception
  when others then
    return extensions.ok(sqlstate = p_expected_state, p_description);
end;
$function$;
