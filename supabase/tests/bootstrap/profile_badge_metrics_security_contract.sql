-- Fixture minimale : le test de sécurité vérifie uniquement l’exposition et les
-- colonnes de sortie. Les calculs complets sont couverts par les migrations et
-- tests dédiés aux badges.

create or replace function public.profile_badge_metrics(p_profile_id uuid)
returns table(total_points bigint)
language sql
stable
security definer
set search_path to ''
as $function$
  select 0::bigint;
$function$;

revoke all on function public.profile_badge_metrics(uuid) from public, anon;
grant execute on function public.profile_badge_metrics(uuid) to authenticated, service_role;
