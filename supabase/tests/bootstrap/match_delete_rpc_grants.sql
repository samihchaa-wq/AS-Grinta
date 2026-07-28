begin;

create or replace function public.archive_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  update public.matches
  set status = 'archive', updated_at = now()
  where id = p_match_id and status <> 'archive';
  if not found then
    raise exception 'Non-archived match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$function$;

revoke execute on function public.archive_match(uuid) from public, anon;
revoke execute on function public.delete_match(uuid) from public, anon;
grant execute on function public.archive_match(uuid) to authenticated, service_role;
grant execute on function public.delete_match(uuid) to authenticated, service_role;

do $block$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.archive_match(uuid)',
    'public.delete_match(uuid)'
  ]
  loop
    if has_function_privilege(
      'anon',
      v_signature::regprocedure,
      'EXECUTE'
    ) then
      raise exception 'Bootstrap assertion failed: anon can execute %', v_signature;
    end if;

    if not has_function_privilege(
      'authenticated',
      v_signature::regprocedure,
      'EXECUTE'
    ) then
      raise exception 'Bootstrap assertion failed: authenticated cannot execute %', v_signature;
    end if;

    if not has_function_privilege(
      'service_role',
      v_signature::regprocedure,
      'EXECUTE'
    ) then
      raise exception 'Bootstrap assertion failed: service_role cannot execute %', v_signature;
    end if;
  end loop;
end;
$block$;

commit;
