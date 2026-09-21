begin;

-- La baseline locale reproduit les ACL et politiques actuellement présentes
-- en production pour l'administration des saisons.
grant select, insert, update, delete
on table public.seasons
to authenticated;

drop policy if exists seasons_staff_insert on public.seasons;
create policy seasons_staff_insert
on public.seasons for insert to authenticated
with check ((select private.is_match_staff()));

drop policy if exists seasons_staff_update on public.seasons;
create policy seasons_staff_update
on public.seasons for update to authenticated
using ((select private.is_match_staff()))
with check ((select private.is_match_staff()));

drop policy if exists seasons_staff_delete on public.seasons;
create policy seasons_staff_delete
on public.seasons for delete to authenticated
using ((select private.is_match_staff()));

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

  if (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'seasons'
      and policyname in (
        'seasons_staff_insert',
        'seasons_staff_update',
        'seasons_staff_delete'
      )
  ) <> 3 then
    raise exception 'Bootstrap assertion failed: season staff policies differ from production';
  end if;
end;
$block$;

commit;
