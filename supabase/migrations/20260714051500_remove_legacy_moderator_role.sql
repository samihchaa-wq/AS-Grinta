-- The application has a single privileged role: active admin.

update public.profiles
set role = 'admin'
where lower(coalesce(role, '')) in ('moderateur', 'moderator');

alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role in ('pronostiqueur', 'admin'));

alter policy matches_authorized_update
on public.matches
using ((select private.is_admin()) and status <> 'archive')
with check ((select private.is_admin()));

alter policy opponents_admin_insert
on public.opponents
with check ((select private.is_admin()));

alter policy opponents_moderator_update
on public.opponents
rename to opponents_admin_update;

alter policy opponents_admin_update
on public.opponents
using ((select private.is_admin()))
with check ((select private.is_admin()));

alter policy opponents_moderator_delete
on public.opponents
rename to opponents_admin_delete;

alter policy opponents_admin_delete
on public.opponents
using ((select private.is_admin()));

drop function if exists public.is_moderator();
drop function if exists private.is_moderator();
