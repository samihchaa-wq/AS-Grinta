create or replace function public.prepare_profile_for_hard_deletion(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.prepare_profile_for_hard_deletion(p_profile_id);
end;
$function$;

revoke all on function public.prepare_profile_for_hard_deletion(uuid) from public, anon, authenticated;
grant execute on function public.prepare_profile_for_hard_deletion(uuid) to service_role;
