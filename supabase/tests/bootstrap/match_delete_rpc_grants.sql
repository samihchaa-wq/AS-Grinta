begin;

revoke execute on function public.delete_match(uuid) from public, anon;
grant execute on function public.delete_match(uuid) to authenticated, service_role;

do $block$
begin
  if has_function_privilege(
    'anon',
    'public.delete_match(uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Bootstrap assertion failed: anon can execute delete_match';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.delete_match(uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Bootstrap assertion failed: authenticated cannot execute delete_match';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.delete_match(uuid)'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'Bootstrap assertion failed: service_role cannot execute delete_match';
  end if;
end;
$block$;

commit;
