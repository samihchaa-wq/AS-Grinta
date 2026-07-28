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

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'seasons'
      and policyname = 'seasons_staff_update'
  ) or not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'seasons'
      and policyname = 'seasons_staff_delete'
  ) then
    raise exception 'Bootstrap assertion failed: season staff RLS policies are missing';
  end if;
end;
$block$;

commit;
