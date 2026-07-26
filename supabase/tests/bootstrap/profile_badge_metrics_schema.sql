-- Contrat minimal de l’exception de lecture surveillée par la matrice
-- SECURITY DEFINER. Les calculs métier complets sont couverts par les migrations
-- de badges ; cette base isolée a seulement besoin de la signature et des droits.

create or replace function public.profile_badge_metrics(p_profile_id uuid)
returns table (
  metric_key text,
  metric_value bigint
)
language sql
stable
security definer
set search_path to ''
as $function$
  select null::text, null::bigint
  where false;
$function$;

revoke all on function public.profile_badge_metrics(uuid)
  from public, anon;
grant execute on function public.profile_badge_metrics(uuid)
  to authenticated, service_role;
