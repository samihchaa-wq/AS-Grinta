-- Test-only compatibility helper. Production is not affected.
-- L’image Supabase locale peut préinstaller pgTAP dans public. On le replace dans
-- extensions avant d’appliquer le verrou applicatif afin que les assertions TAP
-- restent disponibles pendant les simulations de rôles anon/authenticated.
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
