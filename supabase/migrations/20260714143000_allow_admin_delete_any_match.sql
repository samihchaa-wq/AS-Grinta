begin;

create or replace function public.delete_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  delete from public.matches
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  return true;
end;
$$;

revoke all on function public.delete_match(uuid) from public, anon;
grant execute on function public.delete_match(uuid) to authenticated;

commit;
