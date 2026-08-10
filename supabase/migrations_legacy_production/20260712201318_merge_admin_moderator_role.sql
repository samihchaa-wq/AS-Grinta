update public.profiles set role = 'admin'
where lower(coalesce(role, '')) in ('moderateur', 'moderator');

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role = any (array['pronostiqueur'::text, 'admin'::text]));

create or replace function public.is_match_staff()
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role::text, '')) = 'admin'
      and lower(coalesce(p.status::text, 'active')) = 'active'
  );
$$;;
