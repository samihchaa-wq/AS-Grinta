-- The private profile-photo policy introduced next depends on this helper.
-- Production already has the function; CREATE OR REPLACE keeps its existing
-- privileges there and makes the isolated migration test self-contained.

create schema if not exists private;

create or replace function private.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.profiles profile
    where profile.id = (select auth.uid())
      and profile.status = 'active'
  );
$$;
