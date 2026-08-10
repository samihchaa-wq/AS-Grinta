-- Fusion des rôles admin + modérateur en un seul rôle privilégié : « admin ».
-- Il n'existe qu'un seul rôle à droits élevés désormais.

-- Migre d'éventuels modérateurs restants vers admin.
update public.profiles set role = 'admin'
where lower(coalesce(role, '')) in ('moderateur', 'moderator');

-- Restreint les rôles possibles à pronostiqueur / admin.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role = any (array['pronostiqueur'::text, 'admin'::text]));

-- « staff » = « admin actif » (plus de modérateur).
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
$$;
