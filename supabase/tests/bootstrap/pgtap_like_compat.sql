-- Test-only compatibility helper. Production is not affected.
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
