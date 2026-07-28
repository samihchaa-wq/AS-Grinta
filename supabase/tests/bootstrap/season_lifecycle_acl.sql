begin;

grant select, insert, update, delete
on table public.seasons
to authenticated;

do $block$
begin
  if not has_table_privilege('authenticated', 'public.seasons', 'SELECT')
     or not has_table_privilege('authenticated', 'public.seasons', 'INSERT')
     or not has_table_privilege('authenticated', 'public.seasons', 'UPDATE')
     or not has_table_privilege('authenticated', 'public.seasons', 'DELETE') then
    raise exception 'Bootstrap assertion failed: season ACL differs from production';
  end if;

  if not (
    select relrowsecurity
    from pg_class
    where oid = 'public.seasons'::regclass
  ) then
    raise exception 'Bootstrap assertion failed: RLS is disabled on seasons';
  end if;
end;
$block$;

commit;
