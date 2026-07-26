-- Implémentation minimale fidèle du nettoyage des abonnements expirés.
-- La production possède cette fonction depuis la migration Web Push ; ce
-- bootstrap permet au test d’intégrité de s’exécuter dans le schéma isolé.

create or replace function public.internal_push_prune(p_endpoints text[])
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_deleted integer;
begin
  delete from public.push_subscriptions
  where endpoint = any(coalesce(p_endpoints, '{}'::text[]));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

revoke all on function public.internal_push_prune(text[])
  from public, anon, authenticated;
grant execute on function public.internal_push_prune(text[])
  to service_role;
