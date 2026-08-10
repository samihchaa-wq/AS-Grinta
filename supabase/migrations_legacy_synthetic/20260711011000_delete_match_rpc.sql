begin;

create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  deleted_count integer;
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  delete from public.matches
  where id=p_match_id;

  get diagnostics deleted_count = row_count;
  return deleted_count=1;
end;
$$;

revoke all on function public.delete_match(uuid) from public,anon;
grant execute on function public.delete_match(uuid) to authenticated;

commit;
