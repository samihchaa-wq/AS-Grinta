create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  actor_id uuid := (select auth.uid());
  result jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select to_jsonb(p)
  into result
  from public.profiles p
  where p.id = actor_id;

  if result is null then
    raise exception 'Profile not found' using errcode = '42501';
  end if;

  return result;
end;
$function$;

comment on function public.get_my_profile() is
  'Returns only the authenticated user profile, including non-active statuses so the client can route pending or archived accounts safely.';
