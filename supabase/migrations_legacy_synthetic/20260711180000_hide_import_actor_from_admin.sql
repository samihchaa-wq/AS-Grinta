-- Le compte technique d'import historique ne doit ni apparaître dans
-- l'administration ni pouvoir être réactivé par erreur.
update public.profiles
set role = 'admin', status = 'archived', updated_at = now()
where id = '00000000-0000-0000-0000-000000000001';

drop function if exists public.staff_list_profiles();
create function public.staff_list_profiles()
returns table(
  id uuid, first_name text, last_name text, surnom text, username text,
  password_set boolean, photo_url text, role text, is_goalkeeper boolean,
  status text, created_at timestamptz, updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.first_name, p.last_name, p.surnom, p.username,
         p.password_set, p.photo_url, p.role, p.is_goalkeeper,
         p.status, p.created_at, p.updated_at
  from public.profiles p
  where public.is_match_staff()
    and p.id <> '00000000-0000-0000-0000-000000000001'
  order by p.first_name, p.last_name;
$$;

revoke all on function public.staff_list_profiles() from public, anon;
grant execute on function public.staff_list_profiles() to authenticated;
