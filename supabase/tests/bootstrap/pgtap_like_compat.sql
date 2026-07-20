-- Test-only compatibility helper. Production is not affected.
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
